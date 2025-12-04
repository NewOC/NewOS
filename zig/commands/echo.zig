// echo command - print text
const common = @import("common.zig");

pub fn execute(text_ptr: [*]const u8, text_len: u16) void {
    var i: u16 = 0;
    while (i < text_len) : (i += 1) {
        common.print_char(text_ptr[i]);
    }
    common.print_char('\n');
}
