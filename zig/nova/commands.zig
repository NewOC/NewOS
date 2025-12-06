// Nova Language - Commands execution
const common = @import("common.zig");
const parser = @import("parser.zig");

// --- Variable Storage ---
const MAX_VARS = 16;
const MAX_VAR_NAME = 16;
const MAX_VAL_LEN = 64;

const VarType = enum {
    string,
    int,
};

const Variable = struct {
    name: [MAX_VAR_NAME]u8,
    name_len: usize,
    value: [MAX_VAL_LEN]u8, // String storage
    val_len: usize,
    int_val: i32,           // Int storage
    vtype: VarType,
};

var variables: [MAX_VARS]Variable = undefined;
var var_count: usize = 0;

var eval_buffer: [256]u8 = undefined;
var int_conv_buf: [32]u8 = undefined;

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

fn setVariable(name: []const u8, val: []const u8, vtype: VarType, int_val: i32) void {
    if (findVariable(name)) |v| {
        // Update
        if (vtype == .string) {
            const copy_len = if (val.len > MAX_VAL_LEN) MAX_VAL_LEN else val.len;
            common.copy(v.value[0..], val[0..copy_len]);
            v.val_len = copy_len;
        } else {
            v.int_val = int_val;
        }
        v.vtype = vtype;
    } else {
        // Create new
        if (var_count < MAX_VARS) {
            var v = &variables[var_count];
            
            const name_copy_len = if (name.len > MAX_VAR_NAME) MAX_VAR_NAME else name.len;
            common.copy(v.name[0..], name[0..name_copy_len]);
            v.name_len = name_copy_len;
            
            if (vtype == .string) {
                const val_copy_len = if (val.len > MAX_VAL_LEN) MAX_VAL_LEN else val.len;
                common.copy(v.value[0..], val[0..val_copy_len]);
                v.val_len = val_copy_len;
            } else {
                v.int_val = int_val;
            }
            v.vtype = vtype;
            
            var_count += 1;
        } else {
            common.printZ("Error: Too many variables\n");
        }
    }
}

// Result of an evaluation
const EvalResult = struct {
    str_val: []const u8,
    int_val: i32,
    etype: VarType,
};

// Get value of a single term (literal or variable)
fn getValue(raw_term: []const u8) EvalResult {
    const term = trim(raw_term);
    if (term.len == 0) return .{ .str_val = "", .int_val = 0, .etype = .string };
    
    // Literal String
    if (term[0] == '"') {
        var end = term.len;
        if (term.len > 1 and term[term.len - 1] == '"') {
             end = term.len - 1;
        }
        if (end > 1) {
            return .{ .str_val = term[1..end], .int_val = 0, .etype = .string };
        }
        return .{ .str_val = "", .int_val = 0, .etype = .string };
    }
    
    // Variable
    if (findVariable(term)) |v| {
        if (v.vtype == .string) {
            return .{ .str_val = v.value[0..v.val_len], .int_val = 0, .etype = .string };
        } else {
            return .{ .str_val = "", .int_val = v.int_val, .etype = .int };
        }
    }
    
    // Literal Int
    // Assume if it starts with digit or -, and parses, it's int
    if ((term[0] >= '0' and term[0] <= '9') or term[0] == '-') {
        return .{ .str_val = "", .int_val = common.parseInt(term), .etype = .int };
    }
    
    return .{ .str_val = "", .int_val = 0, .etype = .string };
}

// Basic Left-to-Right Evaluator with limited precedence for simplicity
// Supports + - * /
// WARNING: No complex precedence supported yet (e.g. 1 + 2 * 3 will be evaluated as (1+2)*3)
// For a simple toy OS language this might be acceptable unless full math parser is needed.
// To support full precedence, we need a better parser. Given constraints, let's try a simple L-R split.


fn evaluateTerm(raw_term: []const u8) EvalResult {
    const term = trim(raw_term);
    if (term.len == 0) return .{ .str_val = "", .int_val = 0, .etype = .int };
    
    // Check for parens
    if (term.len >= 2 and term[0] == '(' and term[term.len - 1] == ')') {
        // We assume valid nesting from the splitter, but let's be safe later if needed.
        // For now, strip and recurse.
        return evaluateExpression(term[1..term.len-1]);
    }
    
    return getValue(term);
}

fn evaluateExpression(expr_in: []const u8) EvalResult {
    var pos: usize = 0;
    var last_op: u8 = 0;
    var start: usize = 0;
    var depth: i32 = 0;
    
    var accum_int: i32 = 0;
    var accum_str_len: usize = 0;
    var current_type: VarType = .int;
    
    while (pos <= expr_in.len) {
        var is_op = false;
        var c: u8 = 0;
        
        if (pos < expr_in.len) {
            c = expr_in[pos];
            if (c == '(') {
                depth += 1;
            } else if (c == ')') {
                depth -= 1;
            } else if (depth == 0) {
                if (c == '+' or c == '-' or c == '*' or c == '/') {
                    is_op = true;
                }
            }
        }
        
        if (depth == 0 and (pos == expr_in.len or is_op)) {
            const part = expr_in[start..pos];
            const val = evaluateTerm(part);
             
            if (last_op == 0) {
                current_type = val.etype;
                if (current_type == .int) {
                    accum_int = val.int_val;
                } else {
                    common.copy(eval_buffer[0..], val.str_val);
                    accum_str_len = val.str_val.len;
                }
            } else {
                if (current_type == .int and val.etype == .int) {
                    if (last_op == '+') accum_int += val.int_val;
                    if (last_op == '-') accum_int -= val.int_val;
                    if (last_op == '*') accum_int *= val.int_val;
                    if (last_op == '/') {
                        if (val.int_val != 0) accum_int = @divTrunc(accum_int, val.int_val) else accum_int = 0;
                    }
                } else if (current_type == .string and val.etype == .string) {
                    if (last_op == '+') {
                         if (accum_str_len + val.str_val.len < 256) {
                             common.copy(eval_buffer[accum_str_len..], val.str_val);
                             accum_str_len += val.str_val.len;
                         }
                    } else {
                        common.printZ("Error: Invalid op for strings\n");
                    }
                } else {
                     common.printZ("Error: Type mismatch\n");
                }
            }
            
            if (pos < expr_in.len) {
                last_op = c;
                start = pos + 1;
            }
        }
        pos += 1;
    }
    
    if (current_type == .int) {
        return .{ .str_val = "", .int_val = accum_int, .etype = .int };
    } else {
        return .{ .str_val = eval_buffer[0..accum_str_len], .int_val = 0, .etype = .string };
    }
}

// --- commands ---

fn execSetString(buffer: []const u8, stmt: parser.Statement) void {
    const arg = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    if (common.indexOf(arg, '=')) |eq_pos| {
        const name = trim(arg[0..eq_pos]);
        const expr = arg[eq_pos + 1 ..];
        const res = evaluateExpression(expr);
        // Force string
        if (res.etype == .string) {
             setVariable(name, res.str_val, .string, 0);
        } else {
            // Convert int to string if assigning to string? Or error?
            // "set string ... = 10" -> usually error or auto-cast.
            // Let's auto-cast for friendliness
             const s = common.intToString(res.int_val, &int_conv_buf);
             setVariable(name, s, .string, 0);
        }
    }
}

fn execSetInt(buffer: []const u8, stmt: parser.Statement) void {
    const arg = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    if (common.indexOf(arg, '=')) |eq_pos| {
        const name = trim(arg[0..eq_pos]);
        const expr = arg[eq_pos + 1 ..];
        const res = evaluateExpression(expr);
        if (res.etype == .int) {
             setVariable(name, "", .int, res.int_val);
        } else {
             common.printZ("Error: Expected int\n");
        }
    }
}

fn execPrint(buffer: []const u8, stmt: parser.Statement) void {
    const expr = buffer[stmt.arg_start .. stmt.arg_start + stmt.arg_len];
    const res = evaluateExpression(expr);
    
    if (res.etype == .string) {
        for (res.str_val) |c| {
            common.print_char(c);
        }
    } else {
        const s = common.intToString(res.int_val, &int_conv_buf);
        for (s) |c| {
            common.print_char(c);
        }
    }
    common.print_char('\n');
}

// Execute a parsed statement
pub fn execute(buffer: []const u8, stmt: parser.Statement, exit_flag: *bool) void {
    switch (stmt.cmd_type) {
        .set_string => execSetString(buffer, stmt),
        .set_int => execSetInt(buffer, stmt),
        .print => execPrint(buffer, stmt),
        .reboot => common.reboot(),
        .shutdown => common.shutdown(),
        .exit => exit_flag.* = true,
        .unknown => common.printZ("Syntax Error\n"),
        .empty => {},
    }
}
