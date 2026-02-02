// Common Utilities Module
// Provides shared logic for printing, system control, and file system access.

const fs = @import("../fs.zig");
const vga = @import("../drivers/vga.zig");
const timer = @import("../drivers/timer.zig");


// --- VGA Interface ---
/// Low-level character output
pub const print_char = vga.zig_print_char;

/// Print a string slice to the console
pub fn printZ(str: []const u8) void {
    for (str) |c| {
        if (c == 0) break;
        print_char(c);
    }
}

/// Print a signed 32-bit integer to the console
pub fn printNum(n: i32) void {
    if (n < 0) {
        print_char('-');
        printNum(-n);
        return;
    }
    if (n >= 10) {
        printNum(@divTrunc(n, 10));
    }
    print_char(@intCast(@as(u8, @intCast(@mod(n, 10))) + '0'));
}

// --- File System Interface ---
// Re-export core fs functions for easy access by shell commands
pub const fs_init    = fs.fs_init;
pub const fs_create  = fs.fs_create;
pub const fs_delete  = fs.fs_delete;
pub const fs_find    = fs.fs_find;
pub const fs_list    = fs.fs_list;
pub const fs_getname = fs.fs_getname;
pub const fs_size    = fs.fs_size;
pub const fs_read    = fs.fs_read;
pub const fs_write   = fs.fs_write;

// --- System Control (I/O Ports) ---

/// Send a byte to an I/O port
fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

/// Send a word (16-bit) to an I/O port
fn outw(port: u16, value: u16) void {
    asm volatile ("outw %[value], %[port]"
        :
        : [value] "{ax}" (value),
          [port] "{dx}" (port),
    );
}

/// Reset the computer via the keyboard controller pulse
pub fn reboot() noreturn {
    printZ("Rebooting...\r\n");
    // Pulse CPU reset line (FE code to command port 64h)
    outb(0x64, 0xFE);
    while(true) {}
}

/// Shutdown the virtual machine (works in QEMU and Bochs)
pub fn shutdown() noreturn {
    printZ("Shutting down...\r\n");
    // ACPI shutdown for QEMU
    outw(0x604, 0x2000);
    // Shutdown for Bochs/Older QEMU
    outw(0xB004, 0x2000);
    
    printZ("Shutdown failed! (System halted.)\r\n");
    while(true) asm volatile("hlt");
}

/// Precise sleep in milliseconds
pub fn sleep(ms: usize) void {
    timer.sleep(ms);
}


/// Check if two memory slices are equal
pub fn std_mem_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |item, i| {
        if (item != b[i]) return false;
    }
    return true;
}

/// Check if string starts with prefix
pub fn startsWith(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    return std_mem_eql(a[0..b.len], b);
}
