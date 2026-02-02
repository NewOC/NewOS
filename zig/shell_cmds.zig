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
const fat = @import("drivers/fat.zig");
const ata = @import("drivers/ata.zig");
const edit = @import("commands/edit.zig");
const rtc = @import("drivers/rtc.zig");


/// Execute 'ls' command
pub export fn cmd_ls() void {
    if (common.selected_disk < 0) {
        ls.execute();
    } else {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            fat.list_root(drive, bpb);
        } else {
            common.printZ("Error: Disk not formatted\n");
        }
    }
}

/// Execute 'cat' command for a given filename
pub export fn cmd_cat(name_ptr: [*]const u8, name_len: u32) void {
    if (common.selected_disk < 0) {
        cat.execute(name_ptr, @intCast(name_len));
    } else {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            if (!fat.stream_to_console(drive, bpb, name_ptr[0..name_len])) {
                common.printZ("Error: File not found\n");
            }
        }
    }
}

/// Execute 'touch' command to create a file
pub export fn cmd_touch(name_ptr: [*]const u8, name_len: u32) void {
    if (common.selected_disk < 0) {
        touch.execute(name_ptr, @intCast(name_len));
    } else {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            const name = name_ptr[0..name_len];
            if (!fat.write_file(drive, bpb, name, "")) {
                common.printZ("Error: Failed to create file on disk\n");
            }
        } else {
            common.printZ("Error: Disk not formatted\n");
        }
    }
}

/// Execute 'rm' command to delete a file
pub export fn cmd_rm(name_ptr: [*]const u8, name_len: u32) void {
    if (common.selected_disk < 0) {
        rm.execute(name_ptr, @intCast(name_len));
    } else {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            if (!fat.delete_file(drive, bpb, name_ptr[0..name_len])) {
                common.printZ("Error: File not found or could not be deleted\n");
            }
        }
    }
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
    common.printZ("System Ticks Uptime: ");
    common.printNum(@intCast(s));
    common.printZ(" seconds\n");
    
    const dt = rtc.get_datetime();
    common.printZ("Current RTC Time: ");
    common.printNum(dt.hour);
    common.printZ(":");
    if (dt.minute < 10) common.printZ("0");
    common.printNum(dt.minute);
    common.printZ(":");
    if (dt.second < 10) common.printZ("0");
    common.printNum(dt.second);
    common.printZ("\r\n");
}

pub export fn cmd_time() void {
    const dt = rtc.get_datetime();
    common.printZ("Date: ");
    common.printNum(dt.day);
    common.printZ(".");
    common.printNum(dt.month);
    common.printZ(".");
    common.printNum(dt.year);
    common.printZ("  Time: ");
    common.printNum(dt.hour);
    common.printZ(":");
    if (dt.minute < 10) common.printZ("0");
    common.printNum(dt.minute);
    common.printZ(":");
    if (dt.second < 10) common.printZ("0");
    common.printNum(dt.second);
    common.printZ("\n");
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
    
    // Auto-select only Disk 1 (Slave) by default if formatted, 
    // leave Disk 0 (Master/System) unmounted for safety.
    if (fat.read_bpb(.Slave) != null) {
        common.selected_disk = 1;
    }
}

/// Execute 'mount' command
pub export fn cmd_mount(disk_num_ptr: [*]const u8, disk_num_len: u32) void {
    if (disk_num_len == 0) {
        common.printZ("Usage: mount <disk_num|ram>\n");
        return;
    }
    
    const arg = disk_num_ptr[0..disk_num_len];
    if (common.std_mem_eql(arg, "ram")) {
        common.selected_disk = -1;
        common.printZ("Switched to RAM FS\n");
        return;
    }
    
    const disk_num = disk_num_ptr[0] - '0';
    if (disk_num > 1) {
        common.printZ("Error: Invalid disk (0 or 1)\n");
        return;
    }
    
    const drive = if (disk_num == 0) ata.Drive.Master else ata.Drive.Slave;
    if (fat.read_bpb(drive) == null) {
        common.printZ("Error: Disk not formatted\n");
        return;
    }
    
    common.selected_disk = @intCast(disk_num);
    common.printZ("Disk ");
    common.printNum(disk_num);
    common.printZ(" mounted\n");
}

/// Execute 'write' operation (create or overwrite file)
pub export fn cmd_write(name_ptr: [*]const u8, name_len: u32, data_ptr: [*]const u8, data_len: u32) void {
    if (common.selected_disk < 0) {
        var id = common.fs_find(name_ptr, @intCast(name_len));
        if (id < 0) {
            id = common.fs_create(name_ptr, @intCast(name_len));
        }
        if (id >= 0) {
            _ = common.fs_write(@intCast(id), data_ptr, @intCast(data_len));
        }
    } else {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            const name = name_ptr[0..name_len];
            const data = data_ptr[0..data_len];
            if (!fat.write_file(drive, bpb, name, data)) {
                common.printZ("Error: Failed to write file to disk\n");
            }
        }
    }
}

pub export fn cmd_edit(name_ptr: [*]const u8, name_len: u32) void {
    edit.execute(name_ptr[0..name_len]);
}