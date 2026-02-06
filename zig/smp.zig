const acpi = @import("drivers/acpi.zig");
const memory = @import("memory.zig");
const common = @import("commands/common.zig");

const TRAMPOLINE_ADDR = 0x8000;
const FLAG_ADDR = 0x9000;
const MAILBOX_STACK = 0x7000;
const MAILBOX_ENTRY = 0x7004;

pub const Task = struct {
    func: *const fn (usize) void,
    arg: usize,
};

var task_queue: [16]?Task = [_]?Task{null} ** 16;
var queue_lock: u32 = 0; // 0 = free, 1 = locked
var print_lock: u32 = 0;
pub var detected_cores: u32 = 1;

const trampoline_bin = @embedFile("trampoline.bin");
var ap_stacks: [4][8192]u8 align(4096) = undefined;

pub const CpuInfo = struct {
    vendor: [13]u8,
    brand: [49]u8 align(4),
    family: u32,
    model: u32,
    stepping: u32,
};

pub fn get_online_cores() u8 {
    const flag_ptr = @as(*volatile u32, @ptrFromInt(FLAG_ADDR));
    return @intCast(flag_ptr.* + 1); // +1 for the BSP (this core)
}

fn spin_lock(lock: *volatile u32) void {
    while (@atomicRmw(u32, lock, .Xchg, 1, .acquire) == 1) {
        asm volatile ("pause");
    }
}

fn spin_unlock(lock: *volatile u32) void {
    @atomicStore(u32, lock, 0, .release);
}

pub fn lock_print() void {
    spin_lock(&print_lock);
}

pub fn unlock_print() void {
    spin_unlock(&print_lock);
}

pub fn push_task(func: *const fn (usize) void, arg: usize) bool {
    spin_lock(&queue_lock);
    defer spin_unlock(&queue_lock);

    for (&task_queue) |*slot| {
        if (slot.* == null) {
            slot.* = Task{ .func = func, .arg = arg };
            return true;
        }
    }
    return false;
}

fn pop_task() ?Task {
    spin_lock(&queue_lock);
    defer spin_unlock(&queue_lock);

    for (&task_queue) |*slot| {
        if (slot.*) |t| {
            slot.* = null;
            return t;
        }
    }
    return null;
}

pub export fn ap_kernel_entry() noreturn {
    // This is called by APs after they switch to 32-bit mode
    while (true) {
        if (pop_task()) |task| {
            task.func(task.arg);
        } else {
            asm volatile ("pause");
        }
    }
}

pub fn get_cpu_info() CpuInfo {
    var info: CpuInfo = undefined;

    // 1. Get Vendor String
    var eax: u32 = 0;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    asm volatile ("cpuid"
        : [eax_out] "={eax}" (eax),
          [ebx_out] "={ebx}" (ebx),
          [ecx_out] "={ecx}" (ecx),
          [edx_out] "={edx}" (edx),
        : [eax_in] "{eax}" (eax),
    );

    @memcpy(info.vendor[0..4], @as([*]const u8, @ptrCast(&ebx))[0..4]);
    @memcpy(info.vendor[4..8], @as([*]const u8, @ptrCast(&edx))[0..4]);
    @memcpy(info.vendor[8..12], @as([*]const u8, @ptrCast(&ecx))[0..4]);
    info.vendor[12] = 0;

    // 2. Get Family/Model/Stepping
    var eax2: u32 = 1;
    var ebx2: u32 = undefined;
    var ecx2: u32 = undefined;
    var edx2: u32 = undefined;
    asm volatile ("cpuid"
        : [eax_out] "={eax}" (eax2),
          [ebx_out] "={ebx}" (ebx2),
          [ecx_out] "={ecx}" (ecx2),
          [edx_out] "={edx}" (edx2),
        : [eax_in] "{eax}" (eax2),
    );
    info.stepping = eax2 & 0xF;
    info.model = (eax2 >> 4) & 0xF;
    info.family = (eax2 >> 8) & 0xF;
    if (info.family == 15) info.family += (eax2 >> 20) & 0xFF;
    if (info.family == 6 or info.family == 15) info.model += ((eax2 >> 16) & 0xF) << 4;

    // 3. Get Brand String (if supported)
    var eax3: u32 = 0x80000000;
    var ebx3: u32 = undefined;
    var ecx3: u32 = undefined;
    var edx3: u32 = undefined;
    asm volatile ("cpuid"
        : [eax_out] "={eax}" (eax3),
          [ebx_out] "={ebx}" (ebx3),
          [ecx_out] "={ecx}" (ecx3),
          [edx_out] "={edx}" (edx3),
        : [eax_in] "{eax}" (eax3),
    );

    if (eax3 >= 0x80000004) {
        var brand_ptr = @as([*]u32, @ptrCast(&info.brand));
        var i: u32 = 0;
        while (i < 3) : (i += 1) {
            var ra: u32 = undefined;
            var rb: u32 = undefined;
            var rc: u32 = undefined;
            var rd: u32 = undefined;
            const leaf = 0x80000002 + i;
            asm volatile ("cpuid"
                : [eax_out] "={eax}" (ra),
                  [ebx_out] "={ebx}" (rb),
                  [ecx_out] "={ecx}" (rc),
                  [edx_out] "={edx}" (rd),
                : [eax_in] "{eax}" (leaf),
            );
            brand_ptr[i * 4 + 0] = ra;
            brand_ptr[i * 4 + 1] = rb;
            brand_ptr[i * 4 + 2] = rc;
            brand_ptr[i * 4 + 3] = rd;
        }
        info.brand[48] = 0;
    } else {
        @memcpy(info.brand[0..7], "Unknown");
        info.brand[7] = 0;
    }

    return info;
}

pub fn init() void {
    common.printZ("SMP: Initializing Parallel SMP...\n");

    // 1. Prepare Trampoline Code
    const tramp_ptr = @as([*]u8, @ptrFromInt(TRAMPOLINE_ADDR));
    @memcpy(tramp_ptr[0..trampoline_bin.len], trampoline_bin);

    // 2. Reset the Flag (Now a 32-bit counter)
    const flag_ptr = @as(*volatile u32, @ptrFromInt(FLAG_ADDR));
    flag_ptr.* = 0;

    // 3. Setup Mailbox for APs
    const mailbox_stack = @as(*volatile u32, @ptrFromInt(MAILBOX_STACK));
    const mailbox_entry = @as(*volatile u32, @ptrFromInt(MAILBOX_ENTRY));
    mailbox_entry.* = @intFromPtr(&ap_kernel_entry);

    // 4. Get LAPIC Address
    var lapic_base = acpi.lapic_addr;
    if (lapic_base == 0) {
        lapic_base = 0xFEE00000; // Default
        common.printZ("SMP: MADT not found, using default LAPIC base 0xFEE00000\n");
        detected_cores = 1;
    } else {
        detected_cores = acpi.madt_core_count;
    }

    // 5. Map LAPIC
    if (!memory.map_page(lapic_base)) {
        common.printZ("SMP: Failed to map LAPIC memory! Aborting.\n");
        return;
    }

    // 6. Send IPIs
    const lapic = @as([*]volatile u32, @ptrFromInt(lapic_base));
    const ICR_LOW = 0x300 / 4;
    const ICR_HIGH = 0x310 / 4;

    lapic[ICR_HIGH] = 0;
    lapic[ICR_LOW] = 0x000C4500;
    common.sleep(10);

    // We wake up cores ONE BY ONE to assign them stacks properly
    var ap_count: u32 = 0;
    for (acpi.lapic_ids[0..acpi.madt_core_count]) |id| {
        // Skip BSP (usually ID 0, but technically we check against our current ID)
        if (id == 0) continue;

        const stack_top = @intFromPtr(&ap_stacks[ap_count]) + 8192;
        mailbox_stack.* = stack_top;

        const last_flag = flag_ptr.*;

        common.printZ("SMP: Waking AP core ID ");
        common.printNum(@intCast(id));
        common.printZ(" with separate stack...\n");

        // Send SIPI to SPECIFIC core
        lapic[ICR_HIGH] = @as(u32, id) << 24;
        lapic[ICR_LOW] = 0x00004608; // Destination: ID in ICR_HIGH

        // WAIT for this specific core to report "READY"
        var timeout: u32 = 0;
        while (flag_ptr.* == last_flag and timeout < 1000) : (timeout += 1) {
            common.sleep(1);
        }

        if (flag_ptr.* > last_flag) {
            ap_count += 1;
        } else {
            common.printZ("SMP: WARNING - Core ");
            common.printNum(@intCast(id));
            common.printZ(" failed to respond.\n");
        }
    }

    // 7. Check Flag
    const online = get_online_cores();
    if (online > 1) {
        common.printZ("SMP: SUCCESS! ");
        common.printNum(@intCast(online - 1));
        common.printZ(" AP core(s) joined the kernel!\n");
    } else {
        common.printZ("SMP: FAILURE. Core(s) did not join.\n");
    }
}
