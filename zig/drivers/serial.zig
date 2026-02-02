// Serial COM1 Driver
const common = @import("../commands/common.zig");

pub const PORT = 0x3F8;

pub export fn serial_print_char(c: u8) void {
    while (!is_transmit_empty()) {}
    outb(PORT, c);
}

fn is_transmit_empty() bool {
    return (inb(PORT + 5) & 0x20) != 0;
}

fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]" 
        : 
        : [val] "{al}" (val), 
          [port] "{dx}" (port)
    );
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]" 
        : [result] "={al}" (-> u8) 
        : [port] "{dx}" (port)
    );
}
