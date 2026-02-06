const acpi = @import("drivers/acpi.zig");
const memory = @import("memory.zig");
const common = @import("commands/common.zig");
const scheduler = @import("scheduler.zig");

const TRAMPOLINE_ADDR = 0x8000;
const FLAG_ADDR = 0x9000;
const MAILBOX_STACK = 0x7000;
const MAILBOX_ENTRY = 0x7004;
const MAILBOX_ID = 0x7008;

// LAPIC Registers
const LAPIC_TIMER = 0x320;
const LAPIC_TDCR = 0x3E0;
const LAPIC_TICR = 0x380;
const LAPIC_TCCR = 0x390;

extern fn switch_context(current: *usize, next: usize) void;
extern fn start_task_asm(next: usize) noreturn;
extern fn gdt_load() void;
extern fn idt_load() void;

pub fn enable_paging_ap() void {
    const pd_addr = @intFromPtr(&memory.page_directory);
    var dummy: u32 = undefined;
    asm volatile (
        \\mov %%cr4, %%eax
        \\or $0x10, %%eax
        \\mov %%eax, %%cr4
        \\mov %[pd], %%cr3
        \\mov %%cr0, %%eax
        \\or $0x80000000, %%eax
        \\mov %%eax, %%cr0
        \\jmp 1f
        \\1:
        : [dummy] "={eax}" (dummy),
        : [pd] "r" (pd_addr),
        : "memory");
}

pub fn init_sse() void {
    var dummy: u32 = undefined;
    var d_ebx: u32 = undefined;
    var d_ecx: u32 = undefined;
    var d_edx: u32 = undefined;
    asm volatile (
        \\mov %%cr0, %%eax
        \\and $0xFFFB, %%ax
        \\or  $0x2, %%ax
        \\mov %%eax, %%cr0
        \\mov %%cr4, %%eax
        \\or  $0x600, %%eax
        \\mov %%eax, %%cr4
        \\mov $1, %%eax
        \\cpuid
        \\bt $26, %%ecx
        \\jnc 1f
        \\mov %%cr4, %%eax
        \\or $0x40000, %%eax
        \\mov %%eax, %%cr4
        \\bt $28, %%ecx
        \\jnc 1f
        \\xor %%ecx, %%ecx
        \\xgetbv
        \\or $7, %%eax
        \\xsetbv
        \\1:
        : [dummy] "={eax}" (dummy),
          [ebx] "={ebx}" (d_ebx),
          [ecx] "={ecx}" (d_ecx),
          [edx] "={edx}" (d_edx),
        :
        : "memory");
}

// Using scheduler.detected_cores instead
pub const cores = &scheduler.cpcbs;
const trampoline_bin = @embedFile("trampoline.bin");
var ap_stacks: [16][16384]u8 align(4096) = undefined;

pub fn get_lapic_id() u8 {
    var lapic = @as([*]volatile u32, @ptrFromInt(acpi.lapic_addr));
    return @as(u8, @intCast(lapic[0x20 / 4] >> 24));
}

pub const CpuInfo = struct {
    vendor: [13]u8,
    brand: [48]u8,
    family: u32,
    model: u32,
    stepping: u32,
};

/// Initialize LAPIC Timer for the current core
pub fn init_local_timer(quantum: u32) void {
    var lapic = @as([*]volatile u32, @ptrFromInt(acpi.lapic_addr));

    // 1. Set divisor to 16
    lapic[LAPIC_TDCR / 4] = 0x03;

    // 2. Set LVT Timer (Interrupt Vector 0x30, Periodic mode)
    // Mode: Bits 17:18 (01 = Periodic)
    // Vector: 0x30 (48)
    lapic[LAPIC_TIMER / 4] = 0x00020030;

    // 3. Set initial count
    lapic[LAPIC_TICR / 4] = quantum;

    // 4. Enable APIC globally (Spurious Interrupt Vector register)
    // Vector 0xFF, Bit 8 = 1 (Enable)
    lapic[0xF0 / 4] = 0x1FF;
}

/// The main entry point for AP cores
pub export fn ap_kernel_entry() noreturn {
    const core_id = @as(*volatile u32, @ptrFromInt(MAILBOX_ID)).*;
    const cpu = &scheduler.cpcbs[core_id];

    // 1. Hardware Initialization for this core
    gdt_load();
    idt_load();
    enable_paging_ap();
    init_sse();

    // 2. Configure LAPIC timer for this core
    const quantum: u32 = if (cpu.is_guardian) 1000000 else 10000000;
    init_local_timer(quantum);

    // 3. Signal BSP that we are READY
    @as(*volatile u32, @ptrFromInt(FLAG_ADDR)).* = 1;

    // 4. Enable interrupts and idle
    asm volatile ("sti");

    while (true) {
        asm volatile ("hlt");
    }
}

pub fn get_online_cores() u32 {
    return scheduler.detected_cores;
}

pub fn push_task(func: *const fn (usize) callconv(.c) void, arg: usize) bool {
    // Legacy support: push as a normal priority task (16)
    _ = spawn("Task", 16, @intFromPtr(func), arg);
    return true;
}

pub fn get_cpu_info() CpuInfo {
    var info: CpuInfo = undefined;
    var eax: u32 = 0;
    var ebx: u32 = 0;
    var ecx: u32 = 0;
    var edx: u32 = 0;

    // 1. Vendor string (Standard EAX=0)
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [eax_in] "{eax}" (@as(u32, 0)),
    );
    @memcpy(info.vendor[0..4], @as(*[4]u8, @ptrCast(&ebx)));
    @memcpy(info.vendor[4..8], @as(*[4]u8, @ptrCast(&edx)));
    @memcpy(info.vendor[8..12], @as(*[4]u8, @ptrCast(&ecx)));
    info.vendor[12] = 0;

    // 2. Family, Model, Stepping (Standard EAX=1)
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [eax_in] "{eax}" (@as(u32, 1)),
    );
    info.stepping = eax & 0xF;
    info.model = (eax >> 4) & 0xF;
    info.family = (eax >> 8) & 0xF;

    // 3. Brand string (Extended EAX=0x80000000 check)
    var dummy_ebx: u32 = undefined;
    var dummy_ecx: u32 = undefined;
    var dummy_edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (dummy_ebx),
          [ecx] "={ecx}" (dummy_ecx),
          [edx] "={edx}" (dummy_edx),
        : [eax_in] "{eax}" (@as(u32, 0x80000000)),
    );

    if (eax >= 0x80000004) {
        var i: u32 = 0;
        while (i < 3) : (i += 1) {
            var beax: u32 = undefined;
            var bebx: u32 = undefined;
            var becx: u32 = undefined;
            var bedx: u32 = undefined;
            asm volatile ("cpuid"
                : [eax] "={eax}" (beax),
                  [ebx] "={ebx}" (bebx),
                  [ecx] "={ecx}" (becx),
                  [edx] "={edx}" (bedx),
                : [eax_in] "{eax}" (@as(u32, 0x80000002 + i)),
            );
            @memcpy(info.brand[i * 16 + 0 .. i * 16 + 4], @as(*[4]u8, @ptrCast(&beax)));
            @memcpy(info.brand[i * 16 + 4 .. i * 16 + 8], @as(*[4]u8, @ptrCast(&bebx)));
            @memcpy(info.brand[i * 16 + 8 .. i * 16 + 12], @as(*[4]u8, @ptrCast(&becx)));
            @memcpy(info.brand[i * 16 + 12 .. i * 16 + 16], @as(*[4]u8, @ptrCast(&bedx)));
        }
    } else {
        const unknown = "Unknown CPU Model";
        @memcpy(info.brand[0..unknown.len], unknown);
        @memset(info.brand[unknown.len..48], ' ');
    }

    return info;
}

pub fn run_task(core_id: u32, task: *scheduler.Task) void {
    const cpu = &scheduler.cpcbs[core_id];
    const prev_task = cpu.current_task;

    cpu.current_task = task;
    cpu.total_tasks += 1;
    task.status = .Running;

    if (prev_task) |prev| {
        switch_context(&prev.context_ptr, task.context_ptr);
    } else {
        // First task on this core
        start_task_asm(task.context_ptr);
    }
}

pub fn spawn(name: []const u8, priority: u8, entry: usize, arg: usize) u32 {
    const pid = scheduler.init_task(name, priority, entry, arg) orelse 0;
    return pid;
}

pub fn init() void {
    common.printZ("SMP: Initializing Guardian Real-Time Scheduler...\n");

    const tramp_ptr = @as([*]u8, @ptrFromInt(TRAMPOLINE_ADDR));
    @memcpy(tramp_ptr[0..trampoline_bin.len], trampoline_bin);

    @as(*volatile u32, @ptrFromInt(FLAG_ADDR)).* = 0;
    @as(*volatile u32, @ptrFromInt(MAILBOX_ENTRY)).* = @intFromPtr(&ap_kernel_entry);

    if (acpi.lapic_addr == 0) {
        acpi.lapic_addr = 0xFEE00000;
        scheduler.detected_cores = 1;
    } else {
        scheduler.detected_cores = acpi.madt_core_count;
    }

    _ = memory.map_page(acpi.lapic_addr);

    // Initial setup for BSP (Core 0)
    const bsp_id = get_lapic_id();
    scheduler.cpcbs[0] = .{ .id = 0, .lapic_id = bsp_id, .is_guardian = false };
    init_local_timer(10000000); // 100ms quantum for BSP

    var ap_count: u32 = 0;
    for (acpi.lapic_ids[0..scheduler.detected_cores]) |id| {
        if (id == bsp_id) continue;
        if (ap_count + 1 >= scheduler.MAX_CORES) break;

        const stack_top = @intFromPtr(&ap_stacks[ap_count]) + 16384;
        @as(*volatile u32, @ptrFromInt(MAILBOX_STACK)).* = stack_top;
        @as(*volatile u32, @ptrFromInt(MAILBOX_ID)).* = ap_count + 1;

        scheduler.cpcbs[ap_count + 1] = .{
            .id = ap_count + 1,
            .lapic_id = id,
            .is_guardian = (id == acpi.lapic_ids[acpi.madt_core_count - 1]), // Last core is Guardian
        };

        const flag_ptr = @as(*volatile u32, @ptrFromInt(FLAG_ADDR));
        flag_ptr.* = 0; // Reset flag for this core

        const lapic = @as([*]volatile u32, @ptrFromInt(acpi.lapic_addr));
        lapic[0x310 / 4] = @as(u32, id) << 24;
        lapic[0x300 / 4] = 0x00004608; // SIPI

        // Wait for core to signal ready
        var timeout: u32 = 0;
        while (flag_ptr.* == 0 and timeout < 1000000) : (timeout += 1) {
            asm volatile ("pause");
        }

        ap_count += 1;
    }

    common.printZ("SMP: ");
    common.printNum(@intCast(ap_count + 1));
    common.printZ(" cores active. Guardian Core assigned.\n");
}

pub export fn isr_scheduler_entry(ctx_ptr: *usize) void {
    var lapic = @as([*]volatile u32, @ptrFromInt(acpi.lapic_addr));
    const lapic_id = get_lapic_id();

    // Find our core_id
    var core_id: u32 = 0xFFFFFFFF;
    var i: u32 = 0;
    while (i < scheduler.detected_cores) : (i += 1) {
        if (scheduler.cpcbs[i].lapic_id == lapic_id) {
            core_id = i;
            break;
        }
    }

    if (core_id == 0xFFFFFFFF) return; // Should not happen

    // Send EOI to LAPIC IMMEDIATELY before switching
    // This acknowledges the interrupt so the core can receive the next one
    lapic[0xB0 / 4] = 0;

    scheduler.scheduler_yield(core_id, ctx_ptr);
}
