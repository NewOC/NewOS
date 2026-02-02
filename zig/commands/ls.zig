// ls command - list files
const common = @import("common.zig");

pub fn execute() void {
    var ids: [16]u8 = undefined;
    const count = common.fs_list(&ids);
    
    if (count == 0) {
        common.printZ("No files\r\n");
        return;
    }
    
    var name_buf: [12]u8 = undefined;
    var i: u8 = 0;
    while (i < count) : (i += 1) {
        const id = ids[i];
        _ = common.fs_getname(id, &name_buf);
        
        for (name_buf) |c| {
            if (c == 0) break;
            common.print_char(c);
        }
        
        const size = common.fs_size(id);
        common.printZ("  ");
        common.printNum(size);
        common.printZ(" bytes\r\n");
    }
}
