// NewOS Shell - Main command line interface
const common = @import("commands/common.zig");
const keyboard = @import("keyboard_isr.zig");
const shell_cmds = @import("shell_cmds.zig");
const nova = @import("nova.zig");
const messages = @import("messages.zig");
const vga = @import("drivers/vga.zig");
const versioning = @import("versioning.zig");
const serial = @import("drivers/serial.zig");
const fat = @import("drivers/fat.zig");
const ata = @import("drivers/ata.zig");
const config = @import("config.zig");

// Shell configuration
const build_config = @import("build_config");
const HISTORY_SIZE = if (build_config.history_size) |h| h else config.HISTORY_SIZE;

// Command Structure for automated handling and autocomplete
const Command = struct {
    name: []const u8,
    help: []const u8,
    handler: *const fn ([]const u8) void,
};

const SHELL_COMMANDS = [_]Command{
    .{ .name = "help", .help = "Show this help message", .handler = cmd_handler_help },
    .{ .name = "clear", .help = "Clear screen", .handler = cmd_handler_clear },
    .{ .name = "about", .help = "About NewOS", .handler = cmd_handler_about },
    .{ .name = "nova", .help = "Start Nova Interpreter", .handler = cmd_handler_nova },
    .{ .name = "uptime", .help = "Show system uptime", .handler = cmd_handler_uptime },
    .{ .name = "reboot", .help = "Restart the PC", .handler = cmd_handler_reboot },
    .{ .name = "shutdown", .help = "Turn off the PC", .handler = cmd_handler_shutdown },
    .{ .name = "ls", .help = "List files on current disk", .handler = cmd_handler_ls },
    .{ .name = "lsdsk", .help = "List available disks", .handler = cmd_handler_lsdsk },
    .{ .name = "mount", .help = "mount <drive> - Select active disk", .handler = cmd_handler_mount },
    .{ .name = "mkfs-fat12", .help = "mkfs-fat12 <drive> - Format as FAT12", .handler = cmd_handler_mkfs12 },
    .{ .name = "mkfs-fat16", .help = "mkfs-fat16 <drive> - Format as FAT16", .handler = cmd_handler_mkfs16 },
    .{ .name = "touch", .help = "touch <file> - Create empty file", .handler = cmd_handler_touch },
    .{ .name = "write", .help = "write <f> <t> - Write text to file", .handler = cmd_handler_write },
    .{ .name = "rm", .help = "rm <file> - Delete a file", .handler = cmd_handler_rm },
    .{ .name = "cat", .help = "cat <file> - Show file contents", .handler = cmd_handler_cat },
    .{ .name = "edit", .help = "edit <file> - Open text editor", .handler = cmd_handler_edit },
    .{ .name = "history", .help = "Show command history", .handler = cmd_handler_history },
    .{ .name = "echo", .help = "echo <text> - Print text", .handler = cmd_handler_echo },
    .{ .name = "time", .help = "Show current system time (RTC)", .handler = cmd_handler_time },
    .{ .name = "mem", .help = "Show memory allocator status", .handler = cmd_handler_mem },
    .{ .name = "sysinfo", .help = "Show system info", .handler = cmd_handler_sysinfo },
};

// Local command buffer
var cmd_buffer: [1024]u8 = [_]u8{0} ** 1024;
var cmd_len: u16 = 0;
var cmd_pos: u16 = 0;

// Command history state
var history: [HISTORY_SIZE][1024]u8 = [_][1024]u8{[_]u8{0} ** 1024} ** HISTORY_SIZE;
var history_lens: [HISTORY_SIZE]u16 = [_]u16{0} ** HISTORY_SIZE;
var history_count: u8 = 0;
var history_index: u8 = 0;

var insert_mode: bool = true;
var prompt_row: u8 = 0;
var prompt_col: u8 = 0;

var history_loaded: bool = false;

// Autocomplete cycling state
var auto_cycling: bool = false;
var auto_prefix: [64]u8 = [_]u8{0} ** 64;
var auto_prefix_len: usize = 0;
var auto_match_index: usize = 0;
var auto_start_pos: u16 = 0;

/// Read a command from input
pub export fn read_command() void {
    for (&cmd_buffer) |*c| c.* = 0;
    cmd_len = 0;
    cmd_pos = 0;
    history_index = history_count;
    if (!history_loaded) {
        load_history_from_disk();
        history_loaded = true;
    }

    prompt_row = vga.zig_get_cursor_row();
    prompt_col = vga.zig_get_cursor_col();
    refresh_line(); // Initial draw of status bar

    while (true) {
        const char = keyboard.keyboard_wait_char();

        if (char != 9) auto_cycling = false;

        if (char == 10) { // Enter
            break;
        } else if (char == 8) { // Backspace
            if (cmd_pos > 0) {
                // Shift buffer left
                var i: usize = cmd_pos - 1;
                while (i < cmd_len - 1) : (i += 1) {
                    cmd_buffer[i] = cmd_buffer[i + 1];
                }
                cmd_buffer[cmd_len - 1] = 0;
                cmd_pos -= 1;
                cmd_len -= 1;
                refresh_line();
            }
        } else if (char == keyboard.KEY_LEFT) {
            if (cmd_pos > 0) {
                cmd_pos -= 1;
                move_screen_cursor();
            }
        } else if (char == keyboard.KEY_RIGHT) {
            if (cmd_pos < cmd_len) {
                cmd_pos += 1;
                move_screen_cursor();
            }
        } else if (char == keyboard.KEY_HOME) {
            cmd_pos = 0;
            move_screen_cursor();
        } else if (char == keyboard.KEY_END) {
            cmd_pos = cmd_len;
            move_screen_cursor();
        } else if (char == keyboard.KEY_DELETE) {
            if (cmd_pos < cmd_len) {
                // Shift buffer left starting from pos
                var i: usize = cmd_pos;
                while (i < cmd_len - 1) : (i += 1) {
                    cmd_buffer[i] = cmd_buffer[i + 1];
                }
                cmd_buffer[cmd_len - 1] = 0;
                cmd_len -= 1;
                refresh_line();
            }
        } else if (char == keyboard.KEY_INSERT) {
            insert_mode = !insert_mode;
            refresh_line();
        } else if (char == keyboard.KEY_CAPS or char == keyboard.KEY_NUM) {
            refresh_line();
        } else if (char == keyboard.KEY_UP) {
            if (history_count > 0 and history_index > 0) {
                history_index -= 1;
                load_history();
            }
        } else if (char == keyboard.KEY_DOWN) {
            if (history_index < history_count) {
                history_index += 1;
                if (history_index == history_count) {
                    clear_input_line();
                } else {
                    load_history();
                }
            }
        } else if (char == 9) { // Tab
            if (auto_cycling) {
                auto_match_index += 1;
            }
            autocomplete();
            refresh_line();
        } else if (char >= 32 and char <= 126) { // Printable characters
            if (cmd_len < 1023) {
                if (insert_mode) {
                    // Shift buffer right
                    var i: usize = cmd_len;
                    while (i > cmd_pos) : (i -= 1) {
                        cmd_buffer[i] = cmd_buffer[i - 1];
                    }
                    cmd_buffer[cmd_pos] = char;
                    cmd_len += 1;
                    cmd_pos += 1;
                } else {
                    // Overwrite mode
                    cmd_buffer[cmd_pos] = char;
                    if (cmd_pos == cmd_len) cmd_len += 1;
                    cmd_pos += 1;
                }
                refresh_line();
            }
        }
    }

    if (cmd_len > 0) {
        save_to_history();
        save_history_to_disk();
    }
    common.print_char('\r');
    common.print_char('\n');
}

fn save_history_to_disk() void {
    if (common.selected_disk < 0) return;
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    
    if (fat.read_bpb(drive)) |bpb| {
        var join_buf: [HISTORY_SIZE * 1024]u8 = [_]u8{0} ** (HISTORY_SIZE * 1024);
        var offset: usize = 0;
        
        var i: u8 = 0;
        while (i < history_count) : (i += 1) {
            const h_len = history_lens[i];
            for (0..h_len) |j| {
                join_buf[offset] = history[i][j];
                offset += 1;
            }
            join_buf[offset] = '\n';
            offset += 1;
        }
        
        _ = fat.write_file(drive, bpb, "HISTORY", join_buf[0..offset]);
    }
}

fn load_history_from_disk() void {
    if (common.selected_disk < 0) return;
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;

    if (fat.read_bpb(drive)) |bpb| {
        var load_buf: [HISTORY_SIZE * 1024]u8 = [_]u8{0} ** (HISTORY_SIZE * 1024);
        const read = fat.read_file(drive, bpb, "HISTORY", &load_buf);
        if (read <= 0) return;

        history_count = 0;
        var start: usize = 0;
        var i: usize = 0;
        const total: usize = @intCast(read);
        
        while (i < total and history_count < HISTORY_SIZE) : (i += 1) {
            if (load_buf[i] == '\n') {
                const len = i - start;
                if (len > 0 and len < 1024) {
                    for (0..len) |j| history[history_count][j] = load_buf[start + j];
                    history_lens[history_count] = @intCast(len);
                    history_count += 1;
                }
                start = i + 1;
            }
        }
        history_index = history_count;
    }
}

fn refresh_line() void {
    const saved_pos = cmd_pos;
    
    // 1. VGA Update (Silent clear to avoid triggering scrolls during clear)
    {
        var row = prompt_row;
        var col = prompt_col;
        var cleared: usize = 0;
        // Clear up to 2 lines or until end of screen
        while (cleared < 160) : (cleared += 1) {
            if (row >= 25) break;
            const idx = @as(usize, row) * 80 + col;
            vga.VIDEO_MEMORY[idx] = vga.DEFAULT_ATTR | ' ';
            col += 1;
            if (col >= 80) {
                col = 0;
                row += 1;
            }
        }
    }
    
    // Draw text on VGA. We use zig_print_char to allow natural wrapping.
    // If it scrolls, we need to detect it.
    vga.zig_set_cursor(prompt_row, prompt_col);
    const row_before = vga.zig_get_cursor_row();
    for (cmd_buffer[0..cmd_len]) |c| vga.zig_print_char(c);
    const row_after = vga.zig_get_cursor_row();
    
    // If we scrolled, we need to move prompt_row up to stay in sync
    // This is a bit tricky but 1-row scroll is most common
    if (row_after < row_before) { // Very likely a scroll happened
        // Note: this is a simple heuristic. A better way would be a scroll callback.
        if (prompt_row > 0) prompt_row -= 1;
    }
    
    // 2. Serial Update (Terminal-friendly: \r + print whole line)
    serial.serial_print_char('\r');
    serial.serial_print_str("> ");
    serial.serial_print_str(cmd_buffer[0..cmd_len]);
    // Clear tail on serial (3 spaces is enough for small deltas)
    serial.serial_print_str("   "); 
    
    // 3. Move cursor back to position on serial (approximate)
    serial.serial_print_char('\r');
    serial.serial_print_str("> ");
    serial.serial_print_str(cmd_buffer[0..saved_pos]);

    cmd_pos = saved_pos;
    move_screen_cursor();
    
    // Update status indicator in top-right corner
    vga.VIDEO_MEMORY[80 - 14] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'C';
    vga.VIDEO_MEMORY[80 - 13] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'A';
    vga.VIDEO_MEMORY[80 - 12] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'P';
    vga.VIDEO_MEMORY[80 - 11] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'S';
    
    vga.VIDEO_MEMORY[80 - 9]  = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'N';
    vga.VIDEO_MEMORY[80 - 8]  = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'U';
    vga.VIDEO_MEMORY[80 - 7]  = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'M';
    
    const attr = @as(u16, 0x0E00); // Yellow on black
    const status = if (insert_mode) " INS " else " OVR ";
    for (status, 0..) |c, k| {
        vga.VIDEO_MEMORY[80 - 5 + k] = attr | @as(u16, c);
    }
}

fn move_screen_cursor() void {
    var new_col = @as(u16, prompt_col) + cmd_pos;
    var new_row = prompt_row;
    
    while (new_col >= 80) {
        new_col -= 80;
        new_row += 1;
    }
    vga.zig_set_cursor(@intCast(new_row), @intCast(new_col));
}

fn clear_input_line() void {
    cmd_len = 0;
    cmd_pos = 0;
    refresh_line();
}

fn load_history() void {
    clear_input_line();
    const len = history_lens[history_index];
    for (0..len) |i| {
        cmd_buffer[i] = history[history_index][i];
        common.print_char(cmd_buffer[i]);
    }
    cmd_len = len;
    cmd_pos = len;
}

fn save_to_history() void {
    if (history_count == HISTORY_SIZE) {
        for (0..HISTORY_SIZE - 1) |i| {
            history[i] = history[i + 1];
            history_lens[i] = history_lens[i + 1];
        }
        history_count -= 1;
    }
    for (0..cmd_len) |i| history[history_count][i] = cmd_buffer[i];
    history_lens[history_count] = cmd_len;
    history_count += 1;
}

fn autocomplete() void {
    if (cmd_len == 0 and !auto_cycling) return;

    if (!auto_cycling) {
        var start: usize = 0;
        var idx: usize = cmd_pos;
        while (idx > 0) {
            idx -= 1;
            if (cmd_buffer[idx] == ' ') {
                start = idx + 1;
                break;
            }
        }
        auto_start_pos = @intCast(start);
        auto_prefix_len = 0;
        const to_copy = cmd_pos - start;
        while (auto_prefix_len < to_copy and auto_prefix_len < 63) : (auto_prefix_len += 1) {
            auto_prefix[auto_prefix_len] = cmd_buffer[start + auto_prefix_len];
        }
        auto_match_index = 0;
        auto_cycling = true;
    }

    const current_prefix = auto_prefix[0..auto_prefix_len];
    var total_matches: usize = 0;

    if (auto_start_pos == 0) {
        for (SHELL_COMMANDS) |cmd| {
            if (common.startsWithIgnoreCase(cmd.name, current_prefix)) total_matches += 1;
        }
    } else if (common.selected_disk >= 0) {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            var d_buf: [512]u8 = undefined;
            var sector = bpb.first_root_dir_sector;
            while (sector < bpb.first_data_sector) : (sector += 1) {
                ata.read_sector(drive, sector, &d_buf);
                var j: usize = 0;
                while (j < 512) : (j += 32) {
                    if (d_buf[j] == 0) break;
                    if (d_buf[j] == 0xE5) continue;
                    if (d_buf[j+11] == 0x0F) continue;
                    const name = get_name_from_entry(d_buf[j..j+32]);
                    if (common.startsWithIgnoreCase(name.buf[0..name.len], current_prefix)) total_matches += 1;
                }
            }
        }
    }

    if (total_matches == 0) {
        auto_cycling = false;
        return;
    }

    const match_to_pick = auto_match_index % total_matches;
    var current_match_idx: usize = 0;
    var picked_name: [32]u8 = [_]u8{0} ** 32;
    var picked_len: usize = 0;
    var is_cmd = false;

    if (auto_start_pos == 0) {
        for (SHELL_COMMANDS) |cmd| {
            if (common.startsWithIgnoreCase(cmd.name, current_prefix)) {
                if (current_match_idx == match_to_pick) {
                    picked_len = @min(31, cmd.name.len);
                    for (0..picked_len) |p| picked_name[p] = cmd.name[p];
                    is_cmd = true;
                    break;
                }
                current_match_idx += 1;
            }
        }
    } else if (common.selected_disk >= 0) {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            var d_buf: [512]u8 = undefined;
            var sector = bpb.first_root_dir_sector;
            outer: while (sector < bpb.first_data_sector) : (sector += 1) {
                ata.read_sector(drive, sector, &d_buf);
                var j: usize = 0;
                while (j < 512) : (j += 32) {
                    if (d_buf[j] == 0) break;
                    if (d_buf[j] == 0xE5) continue;
                    if (d_buf[j+11] == 0x0F) continue;
                    const name = get_name_from_entry(d_buf[j..j+32]);
                    if (common.startsWithIgnoreCase(name.buf[0..name.len], current_prefix)) {
                        if (current_match_idx == match_to_pick) {
                            picked_len = @min(31, name.len);
                            for (0..picked_len) |p| picked_name[p] = name.buf[p];
                            break :outer;
                        }
                        current_match_idx += 1;
                    }
                }
            }
        }
    }

    if (picked_len > 0) {
        cmd_len = auto_start_pos;
        for (0..picked_len) |p| {
            cmd_buffer[cmd_len] = picked_name[p];
            cmd_len += 1;
        }
        if (is_cmd) {
            cmd_buffer[cmd_len] = ' ';
            cmd_len += 1;
        }
        cmd_pos = cmd_len;
        var z = cmd_len;
        while (z < 1024) : (z += 1) cmd_buffer[z] = 0;
    }
}

fn get_name_from_entry(entry: []const u8) struct { buf: [13]u8, len: usize } {
    var res: [13]u8 = [_]u8{0} ** 13;
    var n_len: usize = 0;
    const case_bits = entry[12];
    const name_lower = (case_bits & 0x08) != 0;
    const ext_lower = (case_bits & 0x10) != 0;
    for (0..8) |k| {
        const c = entry[k];
        if (c == ' ') break;
        res[n_len] = if (name_lower and c >= 'A' and c <= 'Z') c + 32 else c;
        n_len += 1;
    }
    if (entry[8] != ' ') {
        res[n_len] = '.';
        n_len += 1;
        for (0..3) |k| {
            const c = entry[8 + k];
            if (c == ' ') break;
            res[n_len] = if (ext_lower and c >= 'A' and c <= 'Z') c + 32 else c;
            n_len += 1;
        }
    }
    return .{ .buf = res, .len = n_len };
}

/// Dispatch commands
pub export fn execute_command() void {
    const cmd_raw = common.trim(cmd_buffer[0..cmd_len]);
    if (cmd_raw.len == 0) return;

    // Find the end of command name
    var space_idx: usize = 0;
    while (space_idx < cmd_raw.len and cmd_raw[space_idx] != ' ') : (space_idx += 1) {}
    const cmd_name = cmd_raw[0..space_idx];

    for (SHELL_COMMANDS) |sc| {
        if (common.std_mem_eql(sc.name, cmd_name)) {
            sc.handler(cmd_raw);
            return;
        }
    }

    common.printZ("Unknown command: ");
    common.printZ(cmd_name);
    common.printZ("\n");
}

// Handler functions for commands
fn cmd_handler_help(_: []const u8) void {
    common.printZ("Commands:\n");
    for (SHELL_COMMANDS) |cmd| {
        common.printZ("  ");
        common.printZ(cmd.name);
        // Padding for alignment
        var p = cmd.name.len;
        while (p < 15) : (p += 1) common.print_char(' ');
        common.printZ("- ");
        common.printZ(cmd.help);
        common.printZ("\n");
    }
    common.printZ("\n");
}

fn cmd_handler_clear(_: []const u8) void {
    vga.clear_screen();
    messages.print_welcome();
}

fn cmd_handler_about(_: []const u8) void {
    common.printZ("NewOS v" ++ versioning.NEWOS_VERSION ++ "\n");
    common.printZ("32-bit Protected Mode OS\n");
    common.printZ("x86 + Zig kernel modules\n");
    common.printZ("=== By MinecAnton209 ===\n\n");
}

fn cmd_handler_nova(_: []const u8) void {
    nova.nova_start();
}

fn cmd_handler_uptime(_: []const u8) void {
    shell_cmds.cmd_uptime();
}

fn cmd_handler_reboot(_: []const u8) void {
    shell_cmds.cmd_reboot();
}

fn cmd_handler_shutdown(_: []const u8) void {
    shell_cmds.cmd_shutdown();
}

fn cmd_handler_ls(_: []const u8) void {
    shell_cmds.cmd_ls();
}

fn cmd_handler_lsdsk(_: []const u8) void {
    shell_cmds.cmd_lsdsk();
}

fn cmd_handler_mount(full: []const u8) void {
    if (full.len > 6) {
        const arg = full[6..];
        shell_cmds.cmd_mount(arg.ptr, @intCast(arg.len));
    } else { common.printZ("Usage: mount <drive>\n"); }
}

fn cmd_handler_mkfs12(full: []const u8) void {
    if (full.len > 11) {
        const arg = full[11..];
        shell_cmds.cmd_mkfs_fat12(arg.ptr, @intCast(arg.len));
    } else { common.printZ("Usage: mkfs-fat12 <drive>\n"); }
}

fn cmd_handler_mkfs16(full: []const u8) void {
    if (full.len > 11) {
        const arg = full[11..];
        shell_cmds.cmd_mkfs_fat16(arg.ptr, @intCast(arg.len));
    } else { common.printZ("Usage: mkfs-fat16 <drive>\n"); }
}

fn cmd_handler_touch(full: []const u8) void {
    if (full.len > 6) {
        const arg = full[6..];
        shell_cmds.cmd_touch(arg.ptr, @intCast(arg.len));
    } else { common.printZ("Usage: touch <file>\n"); }
}

fn cmd_handler_write(full: []const u8) void {
    if (full.len > 6) {
        const remaining = full[6..];
        if (common.std_mem_indexOf(u8, remaining, " ")) |space| {
            const filename = remaining[0..space];
            const text = remaining[space+1..];
            shell_cmds.cmd_write(filename.ptr, @intCast(filename.len), text.ptr, @intCast(text.len));
        } else { common.printZ("Usage: write <file> <text>\n"); }
    } else { common.printZ("Usage: write <file> <text>\n"); }
}

fn cmd_handler_rm(full: []const u8) void {
    if (full.len > 3) {
        const arg = full[3..];
        shell_cmds.cmd_rm(arg.ptr, @intCast(arg.len));
    } else { common.printZ("Usage: rm <file>\n"); }
}

fn cmd_handler_cat(full: []const u8) void {
    if (full.len > 4) {
        const arg = full[4..];
        shell_cmds.cmd_cat(arg.ptr, @intCast(arg.len));
    } else { common.printZ("Usage: cat <file>\n"); }
}

fn cmd_handler_edit(full: []const u8) void {
    if (full.len > 5) {
        const arg = full[5..];
        shell_cmds.cmd_edit(arg.ptr, @intCast(arg.len));
    } else { common.printZ("Usage: edit <file>\n"); }
}

fn cmd_handler_history(_: []const u8) void {
    var j: u8 = 0;
    while (j < history_count) : (j += 1) {
        common.printNum(j + 1);
        common.printZ(". ");
        common.printZ(history[j][0..history_lens[j]]);
        common.printZ("\n");
    }
}

fn cmd_handler_echo(full: []const u8) void {
    if (full.len > 5) {
        const text = full[5..];
        shell_cmds.cmd_echo(text.ptr, @intCast(text.len));
    }
}

fn cmd_handler_mem(_: []const u8) void {
    const memory_mod = @import("memory.zig");
    common.printZ("Allocator Status:\n");
    const ptr = memory_mod.heap.alloc(64);
    if (ptr) |p| {
        common.printZ("Test Alloc(64): Success 0x");
        common.printNum(@intCast(@intFromPtr(p)));
        common.printZ("\n");
        memory_mod.heap.free(p);
        memory_mod.heap.garbage_collect();
        common.printZ("Memory test stable.\n");
    } else { common.printZ("Allocation failed!\n"); }
}

fn cmd_handler_time(_: []const u8) void {
    shell_cmds.cmd_time();
}

fn cmd_handler_sysinfo(_: []const u8) void {
    shell_cmds.cmd_sysinfo();
}
