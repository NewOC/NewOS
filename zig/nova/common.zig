// Nova Language - Common utilities
const common = @import("../commands/common.zig");

pub const print_char = common.print_char;
pub const printZ = common.printZ;
pub const printNum = common.printNum;

// String utilities
pub fn streq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}

pub fn startsWith(str: []const u8, prefix: []const u8) bool {
    if (str.len < prefix.len) return false;
    for (0..prefix.len) |i| {
        if (str[i] != prefix[i]) return false;
    }
    return true;
}
