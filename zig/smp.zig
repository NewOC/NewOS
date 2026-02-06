const acpi = @import("drivers/acpi.zig");
const memory = @import("memory.zig");
const common = @import("commands/common.zig");

// Trampoline for APs
// 16-bit real mode code that sets a flag and halts.
// Assumed to be loaded at 0x8000 (Vector 0x08)
//
// 1. cli              ; Disable interrupts
// 2. xor ax, ax       ; Zero segments
// 3. mov ds, ax
// 4. mov byte [0x9000], 1 ; Set flag to 1
// 5. hlt              ; Halt
// 6. jmp -2           ; Loop
const TRAMPOLINE_ADDR = 0x8000;
const FLAG_ADDR = 0x9000;

const trampoline_code = [_]u8{
    0xFA, // cli
    0x31, 0xC0, // xor ax, ax
    0x8E, 0xD8, // mov ds, ax
    0xF0, 0xFE, 0x06, 0x00, 0x90, // lock inc byte [0x9000]
    0xF4, // hlt
    0xEB,
    0xFD, // jmp -3 (infinite loop to hlt)
};

pub var detected_cores: u32 = 1;

pub const CpuInfo = struct {
    vendor: [13]u8,
    brand: [49]u8 align(4),
    family: u32,
    model: u32,
    stepping: u32,
};

pub fn get_online_cores() u8 {
    const flag_ptr = @as(*volatile u8, @ptrFromInt(FLAG_ADDR));
    return flag_ptr.* + 1; // +1 for the BSP (this core)
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
    common.printZ("SMP: Initializing Dumb SMP...\n");

    // 1. Prepare Trampoline Code
    const tramp_ptr = @as([*]u8, @ptrFromInt(TRAMPOLINE_ADDR));
    // 0x8000 is safely within the first 16MB of identity mapped memory.
    @memcpy(tramp_ptr[0..trampoline_code.len], &trampoline_code);

    // 2. Reset the Flag
    const flag_ptr = @as(*volatile u8, @ptrFromInt(FLAG_ADDR));
    flag_ptr.* = 0;

    // 3. Get LAPIC Address
    var lapic_base = acpi.lapic_addr;
    if (lapic_base == 0) {
        lapic_base = 0xFEE00000; // Default
        common.printZ("SMP: MADT not found, using default LAPIC base 0xFEE00000\n");
        detected_cores = 1;
    } else {
        detected_cores = acpi.madt_core_count;
    }

    // 4. Map LAPIC
    // We assume 4KB page alignment for LAPIC base (usually 0xFEE00000)
    // map_page is required because LAPIC address is usually above 16MB
    if (!memory.map_page(lapic_base)) {
        common.printZ("SMP: Failed to map LAPIC memory! Aborting.\n");
        return;
    }

    // 5. Send IPIs
    const lapic = @as([*]volatile u32, @ptrFromInt(lapic_base));
    const ICR_LOW = 0x300 / 4;
    const ICR_HIGH = 0x310 / 4;

    common.printZ("SMP: Sending INIT IPI to all other cores...\n");

    // Send INIT (Level Assert, All Excluding Self)
    // Bits 18-19: 11 (All Excluding Self) => 0xC0000
    // Bits 8-10: 101 (INIT) => 0x500
    // Bit 14: 1 (Assert) => 0x4000
    // Total: 0xC4500.
    lapic[ICR_HIGH] = 0;
    lapic[ICR_LOW] = 0x000C4500;

    // Wait 10ms
    common.sleep(10);

    common.printZ("SMP: Sending SIPI (Vector 0x08)...\n");

    // Send SIPI (Vector 0x08 => 0x8000 start address)
    // Mode: 110 (Start-up) -> 0x600
    // Level: 1 (Assert) -> 0x4000
    // Shorthand: 11 -> 0xC0000
    // Total: 0xC4608
    lapic[ICR_HIGH] = 0;
    lapic[ICR_LOW] = 0x000C4608;

    // Wait for the AP to wake up and run the code
    common.sleep(50); // Give it some time

    // 6. Check Flag
    const online = get_online_cores();
    if (online > 1) {
        common.printZ("SMP: SUCCESS! ");
        common.printNum(@intCast(online - 1));
        common.printZ(" AP core(s) woke up!\n");
    } else {
        common.printZ("SMP: FAILURE. Flag is still 0.\n");

        // Try resending SIPI (standard practice)
        common.printZ("SMP: Sending second SIPI...\n");
        lapic[ICR_LOW] = 0x000C4608;
        common.sleep(50);

        if (flag_ptr.* == 1) {
            common.printZ("SMP: SUCCESS after second SIPI!\n");
        } else {
            common.printZ("SMP: FAILURE after second SIPI.\n");
        }
    }
}
