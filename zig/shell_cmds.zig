// NewOS Shell Commands - Main module
// Imports individual command modules and exports to ASM

const ls = @import("commands/ls.zig");
const cat = @import("commands/cat.zig");
const touch = @import("commands/touch.zig");
const rm = @import("commands/rm.zig");
const echo = @import("commands/echo.zig");
const common = @import("commands/common.zig");

// Export commands for ASM
export fn cmd_ls() void {
    ls.execute();
}

export fn cmd_cat(name_ptr: [*]const u8, name_len: u8) void {
    cat.execute(name_ptr, name_len);
}

export fn cmd_touch(name_ptr: [*]const u8, name_len: u8) void {
    touch.execute(name_ptr, name_len);
}

export fn cmd_rm(name_ptr: [*]const u8, name_len: u8) void {
    rm.execute(name_ptr, name_len);
}

export fn cmd_echo(text_ptr: [*]const u8, text_len: u16) void {
    echo.execute(text_ptr, text_len);
}

// Initialize (called once at boot)
export fn zig_init() void {
    common.fs_init();
}

// Backward compatibility
export fn zig_set_cursor(x: u8, y: u8) void {
    _ = x;
    _ = y;
}

// Re-export for other uses
export fn cmd_write(name_ptr: [*]const u8, name_len: u8, data_ptr: [*]const u8, data_len: u16) void {
    var id = common.fs_find(name_ptr, name_len);
    if (id < 0) {
        id = common.fs_create(name_ptr, name_len);
        if (id < 0) {
            common.printZ("Cannot create file\n");
            return;
        }
    }
    const written = common.fs_write(@intCast(id), data_ptr, data_len);
    if (written < 0) {
        common.printZ("Write error\n");
        return;
    }
    common.printZ("Wrote ");
    common.printNum(written);
    common.printZ(" bytes\n");
}
