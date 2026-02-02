// NewOS Shell - Main command line interface
const common = @import("commands/common.zig");
const keyboard = @import("keyboard_isr.zig");
const shell_cmds = @import("shell_cmds.zig");
const nova = @import("nova.zig");
const messages = @import("messages.zig");
const vga = @import("drivers/vga.zig");
const versioning = @import("versioning.zig");


// Shell configuration
const HISTORY_SIZE = 10;

// Local command buffer
var cmd_buffer: [128]u8 = [_]u8{0} ** 128;
var cmd_len: u8 = 0;
var cmd_pos: u8 = 0;

// Command history state
var history: [HISTORY_SIZE][128]u8 = [_][128]u8{[_]u8{0} ** 128} ** HISTORY_SIZE;
var history_lens: [HISTORY_SIZE]u8 = [_]u8{0} ** HISTORY_SIZE;
var history_count: u8 = 0;
var history_index: u8 = 0;

/// Read a command from input
pub export fn read_command() void {
    for (&cmd_buffer) |*c| c.* = 0;
    cmd_len = 0;
    cmd_pos = 0;
    history_index = history_count;

    while (true) {
        const char = keyboard.keyboard_wait_char();

        if (char == 10) { // Enter
            break;
        } else if (char == 8) { // Backspace
            if (cmd_pos > 0) {
                cmd_pos -= 1;
                cmd_len -= 1;
                cmd_buffer[cmd_pos] = 0;
                common.print_char(8);
            }
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
        } else if (char >= 32 and char <= 126) { // Printable characters
            if (cmd_len < 127) {
                cmd_buffer[cmd_pos] = char;
                cmd_len += 1;
                cmd_pos += 1;
                common.print_char(char);
            }
        }
    }

    if (cmd_len > 0) save_to_history();
    common.print_char('\r');
    common.print_char('\n');
}

fn clear_input_line() void {
    vga.zig_clear_line(vga.cursor_row);
    vga.cursor_col = 0;
    common.printZ("> ");
    cmd_pos = 0;
    cmd_len = 0;
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

/// Dispatch commands
pub export fn execute_command() void {
    //if (cmd_len == 0) return;
    const cmd = cmd_buffer[0..cmd_len];

    if (common.std_mem_eql(cmd, "help")) {
        common.printZ("Commands:\n");
        common.printZ("  help           - Show help\n");
        common.printZ("  clear          - Clear screen\n");
        common.printZ("  about          - About OS\n");
        common.printZ("  nova           - Start Nova\n");
        common.printZ("  uptime         - Show system uptime\n");
        common.printZ("  reboot         - Reboot PC\n");
        common.printZ("  shutdown       - Shutdown PC\n");
        common.printZ("  ls             - List files\n");
        common.printZ("  touch <file>   - Create file\n");
        common.printZ("  rm <file>      - Delete file\n");
        common.printZ("  cat <file>     - Show contents\n");
        common.printZ("  echo <text>    - Print text\n\n");
    } else if (common.std_mem_eql(cmd, "clear")) {
        vga.clear_screen();
        messages.print_welcome();
    } else if (common.std_mem_eql(cmd, "about")) {
        common.printZ("NewOS v" ++ versioning.NEWOS_VERSION ++ "\n");
        common.printZ("32-bit Protected Mode OS\n");
        common.printZ("x86 + Zig kernel modules\n");
        common.printZ("=== By MinecAnton209 ===\n\n");
    } else if (common.std_mem_eql(cmd, "nova")) {
        nova.nova_start();
    } else if (common.std_mem_eql(cmd, "uptime")) {
        shell_cmds.cmd_uptime();
    } else if (common.std_mem_eql(cmd, "reboot")) {
        shell_cmds.cmd_reboot();
    } else if (common.std_mem_eql(cmd, "shutdown")) {
        shell_cmds.cmd_shutdown();
    } else if (common.std_mem_eql(cmd, "ls")) {
        shell_cmds.cmd_ls();
    } else if (common.startsWith(cmd, "touch ")) {
        const filename = cmd[6..];
        shell_cmds.cmd_touch(filename.ptr, @intCast(filename.len));
    } else if (common.startsWith(cmd, "rm ")) {
        const filename = cmd[3..];
        shell_cmds.cmd_rm(filename.ptr, @intCast(filename.len));
    } else if (common.startsWith(cmd, "cat ")) {
        const filename = cmd[4..];
        shell_cmds.cmd_cat(filename.ptr, @intCast(filename.len));
    } else if (common.startsWith(cmd, "echo ")) {
        const text = cmd[5..];
        shell_cmds.cmd_echo(text.ptr, @intCast(text.len));
    } else {
        common.printZ("Unknown: [");
        common.printZ(cmd);
        common.printZ("] (Len: ");
        common.printNum(@intCast(cmd_len));
        common.printZ(") Hex: ");
        for (cmd) |c| {
            const hex = "0123456789ABCDEF";
            common.print_char(hex[c >> 4]);
            common.print_char(hex[c & 0x0F]);
            common.print_char(' ');
        }
        common.printZ("\n");
    }
}
