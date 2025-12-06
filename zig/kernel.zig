// Import our shell commands module and re-export manually for ASM
const shell_cmds = @import("shell_cmds.zig");
const nova = @import("nova.zig");

// Re-exports
pub const zig_init = shell_cmds.zig_init;
pub const zig_set_cursor = shell_cmds.zig_set_cursor;
pub const cmd_ls = shell_cmds.cmd_ls;
pub const cmd_cat = shell_cmds.cmd_cat;
pub const cmd_touch = shell_cmds.cmd_touch;
pub const cmd_rm = shell_cmds.cmd_rm;
pub const cmd_echo = shell_cmds.cmd_echo;
pub const cmd_write = shell_cmds.cmd_write;
pub const cmd_panic = shell_cmds.cmd_panic;

// External Assembly Functions
extern fn read_command() void;
extern fn execute_command() void;
extern fn wait_key() u8;
extern fn clear_screen() void;

// VGA Constants
const VGA_MEMORY = 0xb8000;
const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;
const RED_ON_WHITE = 0x4F; // Background Red(4), Foreground White(F)

// Inline Assembly helper for IO ports
fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

// Panic Implementation
pub fn panic(msg: []const u8) noreturn {
    // Disable interrupts (cli)
    asm volatile ("cli");

    const vga_ptr = @as([*]volatile u16, @ptrFromInt(VGA_MEMORY));

    // 1. Fill screen with Red background
    var i: usize = 0;
    while (i < VGA_WIDTH * VGA_HEIGHT) : (i += 1) {
        vga_ptr[i] = (RED_ON_WHITE << 8) | ' ';
    }

    // 2. Print "KERNEL PANIC! SYSTEM HALTED" centered
    const title = "KERNEL PANIC! SYSTEM HALTED";
    print_centered_at(vga_ptr, title, 10);

    // 3. Print the error message centered
    print_centered_at(vga_ptr, msg, 12);

    // 4. Print reboot instruction
    const reboot_msg = "Press ENTER to reboot";
    print_centered_at(vga_ptr, reboot_msg, 15);

    while (true) {
        const key = wait_key();
        if (key == 10 or key == 13) {
            // Trigger reboot via keyboard controller
            outb(0x64, 0xFE);
        }
    }
}

const interpreter = @import("nova/interpreter.zig");
export fn nova_start() void {
    interpreter.start();
}

fn print_centered_at(vga: [*]volatile u16, text: []const u8, row: usize) void {
    const start_col = if (text.len < VGA_WIDTH) (VGA_WIDTH - text.len) / 2 else 0;
    const offset = row * VGA_WIDTH + start_col;
    
    for (text, 0..) |char, idx| {
        if (start_col + idx < VGA_WIDTH) {
            vga[offset + idx] = (RED_ON_WHITE << 8) | @as(u16, char);
        }
    }
}

// Export panic for valid ASM/Zig usage
export fn kernel_panic(msg_ptr: [*]const u8, msg_len: usize) noreturn {
    const msg = msg_ptr[0..msg_len];
    panic(msg);
}

// Main Kernel Entry Point
export fn kmain() void {
    // Initialize Zig/FS
    shell_cmds.zig_init();
    
    const common = @import("commands/common.zig");

    // Use shell.asm logic via extern calls
    while (true) {
        common.printZ("> ");
        read_command();
        execute_command();
    }
}
