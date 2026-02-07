const lexer = @import("nova/lexer.zig");
const util = @import("nova/util.zig");
const common = @import("nova/common.zig");
const global_common = @import("commands/common.zig");
const memory = @import("memory.zig");
const fat = @import("drivers/fat.zig");
const ata = @import("drivers/ata.zig");
const keyboard = @import("keyboard_isr.zig");
const interpreter = @import("nova/interpreter.zig");
const shell = @import("shell.zig");

pub const ValueType = enum {
    int,
    string,
    none,
};

pub const Value = struct {
    vtype: ValueType,
    int_val: i32 = 0,
    str_val: []const u8 = "",
    is_allocated: bool = false,

    pub fn isTrue(self: Value) bool {
        return switch (self.vtype) {
            .int => self.int_val != 0,
            .string => self.str_val.len > 0,
            .none => false,
        };
    }

    pub fn deinit(self: *Value) void {
        if (self.vtype == .string and self.is_allocated and self.str_val.len > 0) {
            memory.heap.free(@ptrCast(@constCast(self.str_val.ptr)));
            self.is_allocated = false;
            self.str_val = "";
        }
    }
};

pub const Function = struct {
    name: []const u8,
    token_start: usize, // IP of the first token inside { }
    arg_names: [][]const u8,
    tokens: []lexer.Token,
};

pub const MAX_SCRIPT_ARGS = 8;
pub const MAX_ARG_LEN = 64;
pub var script_args: [MAX_SCRIPT_ARGS][MAX_ARG_LEN]u8 = [_][MAX_ARG_LEN]u8{[_]u8{0} ** MAX_ARG_LEN} ** MAX_SCRIPT_ARGS;
pub var script_args_len: [MAX_SCRIPT_ARGS]usize = [_]usize{0} ** MAX_SCRIPT_ARGS;
pub var script_argc: usize = 0;

pub fn setScriptArgs(args: []const []const u8) void {
    script_argc = @min(args.len, MAX_SCRIPT_ARGS);
    for (0..script_argc) |i| {
        const len = @min(args[i].len, MAX_ARG_LEN);
        for (0..len) |j| script_args[i][j] = args[i][j];
        script_args_len[i] = len;
    }
}

pub fn clearScriptArgs() void {
    script_argc = 0;
    for (0..MAX_SCRIPT_ARGS) |i| {
        script_args_len[i] = 0;
    }
}

pub const VM = struct {
    tokens: []lexer.Token,
    ip: usize,
    globals: util.HashTable(Value),
    functions: util.HashTable(Function),
    module_cache: util.HashTable(bool),
    exit_flag: bool,

    // Resource tracking
    allocated_sources: util.ArrayList([]const u8),
    allocated_tokens: util.ArrayList([]lexer.Token),

    // Circular string buffers for intermediate results
    str_pool: [8][512]u8 = [_][512]u8{[_]u8{0} ** 512} ** 8,
    str_pool_idx: usize = 0,

    pub fn init() VM {
        return .{
            .tokens = &[_]lexer.Token{},
            .ip = 0,
            .globals = util.HashTable(Value).init(),
            .functions = util.HashTable(Function).init(),
            .module_cache = util.HashTable(bool).init(),
            .exit_flag = false,
            .allocated_sources = util.ArrayList([]const u8).init(),
            .allocated_tokens = util.ArrayList([]lexer.Token).init(),
        };
    }

    pub fn deinit(self: *VM) void {
        // Deinit globals (especially allocated strings)
        for (self.globals.entries) |*entry| {
            if (entry.used) {
                entry.value.deinit();
            }
        }
        self.globals.deinit();

        // Deinit functions
        for (self.functions.entries) |entry| {
            if (entry.used) {
                memory.heap.free(@ptrCast(entry.value.arg_names.ptr));
            }
        }
        self.functions.deinit();

        // Free module cache keys if they were allocated
        for (self.module_cache.entries) |entry| {
            if (entry.used) {
                memory.heap.free(@ptrCast(@constCast(entry.key.ptr)));
            }
        }
        self.module_cache.deinit();

        // Free all scripts and tokens
        for (self.allocated_sources.items[0..self.allocated_sources.len]) |src| {
            memory.heap.free(@ptrCast(@constCast(src.ptr)));
        }
        self.allocated_sources.deinit();

        for (self.allocated_tokens.items[0..self.allocated_tokens.len]) |toks| {
            memory.heap.free(@ptrCast(toks.ptr));
        }
        self.allocated_tokens.deinit();
    }

    fn getNextStrBuf(self: *VM) []u8 {
        const buf = &self.str_pool[self.str_pool_idx];
        self.str_pool_idx = (self.str_pool_idx + 1) % 8;
        return buf[0..];
    }

    pub fn run(self: *VM, tokens: []lexer.Token) !void {
        self.tokens = tokens;
        self.ip = 0;
        try self.executeBlock(null);
    }

    fn executeBlock(self: *VM, locals: ?*util.HashTable(Value)) anyerror!void {
        while (self.ip < self.tokens.len and !self.exit_flag) {
            const token = self.tokens[self.ip];
            if (token.ttype == .EOF) break;
            if (token.ttype == .R_BRACE) {
                self.ip += 1;
                break;
            }
            try self.executeStatement(locals);
        }
    }

    fn executeStatement(self: *VM, locals: ?*util.HashTable(Value)) anyerror!void {
        const token = self.tokens[self.ip];
        switch (token.ttype) {
            .PRINT => {
                self.ip += 1;
                if (self.match(.L_PAREN)) {
                    const val = try self.evaluateExpression(locals);
                    if (self.match(.R_PAREN)) {
                        if (val.vtype == .string) {
                            common.printZ(val.str_val);
                        } else {
                            var buf: [32]u8 = undefined;
                            common.printZ(common.intToString(val.int_val, &buf));
                        }
                        common.printZ("\n");
                    }
                }
                _ = self.match(.SEMICOLON);
            },
            .SET => {
                self.ip += 1;
                if (self.tokens[self.ip].ttype == .INT_KW or self.tokens[self.ip].ttype == .STRING_KW) self.ip += 1;
                if (self.tokens[self.ip].ttype == .IDENTIFIER) {
                    const name = self.tokens[self.ip].value;
                    self.ip += 1;
                    if (self.match(.EQUALS)) {
                        const val = try self.evaluateExpression(locals);
                        self.setVar(locals, name, val);
                    }
                }
                _ = self.match(.SEMICOLON);
            },
            .IF => {
                self.ip += 1;
                const cond = try self.evaluateExpression(locals);
                if (!self.match(.L_BRACE)) { self.exit_flag = true; return; }
                const block_start = self.ip;
                const block_end = self.findMatchingBrace(block_start);
                if (cond.isTrue()) {
                    try self.executeBlock(locals);
                    self.ip = block_end + 1;
                    if (self.match(.ELSE)) {
                        if (self.match(.L_BRACE)) self.ip = self.findMatchingBrace(self.ip) + 1;
                    }
                } else {
                    self.ip = block_end + 1;
                    if (self.match(.ELSE)) {
                        if (self.match(.L_BRACE)) try self.executeBlock(locals);
                    }
                }
            },
            .WHILE => {
                self.ip += 1;
                const cond_ip = self.ip;
                while (!self.exit_flag) {
                    self.ip = cond_ip;
                    const cond = try self.evaluateExpression(locals);
                    if (!self.match(.L_BRACE)) { self.exit_flag = true; return; }
                    const block_start = self.ip;
                    const block_end = self.findMatchingBrace(block_start);
                    if (cond.isTrue()) try self.executeBlock(locals)
                    else { self.ip = block_end + 1; break; }
                }
            },
            .DEF => try self.handleDef(),
            .IMPORT => try self.handleImport(locals),
            .SLEEP => {
                self.ip += 1;
                if (self.match(.L_PAREN)) {
                    const val = try self.evaluateExpression(locals);
                    if (val.vtype == .int and val.int_val > 0) global_common.sleep(@intCast(val.int_val));
                    _ = self.match(.R_PAREN);
                }
                _ = self.match(.SEMICOLON);
            },
            .EXIT => { self.exit_flag = true; self.ip += 1; if (self.match(.L_PAREN)) _ = self.match(.R_PAREN); _ = self.match(.SEMICOLON); },
            .REBOOT => common.reboot(),
            .SHUTDOWN => common.shutdown(),
            .SHELL => {
                self.ip += 1;
                if (self.match(.L_PAREN)) {
                    const val = try self.evaluateExpression(locals);
                    if (val.vtype == .string) shell.shell_execute_literal(val.str_val);
                    _ = self.match(.R_PAREN);
                }
                _ = self.match(.SEMICOLON);
            },
            .IDENTIFIER => {
                const name = token.value;
                self.ip += 1;
                if (self.match(.EQUALS)) {
                    const val = try self.evaluateExpression(locals);
                    self.setVar(locals, name, val);
                    _ = self.match(.SEMICOLON);
                } else if (self.match(.L_PAREN)) {
                    _ = try self.handleCall(name, locals);
                    _ = self.match(.SEMICOLON);
                } else _ = self.match(.SEMICOLON);
            },
            else => self.ip += 1,
        }
    }

    fn match(self: *VM, ttype: lexer.TokenType) bool {
        if (self.ip < self.tokens.len and self.tokens[self.ip].ttype == ttype) {
            self.ip += 1;
            return true;
        }
        return false;
    }

    fn findMatchingBrace(self: *VM, start_ip: usize) usize {
        var depth: i32 = 1;
        var i = start_ip;
        while (i < self.tokens.len) : (i += 1) {
            if (self.tokens[i].ttype == .L_BRACE) depth += 1;
            if (self.tokens[i].ttype == .R_BRACE) {
                depth -= 1;
                if (depth == 0) return i;
            }
        }
        return i;
    }

    fn setVar(self: *VM, locals: ?*util.HashTable(Value), name: []const u8, val: Value) void {
        var final_val = val;
        if (val.vtype == .string) {
            // Persistent copy
            const ptr = memory.heap.alloc(val.str_val.len) orelse return;
            const slice = @as([*]u8, @ptrCast(ptr))[0..val.str_val.len];
            for (val.str_val, 0..) |c, i| slice[i] = c;
            final_val.str_val = slice;
            final_val.is_allocated = true;
        }

        const target = if (locals) |l| l else &self.globals;
        if (target.get(name)) |*old_val| {
            var ov = old_val.*;
            ov.deinit();
        }
        _ = target.put(name, final_val);
    }

    fn getVar(self: VM, locals: ?*util.HashTable(Value), name: []const u8) Value {
        if (locals) |l| { if (l.get(name)) |v| return v; }
        if (self.globals.get(name)) |v| return v;
        return .{ .vtype = .none };
    }

    fn evaluateExpression(self: *VM, locals: ?*util.HashTable(Value)) anyerror!Value {
        var res = try self.evaluateTerm(locals);
        while (self.ip < self.tokens.len) {
            const op = self.tokens[self.ip].ttype;
            if (op != .PLUS and op != .MINUS and op != .STAR and op != .SLASH and
                op != .EQUALS_EQUALS and op != .BANG_EQUALS and op != .LESS and op != .GREATER) break;
            self.ip += 1;
            const right = try self.evaluateTerm(locals);
            if (res.vtype == .int and right.vtype == .int) {
                res.int_val = switch (op) {
                    .PLUS => res.int_val + right.int_val,
                    .MINUS => res.int_val - right.int_val,
                    .STAR => res.int_val * right.int_val,
                    .SLASH => if (right.int_val != 0) @divTrunc(res.int_val, right.int_val) else 0,
                    .EQUALS_EQUALS => if (res.int_val == right.int_val) @as(i32, 1) else 0,
                    .BANG_EQUALS => if (res.int_val != right.int_val) @as(i32, 1) else 0,
                    .LESS => if (res.int_val < right.int_val) @as(i32, 1) else 0,
                    .GREATER => if (res.int_val > right.int_val) @as(i32, 1) else 0,
                    else => res.int_val,
                };
            } else if (res.vtype == .string or right.vtype == .string) {
                if (op == .PLUS) {
                    var b1: [32]u8 = undefined;
                    const s1 = if (res.vtype == .string) res.str_val else common.intToString(res.int_val, &b1);
                    var b2: [32]u8 = undefined;
                    const s2 = if (right.vtype == .string) right.str_val else common.intToString(right.int_val, &b2);
                    const out = self.getNextStrBuf();
                    var len: usize = 0;
                    for (s1) |c| { if (len < 511) { out[len] = c; len += 1; } }
                    for (s2) |c| { if (len < 511) { out[len] = c; len += 1; } }
                    res = .{ .vtype = .string, .str_val = out[0..len], .is_allocated = false };
                } else if (op == .EQUALS_EQUALS) {
                    if (res.vtype == .string and right.vtype == .string) res = .{ .vtype = .int, .int_val = if (common.streq(res.str_val, right.str_val)) @as(i32, 1) else 0 }
                    else res = .{ .vtype = .int, .int_val = 0 };
                }
            }
        }
        return res;
    }

    fn evaluateTerm(self: *VM, locals: ?*util.HashTable(Value)) anyerror!Value {
        if (self.ip >= self.tokens.len) return .{ .vtype = .none };
        const token = self.tokens[self.ip];
        self.ip += 1;
        switch (token.ttype) {
            .NUMBER => return .{ .vtype = .int, .int_val = common.parseInt(token.value) },
            .STRING => return .{ .vtype = .string, .str_val = if (token.value.len >= 2) token.value[1 .. token.value.len - 1] else token.value },
            .IDENTIFIER => {
                if (self.match(.L_PAREN)) return try self.handleCall(token.value, locals);
                return self.getVar(locals, token.value);
            },
            .L_PAREN => { const v = try self.evaluateExpression(locals); _ = self.match(.R_PAREN); return v; },
            else => return .{ .vtype = .none },
        }
    }

    fn handleCall(self: *VM, name: []const u8, locals: ?*util.HashTable(Value)) anyerror!Value {
        if (common.streq(name, "random")) {
            const min_v = try self.evaluateExpression(locals); _ = self.match(.COMMA);
            const max_v = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            return .{ .vtype = .int, .int_val = global_common.get_random(min_v.int_val, max_v.int_val) };
        }
        if (common.streq(name, "input")) {
            const prompt = try self.evaluateExpression(locals);
            if (prompt.vtype == .string) common.printZ(prompt.str_val)
            else { var b: [32]u8 = undefined; common.printZ(common.intToString(prompt.int_val, &b)); }
            var ib: [64]u8 = undefined; const len = interpreter.readInput(&ib); _ = self.match(.R_PAREN);
            const out = self.getNextStrBuf(); for (ib[0..len], 0..) |c, i| out[i] = c;
            return .{ .vtype = .string, .str_val = out[0..len], .is_allocated = false };
        }
        if (common.streq(name, "read")) {
            const path_v = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            if (path_v.vtype != .string) return .{ .vtype = .none };
            const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
            if (fat.read_bpb(drive)) |bpb| {
                const out = self.getNextStrBuf();
                const rl = fat.read_file(drive, bpb, global_common.current_dir_cluster, path_v.str_val, out);
                if (rl >= 0) return .{ .vtype = .string, .str_val = out[0..@intCast(rl)], .is_allocated = false };
            }
            return .{ .vtype = .string, .str_val = "" };
        }
        if (common.streq(name, "delete")) {
            const p = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            if (p.vtype != .string) return .{ .vtype = .none };
            const d = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
            if (fat.read_bpb(d)) |bpb| {
                if (!fat.delete_file(d, bpb, global_common.current_dir_cluster, p.str_val))
                    _ = fat.delete_directory(d, bpb, global_common.current_dir_cluster, p.str_val, true);
            }
            return .{ .vtype = .none };
        }
        if (common.streq(name, "rename")) {
            const old = try self.evaluateExpression(locals); _ = self.match(.COMMA);
            const new = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            if (old.vtype == .string and new.vtype == .string) {
                const d = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(d)) |bpb| _ = fat.rename_file(d, bpb, global_common.current_dir_cluster, old.str_val, new.str_val);
            }
            return .{ .vtype = .none };
        }
        if (common.streq(name, "copy")) {
            const src = try self.evaluateExpression(locals); _ = self.match(.COMMA);
            const dst = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            if (src.vtype == .string and dst.vtype == .string) {
                const d = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(d)) |bpb| {
                    if (fat.find_entry(d, bpb, global_common.current_dir_cluster, src.str_val)) |ent| {
                        if ((ent.attr & 0x10) != 0) _ = fat.copy_directory(d, bpb, global_common.current_dir_cluster, src.str_val, dst.str_val)
                        else _ = fat.copy_file(d, bpb, global_common.current_dir_cluster, src.str_val, dst.str_val);
                    }
                }
            }
            return .{ .vtype = .none };
        }
        if (common.streq(name, "mkdir")) {
            const p = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            if (p.vtype == .string) {
                const d = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(d)) |bpb| _ = fat.create_directory(d, bpb, global_common.current_dir_cluster, p.str_val);
            }
            return .{ .vtype = .none };
        }
        if (common.streq(name, "write_file")) {
            const p = try self.evaluateExpression(locals); _ = self.match(.COMMA);
            const data = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            if (p.vtype == .string and data.vtype == .string) {
                const d = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(d)) |bpb| _ = fat.write_file(d, bpb, global_common.current_dir_cluster, p.str_val, data.str_val);
            }
            return .{ .vtype = .none };
        }
        if (common.streq(name, "create_file")) {
            const p = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            if (p.vtype == .string) {
                const d = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(d)) |bpb| _ = fat.write_file(d, bpb, global_common.current_dir_cluster, p.str_val, "");
            }
            return .{ .vtype = .none };
        }
        if (common.streq(name, "abs")) { const v = try self.evaluateExpression(locals); _ = self.match(.R_PAREN); return .{ .vtype = .int, .int_val = global_common.math_abs(v.int_val) }; }
        if (common.streq(name, "min")) {
            const a = try self.evaluateExpression(locals); _ = self.match(.COMMA);
            const b = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            return .{ .vtype = .int, .int_val = global_common.math_min(a.int_val, b.int_val) };
        }
        if (common.streq(name, "max")) {
            const a = try self.evaluateExpression(locals); _ = self.match(.COMMA);
            const b = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            return .{ .vtype = .int, .int_val = global_common.math_max(a.int_val, b.int_val) };
        }
        if (common.streq(name, "sin")) {
            const v = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            return .{ .vtype = .int, .int_val = approx_sin(v.int_val) };
        }
        if (common.streq(name, "cos")) {
            const v = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            return .{ .vtype = .int, .int_val = approx_sin(v.int_val + 90) };
        }
        if (common.streq(name, "tan") or common.streq(name, "tg")) {
            const v = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            const s = approx_sin(v.int_val); const c = approx_sin(v.int_val + 90);
            return .{ .vtype = .int, .int_val = if (c == 0) 9999 else @divTrunc(s * 100, c) };
        }
        if (common.streq(name, "ctg")) {
            const v = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            const s = approx_sin(v.int_val); const c = approx_sin(v.int_val + 90);
            return .{ .vtype = .int, .int_val = if (s == 0) 9999 else @divTrunc(c * 100, s) };
        }
        if (common.streq(name, "argc")) { _ = self.match(.R_PAREN); return .{ .vtype = .int, .int_val = @intCast(script_argc) }; }
        if (common.streq(name, "args")) {
            const i_v = try self.evaluateExpression(locals); _ = self.match(.R_PAREN);
            if (i_v.vtype == .int and i_v.int_val >= 0 and i_v.int_val < script_argc) {
                const arg = script_args[@intCast(i_v.int_val)][0..script_args_len[@intCast(i_v.int_val)]];
                const out = self.getNextStrBuf(); for (arg, 0..) |c, i| out[i] = c;
                return .{ .vtype = .string, .str_val = out[0..arg.len], .is_allocated = false };
            }
            return .{ .vtype = .string, .str_val = "" };
        }
        if (self.functions.get(name)) |func| {
            var nl = util.HashTable(Value).init(); defer {
                for (nl.entries) |*e| { if (e.used) e.value.deinit(); }
                nl.deinit();
            }
            for (func.arg_names) |an| { const av = try self.evaluateExpression(locals); self.setVar(&nl, an, av); _ = self.match(.COMMA); }
            _ = self.match(.R_PAREN);
            const st = self.tokens; const si = self.ip; self.tokens = func.tokens; self.ip = func.token_start;
            try self.executeBlock(&nl); self.tokens = st; self.ip = si;
            return .{ .vtype = .none };
        }
        while (self.ip < self.tokens.len and self.tokens[self.ip].ttype != .R_PAREN) : (self.ip += 1) {}
        _ = self.match(.R_PAREN); return .{ .vtype = .none };
    }

    fn handleDef(self: *VM) anyerror!void {
        self.ip += 1; if (self.tokens[self.ip].ttype != .IDENTIFIER) return;
        const name = self.tokens[self.ip].value; self.ip += 1;
        if (!self.match(.L_PAREN)) return;
        var anl = util.ArrayList([]const u8).init(); defer anl.deinit();
        while (self.ip < self.tokens.len and self.tokens[self.ip].ttype == .IDENTIFIER) {
            _ = anl.append(self.tokens[self.ip].value); self.ip += 1; _ = self.match(.COMMA);
        }
        _ = self.match(.R_PAREN); if (!self.match(.L_BRACE)) return;
        const ts = self.ip; const be = self.findMatchingBrace(ts); self.ip = be + 1;
        const pap = memory.heap.alloc(anl.len * @sizeOf([]const u8)) orelse return;
        const as = @as([*][]const u8, @ptrCast(pap))[0..anl.len];
        for (anl.items[0..anl.len], 0..) |arg, i| as[i] = arg;
        _ = self.functions.put(name, .{ .name = name, .token_start = ts, .arg_names = as, .tokens = self.tokens });
    }

    fn handleImport(self: *VM, locals: ?*util.HashTable(Value)) anyerror!void {
        self.ip += 1; const pv = try self.evaluateExpression(locals); if (pv.vtype != .string) return;
        var fpb: [128]u8 = [_]u8{0} ** 128; var fpl: usize = 0;
        if (common.startsWith(pv.str_val, "./")) { for (pv.str_val[2..]) |c| { if (fpl < 127) { fpb[fpl] = c; fpl += 1; } } }
        else if (pv.str_val[0] == '/') { for (pv.str_val) |c| { if (fpl < 127) { fpb[fpl] = c; fpl += 1; } } }
        else {
            const pre = "/sys/nova/"; for (pre) |c| { if (fpl < 127) { fpb[fpl] = c; fpl += 1; } }
            for (pv.str_val) |c| { if (fpl < 127) { fpb[fpl] = c; fpl += 1; } }
        }
        if (!common.endsWith(fpb[0..fpl], ".nv")) { const ext = ".nv"; for (ext) |c| { if (fpl < 127) { fpb[fpl] = c; fpl += 1; } } }
        const fp = fpb[0..fpl]; if (self.module_cache.contains(fp)) return;
        const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            if (fat.find_entry(drive, bpb, global_common.current_dir_cluster, fp)) |ent| {
                const s = ent.file_size; const sp = memory.heap.alloc(s) orelse return;
                const ss = @as([*]u8, @ptrCast(sp))[0..s];
                const br = fat.read_file(drive, bpb, global_common.current_dir_cluster, fp, ss);
                if (br > 0) {
                     const ppp = memory.heap.alloc(fpl) orelse return;
                     const pp = @as([*]u8, @ptrCast(ppp))[0..fpl]; for (fp, 0..) |c, i| pp[i] = c;
                     _ = self.module_cache.put(pp, true); _ = self.allocated_sources.append(ss);
                     var sl = lexer.Lexer.init(ss); var tl = try sl.tokenize();
                     const ts = tl.items[0..tl.len]; _ = self.allocated_tokens.append(ts);
                     const st = self.tokens; const si = self.ip; self.tokens = ts; self.ip = 0;
                     try self.executeBlock(locals); self.tokens = st; self.ip = si;
                }
            }
        }
        _ = self.match(.SEMICOLON);
    }
};

fn approx_sin(deg: i32) i32 {
    var x = @mod(deg, 360); if (x < 0) x += 360;
    var sign: i32 = 1; if (x > 180) { x -= 180; sign = -1; }
    const x_180_x = x * (180 - x); const num = 4 * x_180_x; const den = 40500 - x_180_x;
    if (den == 0) return 0; return @intCast(sign * @divTrunc(num * 100, den));
}
