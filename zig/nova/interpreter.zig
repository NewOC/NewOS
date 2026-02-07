// Nova Language - Main interpreter REPL
// This module handles input buffering and execution of Nova commands.

const common = @import("common.zig");
const lexer = @import("lexer.zig");
const vm = @import("../vm.zig");
const util = @import("util.zig");
const keyboard = @import("../keyboard_isr.zig");
const versioning = @import("../versioning.zig");
const vga = @import("../drivers/vga.zig");
const serial = @import("../drivers/serial.zig");
const global_common = @import("../commands/common.zig");
const fat = @import("../drivers/fat.zig");
const ata = @import("../drivers/ata.zig");

const BUFFER_SIZE: usize = 128;
const HISTORY_SIZE: usize = 10;

const NOVA_KEYWORDS = [_][]const u8{
    "print", "def", "import", "if", "else", "while", "exit", "reboot", "shutdown",
    "sleep", "shell", "input", "random", "argc", "args", "set", "int", "string",
    "delete", "rename", "copy", "mkdir", "write_file", "create_file", "read",
    "abs", "min", "max", "sin", "cos", "tan", "tg", "ctg",
};

// Interpreter state
var buffer: [BUFFER_SIZE]u8 = [_]u8{0} ** BUFFER_SIZE;
var buf_len: u16 = 0;
var buf_pos: u16 = 0;
var insert_mode: bool = true;
var prompt_row: u8 = 0;
var prompt_col: u8 = 0;
var exit_flag: bool = false;

// VM state
var global_vm: vm.VM = undefined;
var vm_initialized: bool = false;

// History state
var history: [HISTORY_SIZE][BUFFER_SIZE]u8 = [_][BUFFER_SIZE]u8{[_]u8{0} ** BUFFER_SIZE} ** HISTORY_SIZE;
var history_lens: [HISTORY_SIZE]u16 = [_]u16{0} ** HISTORY_SIZE;
var history_count: u8 = 0;
var history_index: u8 = 0;

// Autocomplete state
var auto_cycling: bool = false;
var auto_prefix: [64]u8 = [_]u8{0} ** 64;
var auto_prefix_len: usize = 0;
var auto_match_index: usize = 0;
var auto_start_pos: u16 = 0;

/// Read a simple line of input into the provided buffer
pub fn readInput(buf: []u8) usize {
    var length: usize = 0;
    while (length < buf.len - 1) {
        const key = keyboard.keyboard_wait_char();
        if (key == 10 or key == 13) { // Enter
            common.print_char('\n');
            break;
        } else if (key == 8 or key == 127) { // Backspace
            if (length > 0) {
                length -= 1;
                buf[length] = 0;
                // Visually backspace
                const cur_row = vga.zig_get_cursor_row();
                const cur_col = vga.zig_get_cursor_col();
                if (cur_col > 0) {
                    vga.zig_set_cursor(cur_row, cur_col - 1);
                    vga.zig_print_char(' ');
                    vga.zig_set_cursor(cur_row, cur_col - 1);
                }
            }
        } else if (key >= 32 and key <= 126) {
            buf[length] = key;
            length += 1;
            common.print_char(key);
        }
    }
    return length;
}

/// Start the Nova interpreter environment
pub fn start(script_path: ?[]const u8) void {
    if (!vm_initialized) {
        global_vm = vm.VM.init();
        vm_initialized = true;
    }

    exit_flag = false;
    global_common.seed_random_with_tsc();

    if (script_path) |path| {
        runScript(path);
    } else {
        // Welcome message
        common.printZ("Nova Language v" ++ versioning.NOVA_VERSION ++ "\n" ++
            "Commands: print(\"text\"); exit();\n");

        // Main REPL loop (Read-Eval-Print Loop)
        while (!exit_flag and !global_vm.exit_flag) {
            common.printZ("nova> ");
            readLine();
            if (exit_flag) break;
            executeLine();
        }
    }
}

pub fn runScript(path: []const u8) void {
    const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    if (global_common.selected_disk < 0) {
        global_common.printError("Error: No disk mounted. Please use 'mount 0' first.\n");
        return;
    }

    if (fat.read_bpb(drive)) |bpb| {
        if (fat.find_entry(drive, bpb, global_common.current_dir_cluster, path)) |entry| {
            if ((entry.attr & 0x10) != 0) {
                global_common.printError("Error: Path is a directory\n");
                return;
            }

            const size = entry.file_size;
            const script_ptr = global_common.heap.alloc(size) orelse return;
            const script_slice = @as([*]u8, @ptrCast(script_ptr))[0..size];
            const bytes_read = fat.read_file(drive, bpb, global_common.current_dir_cluster, path, script_slice);

            if (bytes_read > 0) {
                runScriptSource(script_slice);
            } else {
                global_common.printError("Error: Empty file or read error\n");
            }
        } else {
            global_common.printError("Error: Script not found: ");
            global_common.printError(path);
            global_common.printError("\n");
        }
    }
}

pub fn runScriptSource(script: []const u8) void {
    if (!vm_initialized) {
        global_vm = vm.VM.init();
        vm_initialized = true;
    }

    var script_lexer = lexer.Lexer.init(script);
    var tokens_list = script_lexer.tokenize() catch {
        global_common.printError("Lexer Error\n");
        return;
    };

    const tokens = tokens_list.items[0..tokens_list.len];
    _ = global_vm.allocated_tokens.append(tokens) catch {};
    _ = global_vm.allocated_sources.append(script) catch {};

    global_vm.run(tokens) catch |err| {
        global_common.printError("VM Error: ");
        _ = err;
        global_common.printError("\n");
    };
}

/// Read a single line of input from the keyboard
fn readLine() void {
    buf_len = 0;
    buf_pos = 0;
    for (&buffer) |*b| b.* = 0;
    history_index = history_count;

    prompt_row = vga.zig_get_cursor_row();
    prompt_col = vga.zig_get_cursor_col();
    refreshLine(); // Initial draw of status bar

    while (true) {
        const key = keyboard.keyboard_wait_char();

        if (key == 3) {
            common.printZ("^C\n");
            buf_len = 0;
            buf_pos = 0;
            return;
        }

        if (key != 9) auto_cycling = false;

        if (key == 10 or key == 13) { // Enter
            if (buf_len > 0) {
                saveToHistory();
            }
            common.print_char('\n');
            return;
        } else if (key == 8 or key == 127) { // Backspace
            if (buf_pos > 0) {
                var i: usize = buf_pos - 1;
                while (i < buf_len - 1) : (i += 1) {
                    buffer[i] = buffer[i + 1];
                }
                buffer[buf_len - 1] = 0;
                buf_pos -= 1;
                buf_len -= 1;
                refreshLine();
            }
        } else if (key == keyboard.KEY_LEFT) {
            if (buf_pos > 0) {
                buf_pos -= 1;
                moveScreenCursor();
            }
        } else if (key == keyboard.KEY_RIGHT) {
            if (buf_pos < buf_len) {
                buf_pos += 1;
                moveScreenCursor();
            }
        } else if (key == keyboard.KEY_HOME) {
            buf_pos = 0;
            moveScreenCursor();
        } else if (key == keyboard.KEY_END) {
            buf_pos = buf_len;
            moveScreenCursor();
        } else if (key == keyboard.KEY_UP) {
            if (history_count > 0 and history_index > 0) {
                history_index -= 1;
                loadHistory();
            }
        } else if (key == keyboard.KEY_DOWN) {
            if (history_index < history_count) {
                history_index += 1;
                if (history_index == history_count) {
                    buf_len = 0;
                    buf_pos = 0;
                    for (&buffer) |*b| b.* = 0;
                    refreshLine();
                } else {
                    loadHistory();
                }
            }
        } else if (key == keyboard.KEY_DELETE) {
            if (buf_pos < buf_len) {
                var i: usize = buf_pos;
                while (i < buf_len - 1) : (i += 1) {
                    buffer[i] = buffer[i + 1];
                }
                buffer[buf_len - 1] = 0;
                buf_len -= 1;
                refreshLine();
            }
        } else if (key == keyboard.KEY_INSERT) {
            insert_mode = !insert_mode;
            refreshLine();
        } else if (key == keyboard.KEY_CAPS or key == keyboard.KEY_NUM) {
            refreshLine();
        } else if (key == 9) { // Tab
            if (auto_cycling) {
                auto_match_index += 1;
            }
            autocomplete();
            refreshLine();
        } else if (key >= 32 and key <= 126) { // Printable characters
            if (buf_len < BUFFER_SIZE - 1) {
                if (insert_mode) {
                    var i: usize = buf_len;
                    while (i > buf_pos) : (i -= 1) {
                        buffer[i] = buffer[i - 1];
                    }
                    buffer[buf_pos] = key;
                    buf_len += 1;
                    buf_pos += 1;
                } else {
                    buffer[buf_pos] = key;
                    if (buf_pos == buf_len) buf_len += 1;
                    buf_pos += 1;
                }
                refreshLine();
            }
        } else if (key == 27) { // ESC
            // Clear line?
        }
    }
}

fn loadHistory() void {
    buf_len = history_lens[history_index];
    for (0..buf_len) |i| buffer[i] = history[history_index][i];
    for (buf_len..BUFFER_SIZE) |i| buffer[i] = 0;
    buf_pos = buf_len;
    refreshLine();
}

fn saveToHistory() void {
    if (history_count == HISTORY_SIZE) {
        for (0..HISTORY_SIZE - 1) |i| {
            history[i] = history[i + 1];
            history_lens[i] = history_lens[i + 1];
        }
        history_count -= 1;
    }
    for (0..buf_len) |i| history[history_count][i] = buffer[i];
    history_lens[history_count] = buf_len;
    history_count += 1;
}

fn autocomplete() void {
    if (buf_len == 0 and !auto_cycling) return;

    if (!auto_cycling) {
        var s_idx: usize = 0;
        var idx: usize = buf_pos;
        while (idx > 0) {
            idx -= 1;
            if (buffer[idx] == ' ' or buffer[idx] == ';') {
                s_idx = idx + 1;
                break;
            }
        }
        auto_start_pos = @intCast(s_idx);
        auto_prefix_len = 0;
        const to_copy = buf_pos - s_idx;
        while (auto_prefix_len < to_copy and auto_prefix_len < 63) : (auto_prefix_len += 1) {
            auto_prefix[auto_prefix_len] = buffer[s_idx + auto_prefix_len];
        }
        auto_match_index = 0;
        auto_cycling = true;
    }

    const current_prefix = auto_prefix[0..auto_prefix_len];
    var total_matches: usize = 0;

    for (NOVA_KEYWORDS) |kw| {
        if (global_common.startsWithIgnoreCase(kw, current_prefix)) total_matches += 1;
    }

    if (total_matches == 0) {
        auto_cycling = false;
        return;
    }

    const match_to_pick = auto_match_index % total_matches;
    var current_match_idx: usize = 0;

    for (NOVA_KEYWORDS) |kw| {
        if (global_common.startsWithIgnoreCase(kw, current_prefix)) {
            if (current_match_idx == match_to_pick) {
                buf_len = auto_start_pos;
                for (kw) |c| {
                    buffer[buf_len] = c;
                    buf_len += 1;
                }
                buf_pos = buf_len;
                var z = buf_len;
                while (z < BUFFER_SIZE) : (z += 1) buffer[z] = 0;
                break;
            }
            current_match_idx += 1;
        }
    }
}

fn refreshLine() void {
    const saved_pos = buf_pos;

    // VGA Update
    vga.zig_set_cursor(prompt_row, prompt_col);
    {
        var row = prompt_row;
        var col = prompt_col;
        var cleared: usize = 0;
        while (cleared < 80) : (cleared += 1) {
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

    vga.zig_set_cursor(prompt_row, prompt_col);
    const row_before = vga.zig_get_cursor_row();
    for (buffer[0..buf_len]) |c| vga.zig_print_char(c);
    const row_after = vga.zig_get_cursor_row();
    if (row_after < row_before and prompt_row > 0) prompt_row -= 1;

    // Serial Update
    serial.serial_hide_cursor();
    serial.serial_set_cursor(prompt_row, prompt_col);
    serial.serial_print_str(buffer[0..buf_len]);
    serial.serial_clear_line();

    buf_pos = saved_pos;
    moveScreenCursor();
    serial.serial_show_cursor();

    // Update status indicators
    vga.VIDEO_MEMORY[80 - 14] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'C';
    vga.VIDEO_MEMORY[80 - 13] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'A';
    vga.VIDEO_MEMORY[80 - 12] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'P';
    vga.VIDEO_MEMORY[80 - 11] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'S';

    vga.VIDEO_MEMORY[80 - 9] = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'N';
    vga.VIDEO_MEMORY[80 - 8] = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'U';
    vga.VIDEO_MEMORY[80 - 7] = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'M';

    const attr = @as(u16, 0x0E00);
    const status = if (insert_mode) " INS " else " OVR ";
    for (status, 0..) |c, k| vga.VIDEO_MEMORY[80 - 5 + k] = attr | @as(u16, c);
}

fn moveScreenCursor() void {
    var new_col = @as(u16, prompt_col) + buf_pos;
    var new_row = prompt_row;
    while (new_col >= 80) {
        new_col -= 80;
        new_row += 1;
    }
    vga.zig_set_cursor(@intCast(new_row), @intCast(new_col));
}

/// Parse and execute the buffered command line
fn executeLine() void {
    if (buf_len == 0) return;
    runScriptSource(buffer[0..buf_len]);
}
