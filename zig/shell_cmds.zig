// NewOS Shell Commands - Written in Zig
// Uses ASM print functions for correct cursor handling

const fs = @import("fs");

// External ASM functions (cdecl wrappers)
extern fn zig_print_string(str: [*]const u8) void;
extern fn zig_print_char(c: u8) void;

// Aliases for convenience
const print_char = zig_print_char;
const print_string = zig_print_string;

// Helper to print a null-terminated string
fn printZ(str: []const u8) void {
    for (str) |c| {
        if (c == 0) break;
        print_char(c);
    }
}

// Print a number
fn printNum(n: i32) void {
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

// ============================================
// Shell Commands
// ============================================

// List all files
export fn cmd_ls() void {
    var ids: [16]u8 = undefined;
    const count = fs.fs_list(&ids);
    
    if (count == 0) {
        printZ("No files\n");
        return;
    }
    
    var name_buf: [12]u8 = undefined;
    var i: u8 = 0;
    while (i < count) : (i += 1) {
        const id = ids[i];
        _ = fs.fs_getname(id, &name_buf);
        
        // Print filename
        for (name_buf) |c| {
            if (c == 0) break;
            print_char(c);
        }
        
        const size = fs.fs_size(id);
        printZ("  ");
        printNum(size);
        printZ(" bytes\n");
    }
}

// Print file contents
export fn cmd_cat(name_ptr: [*]const u8, name_len: u8) void {
    const id = fs.fs_find(name_ptr, name_len);
    if (id < 0) {
        printZ("File not found\n");
        return;
    }
    
    var buffer: [1024]u8 = undefined;
    const size = fs.fs_read(@intCast(id), &buffer, 1024);
    if (size > 0) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(size))) : (i += 1) {
            print_char(buffer[i]);
        }
        print_char('\n');
    }
}

// Create empty file
export fn cmd_touch(name_ptr: [*]const u8, name_len: u8) void {
    // Check if already exists
    const existing = fs.fs_find(name_ptr, name_len);
    if (existing >= 0) {
        printZ("File already exists\n");
        return;
    }
    
    const id = fs.fs_create(name_ptr, name_len);
    if (id < 0) {
        printZ("Cannot create file\n");
        return;
    }
    printZ("Created: ");
    var i: u8 = 0;
    while (i < name_len) : (i += 1) {
        print_char(name_ptr[i]);
    }
    print_char('\n');
}

// Delete file
export fn cmd_rm(name_ptr: [*]const u8, name_len: u8) void {
    const id = fs.fs_find(name_ptr, name_len);
    if (id < 0) {
        printZ("File not found\n");
        return;
    }
    
    _ = fs.fs_delete(@intCast(id));
    printZ("Deleted: ");
    var i: u8 = 0;
    while (i < name_len) : (i += 1) {
        print_char(name_ptr[i]);
    }
    print_char('\n');
}

// Write content to file
export fn cmd_write(name_ptr: [*]const u8, name_len: u8, data_ptr: [*]const u8, data_len: u16) void {
    var id = fs.fs_find(name_ptr, name_len);
    
    // Create if doesn't exist
    if (id < 0) {
        id = fs.fs_create(name_ptr, name_len);
        if (id < 0) {
            printZ("Cannot create file\n");
            return;
        }
    }
    
    const written = fs.fs_write(@intCast(id), data_ptr, data_len);
    if (written < 0) {
        printZ("Write error\n");
        return;
    }
    
    printZ("Wrote ");
    printNum(written);
    printZ(" bytes\n");
}

// Echo command: print text
export fn cmd_echo(text_ptr: [*]const u8, text_len: u16) void {
    var i: u16 = 0;
    while (i < text_len) : (i += 1) {
        print_char(text_ptr[i]);
    }
    print_char('\n');
}

// Initialize (called once at boot)
export fn zig_init() void {
    fs.fs_init();
}

// Dummy for backward compatibility
export fn zig_set_cursor(x: u8, y: u8) void {
    _ = x;
    _ = y;
}
