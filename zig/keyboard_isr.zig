// Keyboard interrupt handler for NewOS
const std = @import("std");

// Keyboard buffer
const BUFFER_SIZE = 256;
var keyboard_buffer: [BUFFER_SIZE]u8 = undefined;
var buffer_head: usize = 0;
var buffer_tail: usize = 0;

// Extended keys constants (matches kernel32.asm)
pub const KEY_UP = 0x80;
pub const KEY_DOWN = 0x81;
pub const KEY_LEFT = 0x82;
pub const KEY_RIGHT = 0x83;

// Scancode tables
const scancode = [_]u8{
    0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 8,
    0, 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 10,
    0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`',
    0, '\\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0,
    0, 0, ' ',
} ++ [_]u8{0} ** (128 - 57);

const scancode_shift = [_]u8{
    0, 0, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 8,
    0, 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 10,
    0, 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~',
    0, '|', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0,
    0, 0, ' ',
} ++ [_]u8{0} ** (128 - 57);

// Shift state
var shift_pressed: bool = false;
var extended_key: bool = false;

// I/O port functions
fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

// Keyboard interrupt handler (called from ASM wrapper)
pub export fn isr_keyboard() void {
    const scancode_byte = inb(0x60);
    
    // Handle extended keys prefix
    if (scancode_byte == 0xE0) {
        extended_key = true;
        return;
    }

    // Handle shift keys
    if (scancode_byte == 0x2A or scancode_byte == 0x36) {
        shift_pressed = true;
        return;
    }
    if (scancode_byte == 0xAA or scancode_byte == 0xB6) {
        shift_pressed = false;
        return;
    }
    
    // Ignore key releases (high bit set)
    if ((scancode_byte & 0x80) != 0) {
        extended_key = false; // Reset extended key on release too
        return;
    }
    
    var ascii: u8 = 0;

    if (extended_key) {
        extended_key = false;
        ascii = switch (scancode_byte) {
            0x48 => KEY_UP,
            0x50 => KEY_DOWN,
            0x4B => KEY_LEFT,
            0x4D => KEY_RIGHT,
            else => 0,
        };
    } else {
        // Convert scancode to ASCII
        ascii = if (shift_pressed)
            scancode_shift[scancode_byte]
        else
            scancode[scancode_byte];
    }
    
    // Add to buffer if valid character
    if (ascii != 0) {
        const next_head = (buffer_head + 1) % BUFFER_SIZE;
        if (next_head != buffer_tail) {
            keyboard_buffer[buffer_head] = ascii;
            buffer_head = next_head;
        }
    }
}

// Get character from buffer (non-blocking)
export fn keyboard_getchar() u8 {
    if (buffer_tail == buffer_head) {
        return 0; // Buffer empty
    }
    
    const ch = keyboard_buffer[buffer_tail];
    buffer_tail = (buffer_tail + 1) % BUFFER_SIZE;
    return ch;
}

fn read_volatile(ptr: *const usize) usize {
    return @as(*volatile const usize, ptr).*;
}

// Check if buffer has data
export fn keyboard_has_data() bool {
    return buffer_tail != read_volatile(&buffer_head);
}

// Wait for character (blocking)
pub export fn keyboard_wait_char() u8 {
    while (!keyboard_has_data()) {
        // Ensure interrupts are enabled and wait
        asm volatile ("sti");
        asm volatile ("hlt");
    }
    return keyboard_getchar();
}
