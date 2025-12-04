// Nova Language - Commands execution
const common = @import("common.zig");
const parser = @import("parser.zig");

// Execute print command
pub fn execPrint(buffer: []const u8, stmt: parser.Statement) void {
    var i: usize = 0;
    while (i < stmt.arg_len) : (i += 1) {
        common.print_char(buffer[stmt.arg_start + i]);
    }
    common.print_char('\n');
}

// Execute a parsed statement
pub fn execute(buffer: []const u8, stmt: parser.Statement, exit_flag: *bool) void {
    switch (stmt.cmd_type) {
        .print => execPrint(buffer, stmt),
        .exit => exit_flag.* = true,
        .unknown => common.printZ("Syntax Error\n"),
        .empty => {},
    }
}
