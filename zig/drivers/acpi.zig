// ACPI (Advanced Configuration and Power Interface) Driver
// Provides dynamic hardware shutdown support
const common = @import("../commands/common.zig");

var pm1a_control_block: u16 = 0;
var pm1b_control_block: u16 = 0;
var smi_command_port: u32 = 0;
var acpi_enable_val: u8 = 0;
var slp_typa: u16 = 0;
var slp_typb: u16 = 0;
var slp_en: u16 = 0x2000;

fn find_rsdp() ?usize {
    const signature = "RSD PTR ";
    var addr: usize = 0x80000; // Search EBDA
    while (addr < 0xA0000) : (addr += 16) {
        if (check_signature_at(addr, signature)) return addr;
    }
    addr = 0xE0000; // Search BIOS ROM
    while (addr < 0x100000) : (addr += 16) {
        if (check_signature_at(addr, signature)) return addr;
    }
    return null;
}

fn check_signature_at(addr: usize, sig: []const u8) bool {
    const ptr = @as([*]const u8, @ptrFromInt(addr));
    for (sig, 0..) |c, i| if (ptr[i] != c) return false;
    return true;
}

fn read_u32(addr: usize) u32 { return @as(*const u32, @ptrFromInt(addr)).*; }
fn read_u8(addr: usize) u8 { return @as(*const u8, @ptrFromInt(addr)).*; }

pub fn init() bool {
    const rsdp_addr = find_rsdp() orelse return false;
    const rsdt_addr = read_u32(rsdp_addr + 16);
    const rsdt_length = read_u32(rsdt_addr + 4);
    const num_entries = (rsdt_length - 36) / 4;
    
    var i: u32 = 0;
    while (i < num_entries) : (i += 1) {
        const table_addr = read_u32(rsdt_addr + 36 + (i * 4));
        if (check_signature_at(table_addr, "FACP")) {
            smi_command_port = read_u32(table_addr + 48);
            acpi_enable_val = read_u8(table_addr + 52);
            pm1a_control_block = @intCast(read_u32(table_addr + 64) & 0xFFFF);
            pm1b_control_block = @intCast(read_u32(table_addr + 68) & 0xFFFF);

            if (smi_command_port != 0 and acpi_enable_val != 0) {
                outb(@intCast(smi_command_port), acpi_enable_val);
                common.sleep(10);
            }
            slp_typa = 5 << 10;
            slp_typb = 5 << 10;
            
            //common.printZ("ACPI: Power Management initialized (Port: ");
            //common.printNum(@intCast(pm1a_control_block));
            //common.printZ(")\n");
            return true;
        }
    }
    return false;
}

pub fn shutdown() noreturn {
    if (pm1a_control_block != 0) {
        // 1. Try standard ACPI
        outw(pm1a_control_block, slp_typa | slp_en);
        if (pm1b_control_block != 0) outw(pm1b_control_block, slp_typb | slp_en);
        common.sleep(50);
        // 2. Try force (for QEMU/Bochs)
        outw(pm1a_control_block, slp_en);
        if (pm1b_control_block != 0) outw(pm1b_control_block, slp_en);
    }
    common.printZ("Shutdown failed. System halted.\n");
    while (true) asm volatile ("hlt");
}

fn outw(port: u16, value: u16) void {
    asm volatile ("outw %[value], %[port]" : : [value] "{ax}" (value), [port] "{dx}" (port));
}

fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]" : : [value] "{al}" (value), [port] "{dx}" (port));
}
