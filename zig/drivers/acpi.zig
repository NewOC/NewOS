// ACPI (Advanced Configuration and Power Interface) Driver
// Provides real hardware shutdown support

const common = @import("../commands/common.zig");

var pm1a_control_block: u16 = 0;
var slp_typa: u16 = 0;
var slp_en: u16 = 0x2000; // SLP_EN bit (bit 13)

/// Search for RSDP signature in memory
fn find_rsdp() ?usize {
    const signature = "RSD PTR ";
    
    // Search in EBDA area (0x80000 - 0x9FFFF)
    var addr: usize = 0x80000;
    while (addr < 0xA0000) : (addr += 16) {
        if (check_signature_at(addr, signature)) {
            return addr;
        }
    }
    
    // Search in BIOS ROM area (0xE0000 - 0xFFFFF)
    addr = 0xE0000;
    while (addr < 0x100000) : (addr += 16) {
        if (check_signature_at(addr, signature)) {
            return addr;
        }
    }
    
    return null;
}

fn check_signature_at(addr: usize, sig: []const u8) bool {
    const ptr = @as([*]const u8, @ptrFromInt(addr));
    for (sig, 0..) |c, i| {
        if (ptr[i] != c) return false;
    }
    return true;
}

fn read_u32(addr: usize) u32 {
    const ptr = @as(*const u32, @ptrFromInt(addr));
    return ptr.*;
}

fn read_u8(addr: usize) u8 {
    const ptr = @as(*const u8, @ptrFromInt(addr));
    return ptr.*;
}

/// Initialize ACPI and find shutdown parameters
pub fn init() bool {
    const rsdp_addr = find_rsdp() orelse return false;
    
    // Read RSDT address from RSDP (offset 16)
    const rsdt_addr = read_u32(rsdp_addr + 16);
    
    // Read RSDT length (offset 4)
    const rsdt_length = read_u32(rsdt_addr + 4);
    
    // Calculate number of entries
    const header_size: u32 = 36; // RSDT header size
    const entries_size = rsdt_length - header_size;
    const num_entries = entries_size / 4;
    
    // Search for FACP (FADT) table
    var i: u32 = 0;
    while (i < num_entries) : (i += 1) {
        const entry_addr = rsdt_addr + header_size + (i * 4);
        const table_addr = read_u32(entry_addr);
        
        // Check if this is FACP table
        if (check_signature_at(table_addr, "FACP")) {
            // Read PM1a Control Block address (offset 64 in FADT)
            pm1a_control_block = @intCast(read_u32(table_addr + 64) & 0xFFFF);
            
            // Use default SLP_TYPa value (5 for S5 state)
            // In a full implementation, we would parse DSDT to find _S5 package
            slp_typa = 5 << 10; // SLP_TYPa field is bits 10-12
            
            return true;
        }
    }
    
    return false;
}

/// Perform ACPI shutdown
pub fn shutdown() noreturn {
    if (pm1a_control_block != 0) {
        // Write to PM1a Control Block to initiate shutdown
        const value = slp_typa | slp_en;
        outw(pm1a_control_block, value);
    }
    
    // Fallback: try QEMU/Bochs specific ports
    outw(0x604, 0x2000);
    outw(0xB004, 0x2000);
    
    // If all else fails, halt
    while (true) {
        asm volatile ("hlt");
    }
}

fn outw(port: u16, value: u16) void {
    asm volatile ("outw %[value], %[port]"
        :
        : [value] "{ax}" (value),
          [port] "{dx}" (port),
    );
}
