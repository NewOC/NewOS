// Common utilities for all commands

const fs = @import("../fs.zig");

// External ASM functions (cdecl wrappers)
extern fn zig_print_char(c: u8) void;

pub const print_char = zig_print_char;

// Print a slice
pub fn printZ(str: []const u8) void {
    for (str) |c| {
        if (c == 0) break;
        print_char(c);
    }
}

// Print a number
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

// Re-export fs functions
pub const fs_init = fs.fs_init;
pub const fs_create = fs.fs_create;
pub const fs_delete = fs.fs_delete;
pub const fs_find = fs.fs_find;
pub const fs_list = fs.fs_list;
pub const fs_getname = fs.fs_getname;
pub const fs_size = fs.fs_size;
pub const fs_read = fs.fs_read;
pub const fs_write = fs.fs_write;
