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
const sysinfo = @import("commands/sysinfo.zig");
const file_utils = @import("commands/file_utils.zig");
const docs = @import("commands/docs.zig");

extern fn shell_clear_history() void;

pub fn clear_shell_history() void {
    shell_clear_history();
}

pub export fn cmd_docs(args: [*]const u8, args_len: u32) void {
    docs.execute(args[0..args_len]);
}

pub export fn cmd_cp(args_ptr: [*]const u8, args_len: u32) void {
    file_utils.cmd_cp(args_ptr[0..args_len]);
}

pub export fn cmd_mv(args_ptr: [*]const u8, args_len: u32) void {
    file_utils.cmd_mv(args_ptr[0..args_len]);
}

pub export fn cmd_rename(args_ptr: [*]const u8, args_len: u32) void {
    file_utils.cmd_rename(args_ptr[0..args_len]);
}

pub export fn cmd_format(args_ptr: [*]const u8, args_len: u32) void {
    file_utils.cmd_format(args_ptr[0..args_len]);
}

pub export fn cmd_mkfs(args_ptr: [*]const u8, args_len: u32) void {
    file_utils.cmd_mkfs(args_ptr[0..args_len]);
}


/// Execute 'ls' command
pub export fn cmd_ls(args_ptr: [*]const u8, args_len: u32) void {
    if (common.selected_disk < 0) {
        ls.execute();
    } else {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            const args = args_ptr[0..args_len];
            if (args.len == 0) {
                fat.list_directory(drive, bpb, common.current_dir_cluster);
            } else {
                if (fat.resolve_path(drive, bpb, common.current_dir_cluster, args)) |res| {
                    if (fat.find_entry_literal(drive, bpb, res.dir_cluster, res.file_name)) |entry| {
                        if ((entry.attr & 0x10) != 0) {
                            fat.list_directory(drive, bpb, entry.first_cluster_low);
                        } else {
                            common.printZ("Error: Not a directory\n");
                        }
                    } else {
                        common.printZ("Error: Path not found\n");
                    }
                } else {
                    common.printZ("Error: Path resolve failed\n");
                }
            }
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
            if (!fat.stream_to_console(drive, bpb, common.current_dir_cluster, name_ptr[0..name_len])) {
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
            if (!fat.write_file(drive, bpb, common.current_dir_cluster, name_ptr[0..name_len], "")) {
                common.printZ("Error: Failed to create file on disk\n");
            }
        } else {
            common.printZ("Error: Disk not formatted\n");
        }
    }
}

/// Execute 'rm' command to delete a file or directory
pub export fn cmd_rm(args_ptr: [*]const u8, args_len: u32) void {
    if (common.selected_disk < 0) {
        rm.execute(args_ptr, @intCast(args_len));
        return;
    }

    const args_raw = args_ptr[0..args_len];
    const args = common.trim(args_raw);
    if (args.len == 0) {
        common.printZ("Usage: rm [-d] [-r] <file|*>\n");
        return;
    }

    var recursive = false;
    var delete_dirs = false;
    var sure = false;
    var target: []const u8 = "";

    // Basic space-based split for flags
    var i: usize = 0;
    while (i < args.len) {
        // Skip spaces
        while (i < args.len and args[i] == ' ') : (i += 1) {}
        if (i >= args.len) break;
        
        const start = i;
        while (i < args.len and args[i] != ' ') : (i += 1) {}
        const arg = args[start..i];

        if (common.std_mem_eql(arg, "-r")) {
            recursive = true;
        } else if (common.std_mem_eql(arg, "-d")) {
            delete_dirs = true;
        } else if (common.std_mem_eql(arg, "-rd") or common.std_mem_eql(arg, "-dr")) {
            recursive = true;
            delete_dirs = true;
        } else if (common.std_mem_eql(arg, "--yes-i-am-sure")) {
            sure = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            target = arg;
        }
    }

    if (target.len == 0) {
        common.printZ("Error: No target specified\n");
        return;
    }

    // Confirmation logic for rm *
    if (common.std_mem_eql(target, "*")) {
        if (!recursive or !delete_dirs or !sure) {
            common.printZ("Are you sure? I worked so hard on these files...\n");
            common.printZ("To delete EVERYTHING (files & folders), use: rm -dr * --yes-i-am-sure\n");
            return;
        }
    }

    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    if (fat.read_bpb(drive)) |bpb| {
        if (common.std_mem_eql(target, "*")) {
            fat.delete_all_in_directory(drive, bpb, common.current_dir_cluster, recursive, delete_dirs);
            common.printZ("Target contents deleted.\n");
        } else {
            if (recursive or delete_dirs) {
                if (fat.delete_directory(drive, bpb, common.current_dir_cluster, target, recursive)) {
                    common.printZ("Deleted: ");
                    common.printZ(target);
                    common.printZ("\n");
                } else {
                    common.printZ("Error: Failed to delete directory (not empty? use -r)\n");
                }
            } else {
                // Check if it's a directory before deleting as file
                if (fat.find_entry(drive, bpb, common.current_dir_cluster, target)) |entry| {
                    if ((entry.attr & 0x10) != 0) {
                        common.printZ("Error: Target is a directory (use -d)\n");
                        return;
                    }
                }
                
                if (fat.delete_file(drive, bpb, common.current_dir_cluster, target)) {
                    common.printZ("Deleted: ");
                    common.printZ(target);
                    common.printZ("\n");
                } else {
                    common.printZ("Error: File not found\n");
                }
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
    common.current_dir_cluster = 0; // Reset to Root
    common.current_path_len = 0;
    common.printZ("Disk ");
    common.printNum(disk_num);
    common.printZ(" mounted\n");
}

pub export fn cmd_mkdir(name_ptr: [*]const u8, name_len: u32) void {
    if (common.selected_disk < 0) {
        common.printZ("Error: mkdir only supported on Disk FS\n");
        return;
    }
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    if (fat.read_bpb(drive)) |bpb| {
        if (!fat.create_directory(drive, bpb, common.current_dir_cluster, name_ptr[0..name_len])) {
            common.printZ("Error: Failed to create directory\n");
        }
    }
}

pub export fn cmd_cd(name_ptr: [*]const u8, name_len: u32) void {
    if (common.selected_disk < 0) {
        common.printZ("Error: cd only supported on Disk FS\n");
        return;
    }
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    const name = name_ptr[0..name_len];

    if (fat.read_bpb(drive)) |bpb| {
        if (name.len == 0 or common.std_mem_eql(name, "/")) {
            common.current_dir_cluster = 0;
            common.current_path_len = 0;
            return;
        }

        if (common.std_mem_eql(name, ".")) {
            common.printZ("Wow, you're already here!\n");
            return;
        }

        if (common.std_mem_eql(name, "..")) {
            if (common.current_dir_cluster == 0) {
                common.printZ("There is no escape from the root!\n");
                return;
            }
            const entry = fat.find_entry(drive, bpb, common.current_dir_cluster, "..") orelse {
                common.current_dir_cluster = 0;
                common.current_path_len = 0;
                return;
            };
            common.current_dir_cluster = entry.first_cluster_low;
            // Update path (pop last part)
            if (common.current_path_len > 0) {
                var p = common.current_path_len - 1;
                while (p > 0 and common.current_path[p] != '/') : (p -= 1) {}
                common.current_path_len = p;
            }
            return;
        }

        if (fat.resolve_path(drive, bpb, common.current_dir_cluster, name)) |res| {
            if (fat.find_entry(drive, bpb, res.dir_cluster, res.file_name)) |entry| {
                if ((entry.attr & 0x10) != 0) {
                    common.current_dir_cluster = entry.first_cluster_low;
                    // Append or update path
                    if (args_only_for_cd(name)) {
                        // If user used ../... we might want to recalculate full path or just handle it.
                        // For now simple append.
                        if (common.current_path_len + 1 + res.file_name.len < 256) {
                            common.current_path[common.current_path_len] = '/';
                            for (res.file_name, 0..) |c, k| common.current_path[common.current_path_len + 1 + k] = c;
                            common.current_path_len += 1 + res.file_name.len;
                        }
                    }
                } else {
                    common.printZ("Error: Not a directory\n");
                }
            } else {
                common.printZ("Error: Directory not found\n");
            }
        } else {
            common.printZ("Error: Path not resolved\n");
        }
    }
}

fn args_only_for_cd(name: []const u8) bool {
    // Helper to determine if we should update path simply
    if (common.std_mem_eql(name, ".") or common.std_mem_eql(name, "..")) return false;
    return true;
}

pub export fn cmd_tree() void {
    if (common.selected_disk < 0) {
        common.printZ("Error: tree only supported on Disk FS\n");
        return;
    }
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    if (fat.read_bpb(drive)) |bpb| {
        common.printZ(".\n");
        tree_node(drive, bpb, common.current_dir_cluster, 1);
    }
}

fn tree_node(drive: ata.Drive, bpb: fat.BPB, dir_cluster: u32, depth: usize) void {
    // We need a way to list directory but instead of printing, we recurse.
    // For now, let's just make it print with indentation if we had a way to iterate.
    // Let's add an iterator or just uses a simplified version.
    
    var buffer: [512]u8 = undefined;
    if (dir_cluster == 0) {
        var sector = bpb.first_root_dir_sector;
        while (sector < bpb.first_data_sector) : (sector += 1) {
            ata.read_sector(drive, sector, &buffer);
            if (!tree_sector(drive, bpb, &buffer, depth)) break;
        }
    } else {
        var current = dir_cluster;
        const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);
        while (current < eof_val) {
            const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
            var s: u32 = 0;
            while (s < bpb.sectors_per_cluster) : (s += 1) {
                ata.read_sector(drive, lba + s, &buffer);
                if (!tree_sector(drive, bpb, &buffer, depth)) break;
            }
            current = fat.get_fat_entry(drive, bpb, current);
            if (current == 0) break;
        }
    }
}

fn tree_sector(drive: ata.Drive, bpb: fat.BPB, buffer: *[512]u8, depth: usize) bool {
    var i: u32 = 0;
    while (i < 512) : (i += 32) {
        if (buffer[i] == 0) return false;
        if (buffer[i] == 0xE5) continue;
        if (buffer[i + 11] == 0x0F) continue; // LFN

        const name = fat.get_name_from_raw(buffer[i..i+32]);
        if (common.std_mem_eql(name.buf[0..name.len], ".") or common.std_mem_eql(name.buf[0..name.len], "..")) continue;

        for (0..depth) |_| common.printZ("  ");
        common.printZ("|- ");
        common.printZ(name.buf[0..name.len]);
        common.printZ("\n");

        if ((buffer[i + 11] & 0x10) != 0) { // Directory
            const cluster = @as(u32, buffer[i + 26]) | (@as(u32, buffer[i + 27]) << 8);
            if (cluster != 0) tree_node(drive, bpb, cluster, depth + 1);
        }
    }
    return true;
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
            if (!fat.write_file(drive, bpb, common.current_dir_cluster, name, data)) {
                common.printZ("Error: Failed to write file to disk\n");
            }
        }
    }
}

pub export fn cmd_edit(name_ptr: [*]const u8, name_len: u32) void {
    edit.execute(name_ptr[0..name_len]);
}

pub export fn cmd_sysinfo() void {
    sysinfo.execute();
}