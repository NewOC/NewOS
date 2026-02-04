const vga = @import("drivers/vga.zig");
const serial = @import("drivers/serial.zig");
const config = @import("config.zig");
const common = @import("commands/common.zig");

pub const ExceptionFrame = extern struct {
    gs: u32,
    fs: u32,
    es: u32,
    ds: u32,
    edi: u32,
    esi: u32,
    ebp: u32,
    esp_dummy: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    vector: u32,
    error_code: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
};

pub const TSS = extern struct {
    backlink: u32,
    esp0: u32,
    ss0: u32,
    esp1: u32,
    ss1: u32,
    esp2: u32,
    ss2: u32,
    cr3: u32,
    eip: u32,
    eflags: u32,
    eax: u32,
    ecx: u32,
    edx: u32,
    ebx: u32,
    esp: u32,
    ebp: u32,
    esi: u32,
    edi: u32,
    es: u32,
    cs: u32,
    ss: u32,
    ds: u32,
    fs: u32,
    gs: u32,
    ldt: u32,
    trap: u16,
    iomap_base: u16,
};

pub const exception_names = [_][]const u8{
    "#DE - DIVIDE BY ZERO",
    "#DB - DEBUG",
    "NMI INTERRUPT",
    "#BP - BREAKPOINT",
    "#OF - OVERFLOW",
    "#BR - BOUND RANGE EXCEEDED",
    "#UD - INVALID OPCODE",
    "#NM - DEVICE NOT AVAILABLE",
    "#DF - DOUBLE FAULT",
    "COPROCESSOR SEGMENT OVERRUN",
    "#TS - INVALID TSS",
    "#NP - SEGMENT NOT PRESENT",
    "#SS - STACK SEGMENT FAULT",
    "#GP - GENERAL PROTECTION FAULT",
    "#PF - PAGE FAULT",
    "RESERVED",
    "#MF - X87 FPU FLOATING POINT ERROR",
    "#AC - ALIGNMENT CHECK",
    "#MC - MACHINE CHECK",
    "#XM - SIMD FLOATING POINT EXCEPTION",
    "#VE - VIRTUALIZATION EXCEPTION",
    "#CP - CONTROL PROTECTION EXCEPTION",
    "RESERVED",
    "RESERVED",
    "RESERVED",
    "RESERVED",
    "RESERVED",
    "RESERVED",
    "#HV - HYPERVISOR INJECTION EXCEPTION",
    "#VC - VMM COMMUNICATION EXCEPTION",
    "#SX - SECURITY EXCEPTION",
    "RESERVED",
};

pub export var main_tss: TSS align(16) = undefined;
pub export var df_tss: TSS align(16) = undefined;

var emergency_stack: [4096]u8 align(16) = undefined;

pub export fn init_exception_handling() void {
    // Zero out TSS structures
    @memset(@as([*]u8, @ptrCast(&main_tss))[0..@sizeOf(TSS)], 0);
    @memset(@as([*]u8, @ptrCast(&df_tss))[0..@sizeOf(TSS)], 0);

    // Setup DF TSS
    df_tss.ss0 = 0x10;
    df_tss.esp0 = @intFromPtr(&emergency_stack) + emergency_stack.len;
    df_tss.esp = df_tss.esp0;
    df_tss.ss = 0x10;
    df_tss.ds = 0x10;
    df_tss.es = 0x10;
    df_tss.fs = 0x10;
    df_tss.gs = 0x10;
    df_tss.cs = 0x08;
    df_tss.eip = @intFromPtr(&double_fault_handler_task);
    df_tss.eflags = 0x2; // Reserved bit must be 1

    // CR3 should be current CR3
    df_tss.cr3 = get_cr3();
}

extern fn double_fault_handler_task() void;

fn get_cr3() u32 {
    return asm volatile ("mov %%cr3, %[ret]"
        : [ret] "=r" (-> u32),
    );
}

fn get_cr2() u32 {
    return asm volatile ("mov %%cr2, %[ret]"
        : [ret] "=r" (-> u32),
    );
}

pub fn get_cpu_id() u8 {
    // In a multi-core system, this would call get_lapic_id()
    return 0;
}

// --- Crash Suite Test Functions ---

pub fn crash_abort() noreturn {
    panic("Manual abort triggered via shell command.");
}

pub fn crash_invalid_op() void {
    asm volatile ("ud2");
}

pub fn crash_stack_overflow() void {
    // Prevent tail-call optimization with dummy assembly
    asm volatile ("" ::: "memory");
    var buf: [1024]u8 = undefined;
    // Access buffer to ensure it's not optimized away
    @as(*volatile u8, @ptrCast(&buf[0])).* = 0;
    crash_stack_overflow();
}

pub fn crash_page_fault() void {
    // Trigger a real Page Fault by accessing an unmapped address
    // We'll use 0xDEADC0DE as requested
    const ptr: *volatile u32 = @ptrFromInt(0xDEADC0DE);
    _ = ptr.*;
}

pub fn crash_gpf() void {
    // Loading an invalid segment selector into DS
    asm volatile ("mov %[val], %%ds" : : [val] "r" (@as(u32, 0x1234)));
}

export fn handle_exception(frame: *ExceptionFrame) void {
    if (frame.vector == 14) {
        if (handle_page_fault(frame)) return;
    }
    draw_rsod(frame, null, null);
}

fn handle_page_fault(frame: *ExceptionFrame) bool {
    _ = frame;
    const memory = @import("memory.zig");
    const cr2 = get_cr2();

    // Check if it's the poison address
    if (cr2 == 0xDEADC0DE) {
        return false; // Trigger RSOD
    }

    // Demand Paging range: 32MB to 64MB
    if (cr2 >= 0x2000000 and cr2 < 0x4000000) {
        if (memory.pmm.alloc_page()) |paddr| {
            if (memory.map_page(cr2, paddr)) {
                // Page successfully mapped, retry the instruction
                return true;
            }
        }
    }

    return false; // Fallthrough to RSOD
}

export fn handle_double_fault() noreturn {
    // When a double fault occurs, the CPU switches to the DF TSS.
    // The previous state is saved in the TSS pointed to by backlink.
    // Since main_tss is the only other task, it contains the failed state.
    draw_rsod(null, &main_tss, "Hardware Task Switch due to Double Fault.");
}

pub fn panic(msg: []const u8) noreturn {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;
    var esi: u32 = undefined;
    var edi: u32 = undefined;
    var ebp: u32 = undefined;
    var esp: u32 = undefined;
    var ds: u32 = 0;
    var es: u32 = 0;
    var fs: u32 = 0;
    var gs: u32 = 0;

    asm volatile (
        \\mov %%eax, %[eax]
        \\mov %%ebx, %[ebx]
        \\mov %%ecx, %[ecx]
        \\mov %%edx, %[edx]
        \\mov %%esi, %[esi]
        \\mov %%edi, %[edi]
        \\mov %%ebp, %[ebp]
        \\mov %%esp, %[esp]
        \\mov %%ds, %%ax
        \\mov %%eax, %[ds]
        \\mov %%es, %%ax
        \\mov %%eax, %[es]
        \\mov %%fs, %%ax
        \\mov %%eax, %[fs]
        \\mov %%gs, %%ax
        \\mov %%eax, %[gs]
        : [eax] "=m" (eax),
          [ebx] "=m" (ebx),
          [ecx] "=m" (ecx),
          [edx] "=m" (edx),
          [esi] "=m" (esi),
          [edi] "=m" (edi),
          [ebp] "=m" (ebp),
          [esp] "=m" (esp),
          [ds]  "=m" (ds),
          [es]  "=m" (es),
          [fs]  "=m" (fs),
          [gs]  "=m" (gs),
        :
        : "eax"
    );

    const frame = ExceptionFrame{
        .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx,
        .esi = esi, .edi = edi, .ebp = ebp, .esp_dummy = esp,
        .ds = ds, .es = es, .fs = fs, .gs = gs,
        .eip = 0, .cs = 0x08, .eflags = 0, .vector = 0xFF, .error_code = 0,
    };

    draw_rsod(@as(*const ExceptionFrame, @ptrCast(&frame)), null, msg);
}

fn draw_rsod(frame: ?*const ExceptionFrame, saved_tss: ?*const TSS, msg: ?[]const u8) noreturn {
    asm volatile ("cli");

    const bg_red = 0x4f; // Red background, White text

    // Clear screen with red
    for (0..2000) |i| {
        vga.VIDEO_MEMORY[i] = (bg_red << 8) | ' ';
    }

    print_at(1, 2, "****************************************************************************", bg_red);
    print_at(2, 2, "*                              KERNEL PANIC                                *", bg_red);
    print_at(3, 2, "****************************************************************************", bg_red);

    const vector = if (frame) |f| f.vector else if (saved_tss != null) @as(u32, 8) else 0xFF;
    const name = if (vector < 32) exception_names[vector] else if (vector == 0xFF) @as([]const u8, "SOFTWARE PANIC") else "UNKNOWN EXCEPTION";

    print_at(5, 2, "EXCEPTION: ", bg_red);
    print_at(5, 13, name, bg_red);

    var row: usize = 7;
    if (msg) |m| {
        print_at(row, 2, "REASON: ", bg_red);
        const display_msg = if (m.len > 68) m[0..68] else m;
        print_at(row, 10, display_msg, bg_red);
        row += 2;
    }

    const eax = if (frame) |f| f.eax else if (saved_tss) |t| t.eax else 0;
    const ebx = if (frame) |f| f.ebx else if (saved_tss) |t| t.ebx else 0;
    const ecx = if (frame) |f| f.ecx else if (saved_tss) |t| t.ecx else 0;
    const edx = if (frame) |f| f.edx else if (saved_tss) |t| t.edx else 0;
    const esi = if (frame) |f| f.esi else if (saved_tss) |t| t.esi else 0;
    const edi = if (frame) |f| f.edi else if (saved_tss) |t| t.edi else 0;
    const ebp = if (frame) |f| f.ebp else if (saved_tss) |t| t.ebp else 0;
    const esp = if (frame) |f| (if (f.vector == 0xFF) f.esp_dummy else @intFromPtr(&f.eflags) + 4) else if (saved_tss) |t| t.esp else 0;
    const eip = if (frame) |f| f.eip else if (saved_tss) |t| t.eip else 0;
    const cs  = if (frame) |f| f.cs  else if (saved_tss) |t| t.cs  else 0;
    const err = if (frame) |f| f.error_code else 0;

    const ds  = if (frame) |f| f.ds  else if (saved_tss) |t| t.ds  else 0;
    const es  = if (frame) |f| f.es  else if (saved_tss) |t| t.es  else 0;
    const fs  = if (frame) |f| f.fs  else if (saved_tss) |t| t.fs  else 0;
    const gs  = if (frame) |f| f.gs  else if (saved_tss) |t| t.gs  else 0;
    const ss  = if (saved_tss) |t| t.ss else 0x10;

    // Registers Row 1
    print_at(row, 2,  "EAX: ", bg_red); print_hex_at(row, 7,  eax, bg_red);
    print_at(row, 22, "EBX: ", bg_red); print_hex_at(row, 27, ebx, bg_red);
    print_at(row, 42, "ECX: ", bg_red); print_hex_at(row, 47, ecx, bg_red);
    print_at(row, 62, "EDX: ", bg_red); print_hex_at(row, 67, edx, bg_red);
    row += 1;

    // Registers Row 2
    print_at(row, 2,  "ESI: ", bg_red); print_hex_at(row, 7,  esi, bg_red);
    print_at(row, 22, "EDI: ", bg_red); print_hex_at(row, 27, edi, bg_red);
    print_at(row, 42, "EBP: ", bg_red); print_hex_at(row, 47, ebp, bg_red);
    print_at(row, 62, "ESP: ", bg_red); print_hex_at(row, 67, esp, bg_red);
    row += 1;

    // Registers Row 3 (Segments)
    print_at(row, 2,  "DS : ", bg_red); print_hex_at(row, 7,  ds,  bg_red);
    print_at(row, 22, "ES : ", bg_red); print_hex_at(row, 27, es,  bg_red);
    print_at(row, 42, "FS : ", bg_red); print_hex_at(row, 47, fs,  bg_red);
    print_at(row, 62, "GS : ", bg_red); print_hex_at(row, 67, gs,  bg_red);
    row += 1;

    // Registers Row 4
    print_at(row, 2,  "EIP: ", bg_red); print_hex_at(row, 7,  eip, bg_red);
    print_at(row, 22, "CS : ", bg_red); print_hex_at(row, 27, cs,  bg_red);
    print_at(row, 42, "SS : ", bg_red); print_hex_at(row, 47, ss,  bg_red);
    print_at(row, 62, "ERR: ", bg_red); print_hex_at(row, 67, err, bg_red);
    row += 2;

    const cr2 = get_cr2();
    const cr3 = get_cr3();
    const cpu_id = get_cpu_id();
    print_at(row, 2,  "CR2: ", bg_red); print_hex_at(row, 7,  cr2, bg_red);
    print_at(row, 22, "CR3: ", bg_red); print_hex_at(row, 27, cr3, bg_red);
    print_at(row, 42, "CPU: ", bg_red); print_dec_at(row, 47, cpu_id, bg_red);
    row += 2;

    if (esp != 0) {
        print_at(row, 2, "STACK DUMP:", bg_red); row += 1;
        const stack_ptr: [*]u32 = @ptrFromInt(esp);
        var col: usize = 2;
        for (0..6) |i| {
            print_hex_at(row, col, stack_ptr[i], bg_red);
            col += 15; // Increased spacing to 15
        }
        row += 2;
    }

    if (config.ENABLE_RSOD_REBOOT) {
        print_at(row, 2, "SYSTEM HALTED. Press ENTER to reboot.", bg_red);
    } else {
        print_at(row, 2, "SYSTEM HALTED.", bg_red);
    }

    // Serial output
    serial.serial_print_str("\r\n*** KERNEL PANIC ***\r\n");
    serial.serial_print_str("EXCEPTION: "); serial.serial_print_str(name); serial.serial_print_str("\r\n");
    if (msg) |m| {
        serial.serial_print_str("REASON: "); serial.serial_print_str(m); serial.serial_print_str("\r\n");
    }
    serial.serial_print_str("EAX: "); serial_print_hex(eax); serial.serial_print_str("  EBX: "); serial_print_hex(ebx); serial.serial_print_str("  ECX: "); serial_print_hex(ecx); serial.serial_print_str("  EDX: "); serial_print_hex(edx); serial.serial_print_str("\r\n");
    serial.serial_print_str("ESI: "); serial_print_hex(esi); serial.serial_print_str("  EDI: "); serial_print_hex(edi); serial.serial_print_str("  EBP: "); serial_print_hex(ebp); serial.serial_print_str("  ESP: "); serial_print_hex(esp); serial.serial_print_str("\r\n");
    serial.serial_print_str("DS : "); serial_print_hex(ds);  serial.serial_print_str("  ES : "); serial_print_hex(es);  serial.serial_print_str("  FS : "); serial_print_hex(fs);  serial.serial_print_str("  GS : "); serial_print_hex(gs);  serial.serial_print_str("\r\n");
    serial.serial_print_str("EIP: "); serial_print_hex(eip); serial.serial_print_str("  CS : "); serial_print_hex(cs);  serial.serial_print_str("  SS : "); serial_print_hex(ss);  serial.serial_print_str("  ERR: "); serial_print_hex(err); serial.serial_print_str("\r\n");
    serial.serial_print_str("CR2: "); serial_print_hex(cr2); serial.serial_print_str("  CR3: "); serial_print_hex(cr3); serial.serial_print_str("  CPU: ");
    const cpu_s = [1]u8{'0' + cpu_id};
    serial.serial_print_str(&cpu_s); serial.serial_print_str("\r\n");

    if (esp != 0) {
        serial.serial_print_str("STACK DUMP: ");
        const stack_ptr: [*]u32 = @ptrFromInt(esp);
        for (0..8) |i| {
            serial_print_hex(stack_ptr[i]);
            serial.serial_print_str(" ");
        }
        serial.serial_print_str("\r\n");
    }
    if (config.ENABLE_RSOD_REBOOT) {
        serial.serial_print_str("SYSTEM HALTED. Press ENTER to reboot.\r\n");
    } else {
        serial.serial_print_str("HALTED.\r\n");
    }

    if (config.ENABLE_RSOD_REBOOT) {
        // Clear keyboard and serial buffers
        while ((inb(0x64) & 0x01) != 0) { _ = inb(0x60); }
        while (serial.serial_has_data()) { _ = serial.serial_getchar(); }

        while (true) {
            // 1. Poll PS/2 Keyboard
            const status = inb(0x64);
            if ((status & 0x01) != 0) {
                const scancode = inb(0x60);
                if (scancode == 0x1C or scancode == 0x5A) {
                    reboot();
                }
            }

            // 2. Poll Serial Port (for -nographic)
            if (serial.serial_has_data()) {
                const char = serial.serial_getchar();
                if (char == 10 or char == 13) {
                    reboot();
                }
            }

            io_delay();
        }
    } else {
        while (true) {
            asm volatile ("cli; hlt");
        }
    }
}

fn io_delay() void {
    asm volatile ("outb %%al, $0x80" : : : "al");
}

fn reboot() noreturn {
    // 1. Pulse CPU reset line
    asm volatile (
        \\1:
        \\inb $0x64, %%al
        \\testb $2, %%al
        \\jnz 1b
        \\movb $0xFE, %%al
        \\outb %%al, $0x64
    );

    // 2. Fallback: Triple fault by loading a null IDT and triggering an interrupt
    const idt_ptr = packed struct {
        limit: u16 = 0,
        base: u32 = 0,
    }{};
    asm volatile ("lidt (%[ptr])" : : [ptr] "r" (&idt_ptr));
    asm volatile ("int $3");

    while (true) {
        asm volatile ("cli; hlt");
    }
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

fn print_at(row: usize, col: usize, msg: []const u8, attr: u16) void {
    for (msg, 0..) |c, i| {
        if (col + i >= 80) break;
        vga.VIDEO_MEMORY[row * 80 + col + i] = (attr << 8) | @as(u16, c);
    }
}

fn print_hex_at(row: usize, col: usize, val: u32, attr: u16) void {
    print_at(row, col, "0x", attr);
    var i: i8 = 7;
    while (i >= 0) : (i -= 1) {
        const nibble = @as(u8, @intCast((val >> @as(u5, @intCast(i * 4))) & 0xF));
        const char = if (nibble < 10) '0' + nibble else 'A' + (nibble - 10);
        vga.VIDEO_MEMORY[row * 80 + col + 2 + @as(usize, @intCast(7 - i))] = (attr << 8) | @as(u16, char);
    }
}

fn print_dec_at(row: usize, col: usize, val: u32, attr: u16) void {
    if (val == 0) {
        vga.VIDEO_MEMORY[row * 80 + col] = (attr << 8) | '0';
        return;
    }
    var buf: [10]u8 = undefined;
    var i: usize = 0;
    var n = val;
    while (n > 0) {
        buf[i] = @intCast('0' + (n % 10));
        n /= 10;
        i += 1;
    }
    for (0..i) |j| {
        vga.VIDEO_MEMORY[row * 80 + col + i - 1 - j] = (attr << 8) | @as(u16, buf[j]);
    }
}

fn serial_print_hex(val: u32) void {
    serial.serial_print_str("0x");
    var i: i8 = 7;
    while (i >= 0) : (i -= 1) {
        const nibble = @as(u8, @intCast((val >> @as(u5, @intCast(i * 4))) & 0xF));
        const char = if (nibble < 10) '0' + nibble else 'A' + (nibble - 10);
        const buf = [1]u8{char};
        serial.serial_print_str(&buf);
    }
}
