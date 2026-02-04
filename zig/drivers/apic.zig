// APIC (Advanced Programmable Interrupt Controller) Driver
const acpi = @import("acpi.zig");
const common = @import("../commands/common.zig");

pub const LAPIC_ID = 0x20;
pub const LAPIC_VER = 0x30;
pub const LAPIC_TPR = 0x80;
pub const LAPIC_EOI = 0xB0;
pub const LAPIC_SVR = 0xF0;
pub const LAPIC_ESR = 0x280;
pub const LAPIC_ICRLO = 0x300;
pub const LAPIC_ICRHI = 0x310;
pub const LAPIC_LVT_TMR = 0x320;
pub const LAPIC_LVT_PERF = 0x340;
pub const LAPIC_LVT_LINT0 = 0x350;
pub const LAPIC_LVT_LINT1 = 0x360;
pub const LAPIC_LVT_ERR = 0x370;
pub const LAPIC_TMRINIT = 0x380;
pub const LAPIC_TMRCUR = 0x390;
pub const LAPIC_TMRDIV = 0x3E0;

pub fn lapic_read(reg: u32) u32 {
    return @as(*volatile u32, @ptrFromInt(acpi.lapic_addr + reg)).*;
}

pub fn lapic_write(reg: u32, value: u32) void {
    @as(*volatile u32, @ptrFromInt(acpi.lapic_addr + reg)).* = value;
}

pub fn get_cpu_id() u8 {
    return @intCast(lapic_read(LAPIC_ID) >> 24);
}

pub export fn lapic_eoi() void {
    lapic_write(LAPIC_EOI, 0);
}

extern const trampoline_start: anyopaque;
extern const trampoline_end: anyopaque;
extern var ap_stack_ptr: u32;
extern var ap_main_ptr: u32;

pub var ap_boot_handshake: u32 = 0;

pub fn boot_aps(ap_main: *const fn() callconv(.c) void) void {
    const trampoline_addr: usize = 0x8000;
    const start_ptr = @intFromPtr(&trampoline_start);
    const end_ptr = @intFromPtr(&trampoline_end);
    const len = end_ptr - start_ptr;

    // 1. Copy trampoline to 0x8000
    const dest = @as([*]u8, @ptrFromInt(trampoline_addr));
    const src = @as([*]const u8, @ptrFromInt(start_ptr));
    for (0..len) |i| dest[i] = src[i];

    // Get absolute addresses of parameters in the trampoline at 0x8000
    const ap_stack_ptr_addr = trampoline_addr + (@intFromPtr(&ap_stack_ptr) - start_ptr);
    const ap_main_ptr_addr = trampoline_addr + (@intFromPtr(&ap_main_ptr) - start_ptr);

    // 2. Iterate through CPUs (except Master)
    var i: u32 = 1;
    while (i < acpi.cpu_count) : (i += 1) {
        const cpu_id = acpi.cpu_ids[i];

        // Allocate stack for this CPU
        const stack_size = 16 * 1024;
        const stack = @import("../memory.zig").heap.alloc(stack_size) orelse continue;
        const stack_top = @intFromPtr(stack) + stack_size;

        @as(*volatile u32, @ptrFromInt(ap_stack_ptr_addr)).* = @intCast(stack_top);
        @as(*volatile u32, @ptrFromInt(ap_main_ptr_addr)).* = @intFromPtr(ap_main);

        @atomicStore(u32, &ap_boot_handshake, 0, .seq_cst);

        // Send INIT IPI
        lapic_write(LAPIC_ICRHI, @as(u32, cpu_id) << 24);
        lapic_write(LAPIC_ICRLO, 0x0000C500); // INIT, Level=1, Assert
        common.sleep(10);

        // Send SIPI
        lapic_write(LAPIC_ICRHI, @as(u32, cpu_id) << 24);
        lapic_write(LAPIC_ICRLO, 0x00000600 | (trampoline_addr >> 12)); // SIPI

        // Wait for AP to signal it has booted and read its parameters
        var timeout: u32 = 1000;
        while (@atomicLoad(u32, &ap_boot_handshake, .seq_cst) == 0 and timeout > 0) {
            asm volatile ("pause");
            common.sleep(1);
            timeout -= 1;
        }
    }
}

pub fn init_lapic() void {
    // 1. Set Spurious Interrupt Vector (and enable LAPIC)
    // Vector 0xFF, Enable bit 8
    lapic_write(LAPIC_SVR, lapic_read(LAPIC_SVR) | 0x1FF);

    // 2. Mask LVT entries to prevent unwanted interrupts on APs
    lapic_write(LAPIC_LVT_TMR, 0x10000);   // Masked
    lapic_write(LAPIC_LVT_PERF, 0x10000);  // Masked
    lapic_write(LAPIC_LVT_LINT0, 0x10000); // Masked
    lapic_write(LAPIC_LVT_LINT1, 0x10000); // Masked
    lapic_write(LAPIC_LVT_ERR, 0x10000);   // Masked
}

// I/O APIC
pub fn ioapic_read(reg: u32) u32 {
    @as(*volatile u32, @ptrFromInt(acpi.ioapic_addr)).* = reg;
    return @as(*volatile u32, @ptrFromInt(acpi.ioapic_addr + 0x10)).*;
}

pub fn ioapic_write(reg: u32, value: u32) void {
    @as(*volatile u32, @ptrFromInt(acpi.ioapic_addr)).* = reg;
    @as(*volatile u32, @ptrFromInt(acpi.ioapic_addr + 0x10)).* = value;
}

pub fn set_irq_redirect(irq: u8, vector: u8, cpu_id: u8) void {
    const low_index = 0x10 + @as(u32, irq) * 2;
    const high_index = low_index + 1;

    // High 32 bits: Destination Field (APIC ID)
    ioapic_write(high_index, @as(u32, cpu_id) << 24);

    // Low 32 bits: Vector, Delivery Mode (Fixed=000), Destination Mode (Physical=0),
    // Interrupt Polarity (Active High=0), Trigger Mode (Edge=0), Mask (Unmasked=0)
    ioapic_write(low_index, vector);
}

pub fn disable_pic() void {
    common.outb(0x21, 0xFF);
    common.outb(0xA1, 0xFF);
}

pub fn init() void {
    disable_pic();
    init_lapic();

    // Route Keyboard (IRQ 1) to Master (Core 0) as requested
    // IRQ 1 -> Vector 0x21
    set_irq_redirect(1, 0x21, acpi.cpu_ids[0]);

    // Route Timer (IRQ 0) to Master (Core 0)
    // IRQ 0 -> Vector 0x20
    set_irq_redirect(0, 0x20, acpi.cpu_ids[0]);
}
