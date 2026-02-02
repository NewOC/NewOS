// VGA Text Mode Driver (80x25) - Ultra-Robust Version
const common = @import("../commands/common.zig");

pub const VIDEO_MEMORY: [*]volatile u16 = @ptrFromInt(0xb8000);
pub const MAX_COLS: usize = 80;
pub const MAX_ROWS: usize = 25;
pub const DEFAULT_ATTR: u16 = 0x0f00; // White on black

pub export var cursor_row: u8 = 0;
pub export var cursor_col: u8 = 0;

/// Clear the entire screen buffer
pub export fn clear_screen() void {
    var i: usize = 0;
    while (i < MAX_COLS * MAX_ROWS) : (i += 1) {
        VIDEO_MEMORY[i] = DEFAULT_ATTR | ' ';
    }
    cursor_row = 0;
    cursor_col = 0;
}

/// Scroll one line up
fn scroll_one() void {
    // Copy rows 1..24 to 0..23
    var row: usize = 1;
    while (row < MAX_ROWS) : (row += 1) {
        var col: usize = 0;
        while (col < MAX_COLS) : (col += 1) {
            const dest = (row - 1) * MAX_COLS + col;
            const src = row * MAX_COLS + col;
            VIDEO_MEMORY[dest] = VIDEO_MEMORY[src];
        }
    }
    // Clear last row
    const last_line = (MAX_ROWS - 1) * MAX_COLS;
    var i: usize = 0;
    while (i < MAX_COLS) : (i += 1) {
        VIDEO_MEMORY[last_line + i] = DEFAULT_ATTR | ' ';
    }
}

/// Print character with full control over cursor
pub export fn zig_print_char(c: u8) void {
    if (c == 10) { // LF (Line Feed)
        cursor_row += 1;
        cursor_col = 0; // Forced CR on LF for shell reliability
    } else if (c == 13) { // CR (Carriage Return)
        cursor_col = 0;
    } else if (c == 8) { // Backspace
        if (cursor_col > 0) {
            cursor_col -= 1;
            const idx = @as(usize, cursor_row) * MAX_COLS + cursor_col;
            VIDEO_MEMORY[idx] = DEFAULT_ATTR | ' ';
        }
    } else if (c >= 32 and c <= 126) {
        const idx = @as(usize, cursor_row) * MAX_COLS + cursor_col;
        VIDEO_MEMORY[idx] = DEFAULT_ATTR | @as(u16, c);
        cursor_col += 1;
    }

    // Wrap column
    if (cursor_col >= MAX_COLS) {
        cursor_col = 0;
        cursor_row += 1;
    }

    // Scroll if row exceeded
    while (cursor_row >= MAX_ROWS) {
        scroll_one();
        cursor_row -= 1;
    }
}

/// Clear specific row
pub export fn zig_clear_line(row: u8) void {
    if (row >= MAX_ROWS) return;
    const offset = @as(usize, row) * MAX_COLS;
    var i: usize = 0;
    while (i < MAX_COLS) : (i += 1) {
        VIDEO_MEMORY[offset + i] = DEFAULT_ATTR | ' ';
    }
}
