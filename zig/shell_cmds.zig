// Shell Commands Module
// Bridges high-level command logic with individual command implementations.

const ls = @import("commands/ls.zig");
const cat = @import("commands/cat.zig");
const touch = @import("commands/touch.zig");
const rm = @import("commands/rm.zig");
const echo = @import("commands/echo.zig");
const common = @import("commands/common.zig");
const timer = @import("drivers/timer.zig");
const disk_cmds = @import("commands/disk_cmds.zig");


/// Execute 'ls' command
pub export fn cmd_ls() void {
    ls.execute();
}

/// Execute 'cat' command for a given filename
pub export fn cmd_cat(name_ptr: [*]const u8, name_len: u32) void {
    cat.execute(name_ptr, @intCast(name_len));
}

/// Execute 'touch' command to create a file
pub export fn cmd_touch(name_ptr: [*]const u8, name_len: u32) void {
    touch.execute(name_ptr, @intCast(name_len));
}

/// Execute 'rm' command to delete a file
pub export fn cmd_rm(name_ptr: [*]const u8, name_len: u32) void {
    rm.execute(name_ptr, @intCast(name_len));
}

/// Execute 'echo' command to print text
pub export fn cmd_echo(text_ptr: [*]const u8, text_len: u32) void {
    echo.execute(text_ptr, @intCast(text_len));
}

/// Execute system 'reboot'
pub export fn cmd_reboot() void {
    common.reboot();
}

/// Execute system 'shutdown'
pub export fn cmd_shutdown() void {
    common.shutdown();
}

/// Execute 'uptime' command
pub export fn cmd_uptime() void {
    const s = timer.get_uptime();
    common.printZ("Uptime: ");
    common.printNum(@intCast(s));
    common.printZ(" seconds\r\n");
}

/// Execute 'lsdsk' command
pub export fn cmd_lsdsk() void {
    disk_cmds.lsdsk();
}

/// Execute 'mkfs-fat12' command
pub export fn cmd_mkfs_fat12(drive_num_ptr: [*]const u8, drive_num_len: u32) void {
    if (drive_num_len == 0) {
        common.printZ("Usage: mkfs-fat12 <drive_num>\n");
        return;
    }
    const drive_num = drive_num_ptr[0] - '0';
    disk_cmds.mkfs_fat12(@intCast(drive_num));
}

/// Execute 'mkfs-fat16' command
pub export fn cmd_mkfs_fat16(drive_num_ptr: [*]const u8, drive_num_len: u32) void {
    if (drive_num_len == 0) {
        common.printZ("Usage: mkfs-fat16 <drive_num>\n");
        return;
    }
    const drive_num = drive_num_ptr[0] - '0';
    disk_cmds.mkfs_fat16(@intCast(drive_num));
}


/// Global initialization for Zig-based modules (FS, etc.)
pub export fn zig_init() void {
    common.fs_init();
}

/// Execute 'write' operation (create or overwrite file)
pub export fn cmd_write(name_ptr: [*]const u8, name_len: u32, data_ptr: [*]const u8, data_len: u32) void {
    var id = common.fs_find(name_ptr, @intCast(name_len));
    if (id < 0) {
        id = common.fs_create(name_ptr, @intCast(name_len));
    }
    if (id >= 0) {
        _ = common.fs_write(@intCast(id), data_ptr, @intCast(data_len));
    }
}