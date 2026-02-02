// VGA Text Mode Driver - Safe Version
const common = @import("../commands/common.zig");

pub const VIDEO_MEMORY: [*]volatile u16 = @ptrFromInt(0xb8000);
pub const MAX_COLS: usize = 80;
pub const MAX_ROWS: usize = 25;
pub const DEFAULT_ATTR: u16 = 0x0f00;

pub export var cursor_row: u8 = 0;
pub export var cursor_col: u8 = 0;

var screen_buffer: [MAX_COLS * MAX_ROWS]u16 = [_]u16{0} ** (MAX_COLS * MAX_ROWS);
var saved_cursor_row: u8 = 0;
var saved_cursor_col: u8 = 0;

pub export fn save_screen_buffer() void {
    var i: usize = 0;
    while (i < MAX_COLS * MAX_ROWS) : (i += 1) {
        screen_buffer[i] = VIDEO_MEMORY[i];
    }
    saved_cursor_row = cursor_row;
    saved_cursor_col = cursor_col;
}

pub export fn restore_screen_buffer() void {
    var i: usize = 0;
    while (i < MAX_COLS * MAX_ROWS) : (i += 1) {
        VIDEO_MEMORY[i] = screen_buffer[i];
    }
    cursor_row = saved_cursor_row;
    cursor_col = saved_cursor_col;
    update_hardware_cursor();
}

pub export fn clear_screen() void {
    var i: usize = 0;
    while (i < MAX_COLS * MAX_ROWS) : (i += 1) {
        VIDEO_MEMORY[i] = DEFAULT_ATTR | ' ';
    }
    cursor_row = 0;
    cursor_col = 0;
    update_hardware_cursor();
}

pub export fn zig_set_cursor(row: u8, col: u8) void {
    cursor_row = row;
    cursor_col = col;
    update_hardware_cursor();
}

pub export fn zig_get_cursor_row() u8 { return cursor_row; }
pub export fn zig_get_cursor_col() u8 { return cursor_col; }

fn scroll() void {
    var i: usize = 0;
    // Копируем строки 1-24 в 0-23
    while (i < (MAX_ROWS - 1) * MAX_COLS) : (i += 1) {
        VIDEO_MEMORY[i] = VIDEO_MEMORY[i + MAX_COLS];
    }
    // Очищаем последнюю строку
    i = (MAX_ROWS - 1) * MAX_COLS;
    while (i < MAX_ROWS * MAX_COLS) : (i += 1) {
        VIDEO_MEMORY[i] = DEFAULT_ATTR | ' ';
    }
}

fn internal_newline() void {
    cursor_col = 0;
    cursor_row += 1;
    if (cursor_row >= MAX_ROWS) {
        scroll();
        cursor_row = MAX_ROWS - 1;
    }
}

pub export fn zig_print_char(c: u8) void {
    if (c == '\n' or c == 10) {
        internal_newline();
    } else if (c == '\r' or c == 13) {
        cursor_col = 0;
    } else if (c == 8) { // Backspace
        if (cursor_col > 0) {
            cursor_col -= 1;
        } else if (cursor_row > 0) {
            cursor_row -= 1;
            cursor_col = MAX_COLS - 1;
        }
        const idx = @as(usize, cursor_row) * MAX_COLS + cursor_col;
        VIDEO_MEMORY[idx] = DEFAULT_ATTR | ' ';
    } else if (c >= 32 and c <= 126) {
        // Проверка перед печатью символа
        if (cursor_row >= MAX_ROWS) {
            scroll();
            cursor_row = MAX_ROWS - 1;
        }

        const idx = @as(usize, cursor_row) * MAX_COLS + cursor_col;
        VIDEO_MEMORY[idx] = DEFAULT_ATTR | @as(u16, c);
        
        cursor_col += 1;
        if (cursor_col >= MAX_COLS) {
            internal_newline();
        }
    }
    
    update_hardware_cursor();
}

pub export fn zig_clear_line(row: u8) void {
    if (row >= MAX_ROWS) return;
    const offset = @as(usize, row) * MAX_COLS;
    var i: usize = 0;
    while (i < MAX_COLS) : (i += 1) {
        VIDEO_MEMORY[offset + i] = DEFAULT_ATTR | ' ';
    }
}

fn update_hardware_cursor() void {
    const pos = @as(u16, cursor_row) * 80 + cursor_col;
    outb(0x3D4, 0x0F);
    outb(0x3D5, @intCast(pos & 0xFF));
    outb(0x3D4, 0x0E);
    outb(0x3D5, @intCast((pos >> 8) & 0xFF));
}

fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]" : : [val] "{al}" (val), [port] "{dx}" (port));
}
