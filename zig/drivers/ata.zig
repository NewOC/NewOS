// ATA PIO Driver
// Provides basic read/write access to ATA hard disks.

const common = @import("../commands/common.zig");

pub const Drive = enum(u1) {
    Master = 0,
    Slave = 1,
};

pub const ATA_PRIMARY_BASE = 0x1F0;
pub const ATA_STATUS_REG = ATA_PRIMARY_BASE + 7;
pub const ATA_COMMAND_REG = ATA_PRIMARY_BASE + 7;

fn wait_bsy() void {
    while ((common.inb(ATA_STATUS_REG) & 0x80) != 0) {}
}

fn wait_drq() void {
    while ((common.inb(ATA_STATUS_REG) & 0x08) == 0) {}
}

pub fn identify(drive: Drive) u32 {
    common.outb(ATA_PRIMARY_BASE + 6, if (drive == .Master) @as(u8, 0xA0) else @as(u8, 0xB0));
    common.outb(ATA_PRIMARY_BASE + 2, 0);
    common.outb(ATA_PRIMARY_BASE + 3, 0);
    common.outb(ATA_PRIMARY_BASE + 4, 0);
    common.outb(ATA_PRIMARY_BASE + 5, 0);
    common.outb(ATA_COMMAND_REG, 0xEC);

    const status = common.inb(ATA_STATUS_REG);
    if (status == 0) return 0;

    wait_bsy();

    const low = common.inb(ATA_PRIMARY_BASE + 4);
    const high = common.inb(ATA_PRIMARY_BASE + 5);
    if (low != 0 or high != 0) return 0; // Not ATA

    wait_drq();

    // Read 256 words (512 bytes)
    var sectors: u32 = 0;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const word = common.inw(ATA_PRIMARY_BASE);
        if (i == 60) {
            sectors = word;
        } else if (i == 61) {
            sectors |= (@as(u32, word) << 16);
        }
    }

    return sectors;
}

pub fn read_sector(drive: Drive, lba: u32, buffer: [*]u8) void {
    wait_bsy();
    common.outb(ATA_PRIMARY_BASE + 6, 0xE0 | (@as(u8, @intFromEnum(drive)) << 4) | @as(u8, @intCast((lba >> 24) & 0x0F)));
    common.outb(ATA_PRIMARY_BASE + 2, 1); // 1 sector
    common.outb(ATA_PRIMARY_BASE + 3, @intCast(lba & 0xFF));
    common.outb(ATA_PRIMARY_BASE + 4, @intCast((lba >> 8) & 0xFF));
    common.outb(ATA_PRIMARY_BASE + 5, @intCast((lba >> 16) & 0xFF));
    common.outb(ATA_COMMAND_REG, 0x20);

    wait_bsy();
    wait_drq();

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const word = common.inw(ATA_PRIMARY_BASE);
        buffer[i * 2] = @intCast(word & 0xFF);
        buffer[i * 2 + 1] = @intCast((word >> 8) & 0xFF);
    }
}

pub fn write_sector(drive: Drive, lba: u32, data: [*]const u8) void {
    wait_bsy();
    common.outb(ATA_PRIMARY_BASE + 6, 0xE0 | (@as(u8, @intFromEnum(drive)) << 4) | @as(u8, @intCast((lba >> 24) & 0x0F)));
    common.outb(ATA_PRIMARY_BASE + 2, 1); // 1 sector
    common.outb(ATA_PRIMARY_BASE + 3, @intCast(lba & 0xFF));
    common.outb(ATA_PRIMARY_BASE + 4, @intCast((lba >> 8) & 0xFF));
    common.outb(ATA_PRIMARY_BASE + 5, @intCast((lba >> 16) & 0xFF));
    common.outb(ATA_COMMAND_REG, 0x30);

    wait_bsy();
    wait_drq();

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        const word: u16 = @as(u16, data[i * 2]) | (@as(u16, data[i * 2 + 1]) << 8);
        common.outw(ATA_PRIMARY_BASE, word);
    }

    // Flush cache
    common.outb(ATA_COMMAND_REG, 0xE7);
    wait_bsy();
}
