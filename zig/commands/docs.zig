// Detailed Documentation Command
const common = @import("common.zig");
const vga = @import("../drivers/vga.zig");

pub fn execute(args: []const u8) void {
    const COLOR_HEADER = 14; // Yellow
    const COLOR_TEXT = 7;    // Light Grey
    const COLOR_BG = 0;

    if (common.std_mem_eql(args, "nova")) {
        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("=== Nova Language Syntax ===\n\n");
        
        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("[ Variables ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("set int x = 10;", "Integer variable (32-bit).");
        print_doc("set string s = \"a\";", "String variable (Max 64 chars).");
        common.printZ("  * Variables are persistent during the session (Max 16).\n");
        common.printZ("  * Assigning Int to String performs auto-casting.\n");

        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("\n[ Expressions ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("1 + 2 * 3", "L-R eval: result is 9.");
        print_doc("(1 + 2) * 3", "Order control with parens.");
        print_doc("\"Hey \" + name", "String concatenation.");

        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("\n[ Commands ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("print(a + b);", "Print result to console.");
        print_doc("exit();", "Return to NewOS Shell.");
        
        common.printZ("\nStatements MUST end with a semicolon (;).\n");
        vga.reset_color();
        return;
    }

    vga.set_color(COLOR_HEADER, COLOR_BG);
    common.printZ("=== NewOS Documentation ===\n\n");

    vga.set_color(COLOR_HEADER, COLOR_BG);
    common.printZ("[ System ]\n");
    vga.set_color(COLOR_TEXT, COLOR_BG);
    print_doc("help", "Displays a brief list of all available commands.");
    print_doc("docs", "Show this detailed documentation.");
    print_doc("docs nova", "Show Nova language syntax and help.");
    print_doc("sysinfo", "Shows OS version, CPU vendor, RAM, and disk sizes.");
    print_doc("uptime", "Shows how long the system has been running.");
    print_doc("reboot/shutdown", "Standard power management commands.");

    vga.set_color(COLOR_HEADER, COLOR_BG);
    common.printZ("\n[ File System ]\n");
    vga.set_color(COLOR_TEXT, COLOR_BG);
    print_doc("ls", "List files in the current directory.");
    print_doc("mount <0/1>", "Selects the active disk (0=Master, 1=Slave).");
    print_doc("cp <src> <dst>", "Copies a file from source to destination.");
    print_doc("mv/ren <o> <n>", "Renames or moves a file.");
    print_doc("rm <file>", "Deletes a file permanently.");
    print_doc("format <id> --force", "Formats a disk. Drive 0 is system-protected.");

    vga.set_color(COLOR_HEADER, COLOR_BG);
    common.printZ("\n[ Utilities ]\n");
    vga.set_color(COLOR_TEXT, COLOR_BG);
    print_doc("edit <file>", "Simple text editor with save (F2) and exit (F10).");
    print_doc("write <f> <t>", "Creates a file and writes the provided text to it.");
    print_doc("cat <file>", "Displays the contents of a file on the screen.");
    print_doc("nova", "Starts the Nova interpreted language shell.");

    common.printZ("\nTip: Use 'docs <topic>' for specific help.\n");
    vga.reset_color();
}

fn print_doc(cmd: []const u8, desc: []const u8) void {
    const COLOR_CMD = 15;
    const COLOR_TEXT = 7;
    const COLOR_BG = 0;

    vga.set_color(COLOR_CMD, COLOR_BG);
    common.printZ("  ");
    common.printZ(cmd);
    
    // Simple padding
    var i: usize = cmd.len;
    while (i < 20) : (i += 1) common.print_char(' ');
    
    vga.set_color(COLOR_TEXT, COLOR_BG);
    common.printZ("- ");
    common.printZ(desc);
    common.printZ("\n");
}
