// Disk Management Commands
const common = @import("common.zig");
const ata = @import("../drivers/ata.zig");

pub fn lsdsk() void {
    common.printZ("Scanning for ATA disks...\n");
    common.printZ("NUM | SIZE (MB) | FILESYSTEM\n");
    common.printZ("----------------------------\n");

    var drive_idx: u8 = 0;
    while (drive_idx < 2) : (drive_idx += 1) {
        const drive = if (drive_idx == 0) ata.Drive.Master else ata.Drive.Slave;
        const total_sectors = ata.identify(drive);

        if (total_sectors > 0) {
            common.printNum(@intCast(drive_idx));
            common.printZ("   | ");
            
            const size_mb = (total_sectors * 512) / (1024 * 1024);
            common.printNum(@intCast(size_mb));
            common.printZ("       | ");

            // Check sector 0 for FS
            var buffer: [512]u8 = undefined;
            ata.read_sector(drive, 0, &buffer);

            if (buffer[510] == 0x55 and buffer[511] == 0xAA) {
                // Check for FAT
                if (common.std_mem_eql(buffer[0x36..0x3E], "FAT12   ")) {
                    common.printZ("FAT12\n");
                } else if (common.std_mem_eql(buffer[0x36..0x3E], "FAT16   ")) {
                    common.printZ("FAT16\n");
                } else if (common.std_mem_eql(buffer[0x52..0x5A], "FAT32   ")) {
                    common.printZ("FAT32\n");
                } else {
                    common.printZ("Unknown (Bootable)\n");
                }
            } else {
                common.printZ("None\n");
            }
        }
    }
}

pub fn mkfs_fat12(drive_num: u8) void {
    if (drive_num >= 2) {
        common.printZ("Error: Invalid drive number (0-1)\n");
        return;
    }

    const drive = if (drive_num == 0) ata.Drive.Master else ata.Drive.Slave;
    const total_sectors = ata.identify(drive);

    if (total_sectors == 0) {
        common.printZ("Error: Drive not found\n");
        return;
    }

    // FAT12 Limit: ~4084 clusters. With 8 sectors per cluster (4KB), 
    // max size is roughly 16MB.
    if (total_sectors > 32768) { // 32768 sectors * 512 bytes = 16MB
        common.printZ("Error: Disk too large for FAT12 (Max 16MB)\n");
        return;
    }

    common.printZ("Formatting drive ");
    common.printNum(@intCast(drive_num));
    common.printZ(" with FAT12...\n");

    var boot_sector: [512]u8 = [_]u8{0} ** 512;

    // JMP 0x3C, NOP
    boot_sector[0] = 0xEB;
    boot_sector[1] = 0x3C;
    boot_sector[2] = 0x90;

    // OEM Name
    const oem = "NEWOS   ";
    for (oem, 0..) |c, i| boot_sector[3+i] = c;

    // BPB
    boot_sector[11] = 0x00; boot_sector[12] = 0x02; // Bytes per sector (512)
    boot_sector[13] = 0x08; // Sectors per cluster (8 -> 4KB)
    boot_sector[14] = 0x01; boot_sector[15] = 0x00; // Reserved sectors (1)
    boot_sector[16] = 0x02; // Number of FATs (2)
    boot_sector[17] = 0xE0; boot_sector[18] = 0x00; // Root entry count (224)
    
    if (total_sectors < 65536) {
        boot_sector[19] = @intCast(total_sectors & 0xFF);
        boot_sector[20] = @intCast((total_sectors >> 8) & 0xFF);
    } else {
        boot_sector[19] = 0;
        boot_sector[20] = 0;
        boot_sector[32] = @intCast(total_sectors & 0xFF);
        boot_sector[33] = @intCast((total_sectors >> 8) & 0xFF);
        boot_sector[34] = @intCast((total_sectors >> 16) & 0xFF);
        boot_sector[35] = @intCast((total_sectors >> 24) & 0xFF);
    }

    boot_sector[21] = 0xF8; // Media descriptor (Hard Disk)
    
    // Sectors per FAT (rough estimate for FAT12)
    // Max FAT12 clusters ~ 4084. 4084 * 1.5 = 6126 bytes = 12 sectors.
    boot_sector[22] = 0x0C; boot_sector[23] = 0x00; // 12 sectors per FAT

    boot_sector[24] = 0x20; boot_sector[25] = 0x00; // Sectors per track (32)
    boot_sector[26] = 0x40; boot_sector[27] = 0x00; // Heads (64)
    
    // EBPB
    boot_sector[36] = 0x80; // Drive number
    boot_sector[38] = 0x29; // Signature
    boot_sector[39] = 0x78; boot_sector[40] = 0x56; boot_sector[41] = 0x34; boot_sector[42] = 0x12; // Serial

    const label = "NEWOS FAT12";
    for (label, 0..) |c, i| boot_sector[43+i] = c;

    const fstype = "FAT12   ";
    for (fstype, 0..) |c, i| boot_sector[54+i] = c;

    boot_sector[510] = 0x55;
    boot_sector[511] = 0xAA;

    ata.write_sector(drive, 0, &boot_sector);

    // Clear FATs (2 FATs of 12 sectors each)
    var zero_sector: [512]u8 = [_]u8{0} ** 512;
    // FAT1st byte: Media Descriptor, following bytes: 0xFF
    var fat_start_sector: [512]u8 = [_]u8{0} ** 512;
    fat_start_sector[0] = 0xF8;
    fat_start_sector[1] = 0xFF;
    fat_start_sector[2] = 0xFF;

    common.printZ("Initializing FAT tables...\n");
    var i: u32 = 0;
    while (i < 24) : (i += 1) {
        if (i == 0 or i == 12) {
            ata.write_sector(drive, 1 + i, &fat_start_sector);
        } else {
            ata.write_sector(drive, 1 + i, &zero_sector);
        }
    }

    // Clear Root Directory (224 entries * 32 bytes = 7168 bytes = 14 sectors)
    common.printZ("Initializing Root Directory...\n");
    i = 0;
    while (i < 14) : (i += 1) {
        ata.write_sector(drive, 25 + i, &zero_sector);
    }

    common.printZ("Format complete.\n");
}
