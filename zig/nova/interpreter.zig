// Nova Language - Main interpreter
const common = @import("common.zig");
const parser = @import("parser.zig");
const commands = @import("commands.zig");

extern fn zig_print_char(c: u8) void;
extern fn wait_key() u8;

const BUFFER_SIZE: usize = 128;

var buffer: [BUFFER_SIZE]u8 = undefined;
var buf_len: u8 = 0;
var exit_flag: bool = false;

// External cursor vars (from asm)
// We'll manage our own state

pub fn start() void {
    exit_flag = false;
    
    // Welcome
    common.printZ("Nova Language v0.2 (Zig)\n");
    common.printZ("Commands: print(\"text\"); exit();\n");
    
    // REPL loop
    while (!exit_flag) {
        common.printZ("nova> ");
        readLine();
        executeLine();
    }
}

fn readLine() void {
    buf_len = 0;
    for (&buffer) |*b| b.* = 0;
    
    while (true) {
        const key = wait_key();
        
        if (key == 10) { // Enter
            common.print_char('\n');
            return;
        }
        
        if (key == 8) { // Backspace
            if (buf_len > 0) {
                buf_len -= 1;
                buffer[buf_len] = 0;
                // Visual backspace handled by wait_key? 
                // Need to print backspace sequence
                common.print_char(8);
                common.print_char(' ');
                common.print_char(8);
            }
            continue;
        }
        
        // Regular character
        if (buf_len < BUFFER_SIZE - 1 and key >= 32 and key < 127) {
            buffer[buf_len] = key;
            buf_len += 1;
            common.print_char(key);
        }
    }
}

fn executeLine() void {
    if (buf_len == 0) return;
    
    var pos: usize = 0;
    while (pos < buf_len and !exit_flag) {
        const stmt = parser.parseStatement(buffer[0..buf_len], pos);
        
        if (stmt.cmd_type == .empty) break;
        
        commands.execute(buffer[0..buf_len], stmt, &exit_flag);
        pos = parser.nextStatement(buffer[0..buf_len], pos);
    }
}
