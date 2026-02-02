// Nova Language - Main interpreter REPL
// This module handles input buffering and execution of Nova commands.

const common = @import("common.zig");
const parser = @import("parser.zig");
const commands = @import("commands.zig");
const keyboard = @import("../keyboard_isr.zig");
const versioning = @import("../versioning.zig");


// External screen functions
extern fn zig_print_char(c: u8) void;

const BUFFER_SIZE: usize = 128;

// Interpreter state
var buffer: [BUFFER_SIZE]u8 = undefined;
var buf_len: u8 = 0;
var exit_flag: bool = false;

/// Start the Nova interpreter environment
pub fn start() void {
    exit_flag = false;
    
    // Welcome message
    common.printZ(
        "Nova Language v" ++ versioning.NOVA_VERSION ++ "\n" ++
        "Commands: print(\"text\"); exit();\n"
    );
    
    // Main REPL loop (Read-Eval-Print Loop)
    while (!exit_flag) {
        common.printZ("nova> ");
        readLine();
        executeLine();
    }
}

/// Read a single line of input from the keyboard
fn readLine() void {
    buf_len = 0;
    for (&buffer) |*b| b.* = 0;
    
    while (true) {
        const key = keyboard.keyboard_wait_char();
        
        // Handle Enter key
        if (key == 10 or key == 13) { 
            common.print_char('\n');
            return;
        }
        
        // Handle Backspace
        if (key == 8 or key == 127) { 
            if (buf_len > 0) {
                buf_len -= 1;
                buffer[buf_len] = 0;
                
                common.print_char(8);  // Move back
                common.print_char(' '); // Clear char
                common.print_char(8);  // Move back again
            }
            continue;
        }
        
        // Handle printable characters
        if (buf_len < BUFFER_SIZE - 1 and key >= 32 and key < 127) {
            buffer[buf_len] = key;
            buf_len += 1;
            common.print_char(key);
        }
    }
}

/// Parse and execute the buffered command line
fn executeLine() void {
    if (buf_len == 0) return;
    
    var pos: usize = 0;
    // Iterate through all statements in the buffer (separated by ;)
    while (pos < buf_len and !exit_flag) {
        const stmt = parser.parseStatement(buffer[0..buf_len], pos);
        
        if (stmt.cmd_type == .empty) break;
        
        // Execute the parsed command
        commands.execute(buffer[0..buf_len], stmt, &exit_flag);
        
        // Move pos to the next statement
        pos = parser.nextStatement(buffer[0..buf_len], pos);
    }
}