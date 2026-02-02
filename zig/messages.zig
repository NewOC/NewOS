// System Messages Module
// Contains all static text messages used by the kernel and shell

const common = @import("commands/common.zig");

/// Print welcome banner
pub export fn print_welcome() void {
    common.printZ("=== NewOS 32-bit Console ===\r\n");
    common.printZ("Type \"help\" for commands\r\n\r\n");
}
