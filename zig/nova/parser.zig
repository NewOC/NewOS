// Nova Language - Parser
const common = @import("common.zig");

pub const Statement = struct {
    cmd_type: CmdType,
    arg_start: usize,
    arg_len: usize,
};

pub const CmdType = enum {
    print,
    set_string,
    exit,
    unknown,
    empty,
};

// Parse a statement from buffer starting at pos
pub fn parseStatement(buffer: []const u8, start: usize) Statement {
    var pos = start;
    
    // Skip leading spaces
    while (pos < buffer.len and buffer[pos] == ' ') {
        pos += 1;
    }
    
    // End of buffer
    if (pos >= buffer.len or buffer[pos] == 0) {
        return .{ .cmd_type = .empty, .arg_start = 0, .arg_len = 0 };
    }
    
    // Check for exit();
    if (common.startsWith(buffer[pos..], "exit();")) {
        return .{ .cmd_type = .exit, .arg_start = 0, .arg_len = 0 };
    }
    
    // Check for set string
    // Format: set string <name> = <expr>;
    if (common.startsWith(buffer[pos..], "set string ")) {
        const arg_start = pos + 11; // "set string " len is 11
        var arg_end = arg_start;
        
        // Find semicolon
        while (arg_end < buffer.len and buffer[arg_end] != ';' and buffer[arg_end] != 0) {
            arg_end += 1;
        }
        
        return .{ 
            .cmd_type = .set_string, 
            .arg_start = arg_start, 
            .arg_len = arg_end - arg_start 
        };
    }
    
    // Check for print(
    if (common.startsWith(buffer[pos..], "print(")) {
        const arg_start = pos + 6; // After print(
        var arg_end = arg_start;
        
        // Find closing );
        // We look for ); specifically to be safe, or just )
        // Example: print(1);
        while (arg_end < buffer.len and buffer[arg_end] != 0) {
            if (buffer[arg_end] == ')' and arg_end + 1 < buffer.len and buffer[arg_end + 1] == ';') {
                break;
            }
            arg_end += 1;
        }
        
        return .{ 
            .cmd_type = .print, 
            .arg_start = arg_start, 
            .arg_len = arg_end - arg_start 
        };
    }
    
    return .{ .cmd_type = .unknown, .arg_start = 0, .arg_len = 0 };
}

// Find next statement (after semicolon)
pub fn nextStatement(buffer: []const u8, pos: usize) usize {
    var p = pos;
    while (p < buffer.len and buffer[p] != 0 and buffer[p] != ';') {
        p += 1;
    }
    if (p < buffer.len and buffer[p] == ';') {
        p += 1;
    }
    return p;
}
