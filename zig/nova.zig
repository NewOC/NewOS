// Nova Language - Main export module
const interpreter = @import("nova/interpreter.zig");

// Export nova_start for ASM
pub export fn nova_start() void {
    interpreter.start();
}
