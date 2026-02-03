// Nova Language - Main export module
const interpreter = @import("nova/interpreter.zig");

// Export nova_start for ASM/Shell
pub export fn nova_start(arg_ptr: [*]const u8, arg_len: usize) void {
    if (arg_len == 0) {
        interpreter.start(null);
    } else {
        interpreter.start(arg_ptr[0..arg_len]);
    }
}
