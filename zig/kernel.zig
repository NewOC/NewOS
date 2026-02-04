// NewOS Kernel - Main Zig Module
// Entry point for the Zig portion of the kernel and panic handler.

const shell_cmds = @import("shell_cmds.zig");
const keyboard_isr = @import("keyboard_isr.zig");
const nova = @import("nova.zig");
const common = @import("commands/common.zig");
const shell = @import("shell.zig");
const messages = @import("messages.zig");
const timer = @import("drivers/timer.zig");
const acpi = @import("drivers/acpi.zig");
const apic = @import("drivers/apic.zig");
const memory = @import("memory.zig");
const sync = @import("sync.zig");
const scheduler = @import("scheduler.zig");


// Ensure all modules are included in the compilation
comptime {
    _ = shell_cmds;
    _ = keyboard_isr;
    _ = nova;
    _ = shell;
    _ = messages;
    _ = timer;
    _ = acpi;
    _ = memory;
    _ = @import("drivers/vga.zig");
}

// External shell functions (exported by shell.zig)
extern fn read_command() void;
extern fn execute_command() void;

/// Kernel Panic Handler (exported for ASM use)
export fn kernel_panic(msg_ptr: [*]const u8, msg_len: usize) noreturn {
    panic(msg_ptr[0..msg_len]);
}

/// Main Panic Handler - Stops execution and displays an error message
pub fn panic(msg: []const u8) noreturn {
    asm volatile ("cli"); // Disable interrupts
    
    // Direct VGA memory access to display Red Screen of Death
    const vga = @as([*]volatile u16, @ptrFromInt(0xb8000));
    
    // Fill entire screen with red background
    for (0..2000) |i| {
        vga[i] = (0x4f << 8) | ' '; // Red background, white text
    }
    
    // Title centered on line 10
    const title = "*** KERNEL PANIC ***";
    const title_row: usize = 10;
    const title_col: usize = (80 - title.len) / 2;
    for (title, 0..) |char, i| {
        vga[title_row * 80 + title_col + i] = (0x4f << 8) | @as(u16, char);
    }
    
    // Error message centered on line 12
    const msg_row: usize = 12;
    const msg_len = @min(msg.len, 78); // Max 78 chars to fit on screen
    const msg_col: usize = (80 - msg_len) / 2;
    for (msg[0..msg_len], 0..) |char, i| {
        vga[msg_row * 80 + msg_col + i] = (0x4f << 8) | @as(u16, char);
    }
    
    // Footer message on line 14
    const footer = "Press ENTER to reboot system.";
    const footer_row: usize = 14;
    const footer_col: usize = (80 - footer.len) / 2;
    for (footer, 0..) |char, i| {
        vga[footer_row * 80 + footer_col + i] = (0x4f << 8) | @as(u16, char);
    }
    
    // Poll for Enter key to reboot
    while (true) {
        // Check Status Register (Port 0x64) bit 0 (Output Buffer Full)
        const status = inb(0x64);
        if ((status & 0x01) != 0) {
            // Read Scancode from Data Register (Port 0x60)
            const scancode = inb(0x60);
            if (scancode == 0x1C) { // Enter Key Pressed
                common.reboot();
            }
        }
    }
}

/// Read a byte from an I/O port
fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

extern const kernel_idt_descriptor: anyopaque;

/// AP Entry Point (Application Processors)
export fn ap_main() callconv(.c) void {
    // Load IDT for this core
    asm volatile ("lidt (%[ptr])" : : [ptr] "r" (&kernel_idt_descriptor));

    apic.init_lapic();

    // Signal to Master that we have booted and read trampoline parameters
    @atomicStore(u32, &apic.ap_boot_handshake, 1, .seq_cst);

    // Each AP enters the polling loop
    ap_polling_loop();
}

fn ap_polling_loop() noreturn {
    while (true) {
        if (scheduler.dequeue()) |task| {
            @atomicStore(scheduler.TaskStatus, &task.status, .Running, .seq_cst);
            task.func(task.arg);
            @atomicStore(scheduler.TaskStatus, &task.status, .Done, .seq_cst);
        } else {
            asm volatile ("pause");
        }
    }
}

// --- Kernel Entry Point ---
export fn kmain() void {
    // 1. Initialize PMM & Heap
    memory.pmm.init();
    memory.heap.init();
    
    // 2. Initialize timer and interrupt controllers
    // Initialize file system
    shell_cmds.zig_init();
    
    // Initialize system timer
    timer.init();
    
    // Initialize ACPI (for proper shutdown)
    if (acpi.init()) {
        // Initialize APIC and Boot APs
        apic.init();
        apic.boot_aps(ap_main);
    }

    // Enable interrupts on Master Core
    asm volatile ("sti");

    // Main Shell loop
    while (true) {
        read_command();
        execute_command();
    }
}