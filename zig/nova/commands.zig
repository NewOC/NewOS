// Nova Language - Commands execution
const common = @import("common.zig");
const parser = @import("parser.zig");

// --- Variable Storage ---
const MAX_VARS = 16;
const MAX_VAR_NAME = 16;
const MAX_VAL_LEN = 64;

const Variable = struct {
    name: [MAX_VAR_NAME]u8,
    name_len: usize,
    value: [MAX_VAL_LEN]u8,
    val_len: usize,
};

var variables: [MAX_VARS]Variable = undefined;
var var_count: usize = 0;

var eval_buffer: [256]u8 = undefined;

// --- Helper Functions ---

fn trim(s: []const u8) []const u8 {
    if (s.len == 0) return s;
    var start: usize = 0;
    while (start < s.len and s[start] == ' ') : (start += 1) {}
    var end: usize = s.len;
    while (end > start and s[end - 1] == ' ') : (end -= 1) {}
    return s[start..end];
}

fn findVariable(name: []const u8) ?*Variable {
    var i: usize = 0;
    while (i < var_count) : (i += 1) {
        if (common.streq(variables[i].name[0..variables[i].name_len], name)) {
            return &variables[i];
        }
    }
    return null;
}

fn setVariable(name: []const u8, val: []const u8) void {
    if (findVariable(name)) |v| {
        // Update
        const copy_len = if (val.len > MAX_VAL_LEN) MAX_VAL_LEN else val.len;
        common.copy(v.value[0..], val[0..copy_len]);
        v.val_len = copy_len;
    } else {
        // Create new
        if (var_count < MAX_VARS) {
            var v = &variables[var_count];
            
            const name_copy_len = if (name.len > MAX_VAR_NAME) MAX_VAR_NAME else name.len;
            common.copy(v.name[0..], name[0..name_copy_len]);
            v.name_len = name_copy_len;
            
            const val_copy_len = if (val.len > MAX_VAL_LEN) MAX_VAL_LEN else val.len;
            common.copy(v.value[0..], val[0..val_copy_len]);
            v.val_len = val_copy_len;
            
            var_count += 1;
        } else {
            common.printZ("Error: Too many variables\n");
        }
    }
}

// Get value of a single term (literal or variable)
fn getValue(raw_term: []const u8) []const u8 {
    const term = trim(raw_term);
    if (term.len == 0) return "";
    
    // Literal
    if (term[0] == '"') {
        var end = term.len;
        if (term.len > 1 and term[term.len - 1] == '"') {
             end = term.len - 1;
        }
        // remove first quote
        if (end > 1) {
            return term[1..end];
        }
        return "";
    }
    
    // Variable
    if (findVariable(term)) |v| {
        return v.value[0..v.val_len];
    }
    
    // If number/unknown and not variable, return empty or error? 
    // For now return empty if not found
    return "";
}

fn evaluateExpression(expr_in: []const u8) []const u8 {
    var current_len: usize = 0;
    var pos: usize = 0;
    var start: usize = 0;
    
    // Simple split by '+'
    while (pos <= expr_in.len) {
        if (pos == expr_in.len or expr_in[pos] == '+') {
            const part = expr_in[start..pos];
            const val = getValue(part);
            
            // Append
            if (current_len + val.len <= eval_buffer.len) {
                common.copy(eval_buffer[current_len..], val);
                current_len += val.len;
            }
            
            start = pos + 1;
        }
        pos += 1;
    }
    
    return eval_buffer[0..current_len];
}

// --- commands ---

fn execSetString(buffer: []const u8, stmt: parser.Statement) void {
    const arg = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    
    if (common.indexOf(arg, '=')) |eq_pos| {
        const name = trim(arg[0..eq_pos]);
        const expr = arg[eq_pos + 1 ..];
        
        const val = evaluateExpression(expr);
        setVariable(name, val);
    } else {
        common.printZ("Error: Missing '='\n");
    }
}

fn execPrint(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const val = evaluateExpression(expr);
    
    for (val) |c| {
        common.print_char(c);
    }
    common.print_char('\n');
}

// Execute a parsed statement
pub fn execute(buffer: []const u8, stmt: parser.Statement, exit_flag: *bool) void {
    switch (stmt.cmd_type) {
        .set_string => execSetString(buffer, stmt),
        .print => execPrint(buffer, stmt),
        .exit => exit_flag.* = true,
        .unknown => common.printZ("Syntax Error\n"),
        .empty => {},
    }
}
