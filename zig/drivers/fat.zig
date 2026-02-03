// FAT12/16 Filesystem Driver
const common = @import("../commands/common.zig");
const ata = @import("ata.zig");

pub const FatType = enum {
    None,
    FAT12,
    FAT16,
    FAT32,
};

pub const BPB = struct {
    oem_name: [8]u8,
    bytes_per_sector: u16,
    sectors_per_cluster: u8,
    reserved_sectors: u16,
    num_fats: u8,
    root_entries: u16,
    total_sectors_16: u16,
    media_descriptor: u8,
    sectors_per_fat: u16,
    sectors_per_track: u16,
    num_heads: u16,
    hidden_sectors: u32,
    total_sectors_32: u32,

    // Calculated fields
    first_fat_sector: u32,
    first_root_dir_sector: u32,
    first_data_sector: u32,
    root_dir_sectors: u32,
    fat_type: FatType,
};

pub fn read_bpb(drive: ata.Drive) ?BPB {
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, 0, &buffer);

    if (buffer[510] != 0x55 or buffer[511] != 0xAA) return null;

    var bpb: BPB = undefined;
    
    // Copy OEM name
    for (0..8) |i| bpb.oem_name[i] = buffer[3 + i];

    bpb.bytes_per_sector = @as(u16, buffer[11]) | (@as(u16, buffer[12]) << 8);
    bpb.sectors_per_cluster = buffer[13];
    bpb.reserved_sectors = @as(u16, buffer[14]) | (@as(u16, buffer[15]) << 8);
    bpb.num_fats = buffer[16];
    bpb.root_entries = @as(u16, buffer[17]) | (@as(u16, buffer[18]) << 8);
    bpb.total_sectors_16 = @as(u16, buffer[19]) | (@as(u16, buffer[20]) << 8);
    bpb.media_descriptor = buffer[21];
    bpb.sectors_per_fat = @as(u16, buffer[22]) | (@as(u16, buffer[23]) << 8);
    bpb.sectors_per_track = @as(u16, buffer[24]) | (@as(u16, buffer[25]) << 8);
    bpb.num_heads = @as(u16, buffer[26]) | (@as(u16, buffer[27]) << 8);
    bpb.hidden_sectors = @as(u32, buffer[28]) | (@as(u32, buffer[29]) << 8) | (@as(u32, buffer[30]) << 16) | (@as(u32, buffer[31]) << 24);
    bpb.total_sectors_32 = @as(u32, buffer[32]) | (@as(u32, buffer[33]) << 8) | (@as(u32, buffer[34]) << 16) | (@as(u32, buffer[35]) << 24);

    if (bpb.bytes_per_sector != 512) return null; // We only support 512 for now

    // Strict check: Must have FAT12 or FAT16 string at specific offsets
    const is_fat12 = common.std_mem_eql(buffer[0x36..0x3E], "FAT12   ");
    const is_fat16 = common.std_mem_eql(buffer[0x36..0x3E], "FAT16   ");
    if (!is_fat12 and !is_fat16) return null;

    bpb.root_dir_sectors = ((@as(u32, bpb.root_entries) * 32) + (bpb.bytes_per_sector - 1)) / bpb.bytes_per_sector;
    bpb.first_fat_sector = bpb.reserved_sectors;
    bpb.first_root_dir_sector = bpb.first_fat_sector + (bpb.num_fats * bpb.sectors_per_fat);
    bpb.first_data_sector = bpb.first_root_dir_sector + bpb.root_dir_sectors;

    const total_sectors = if (bpb.total_sectors_16 == 0) bpb.total_sectors_32 else bpb.total_sectors_16;
    const data_sectors = total_sectors - (bpb.reserved_sectors + (bpb.num_fats * bpb.sectors_per_fat) + bpb.root_dir_sectors);
    const total_clusters = data_sectors / bpb.sectors_per_cluster;

    if (total_clusters < 4085) {
        bpb.fat_type = .FAT12;
    } else if (total_clusters < 65525) {
        bpb.fat_type = .FAT16;
    } else {
        bpb.fat_type = .FAT32;
    }

    return bpb;
}

pub const DirEntry = struct {
    name: [8]u8,
    ext: [3]u8,
    attr: u8,
    reserved: u8,
    creation_time_tenth: u8,
    creation_time: u16,
    creation_date: u16,
    last_access_date: u16,
    first_cluster_high: u16,
    write_time: u16,
    write_date: u16,
    first_cluster_low: u16,
    file_size: u32,
};

pub fn list_root(drive: ata.Drive, bpb: BPB) void {
    var buffer: [512]u8 = undefined;
    var sector = bpb.first_root_dir_sector;
    
    while (sector < bpb.first_data_sector) : (sector += 1) {
        ata.read_sector(drive, sector, &buffer);
        
        var i: usize = 0;
        while (i < 512) : (i += 32) {
            if (buffer[i] == 0) return; // No more files
            if (buffer[i] == 0xE5) continue; // Deleted file
            if (buffer[i + 11] == 0x0F) continue; // LFN
            
            const case_bits = buffer[i + 12];
            const name_lower = (case_bits & 0x08) != 0;
            const ext_lower = (case_bits & 0x10) != 0;

            // Print name
            for (0..8) |j| {
                const c = buffer[i + j];
                if (c == ' ') break;
                if (name_lower and c >= 'A' and c <= 'Z') {
                    common.print_char(c + 32);
                } else {
                    common.print_char(c);
                }
            }
            // Print extension if exists
            if (buffer[i + 8] != ' ') {
                common.print_char('.');
                for (0..3) |j| {
                    const c = buffer[i + 8 + j];
                    if (c == ' ') break;
                    if (ext_lower and c >= 'A' and c <= 'Z') {
                        common.print_char(c + 32);
                    } else {
                        common.print_char(c);
                    }
                }
            }
            common.printZ("  ");
            
            const size = @as(u32, buffer[i + 28]) | (@as(u32, buffer[i + 29]) << 8) | (@as(u32, buffer[i + 30]) << 16) | (@as(u32, buffer[i + 31]) << 24);
            common.printNum(@intCast(size));
            common.printZ(" bytes\n");
        }
    }
}

pub fn read_file(drive: ata.Drive, bpb: BPB, name: []const u8, output: [*]u8) i32 {
    const entry = find_entry(drive, bpb, name) orelse return -1;
    
    var current_cluster = @as(u32, entry.first_cluster_low);
    var bytes_read: u32 = 0;
    const total_size = entry.file_size;

    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);

    while (current_cluster < eof_val and bytes_read < total_size) {
        const lba = bpb.first_data_sector + (current_cluster - 2) * bpb.sectors_per_cluster;
        
        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster and bytes_read < total_size) : (s += 1) {
            var sector_buf: [512]u8 = undefined;
            ata.read_sector(drive, lba + s, &sector_buf);
            
            const to_copy = @min(total_size - bytes_read, 512);
            for (0..to_copy) |j| output[bytes_read + j] = sector_buf[j];
            bytes_read += @intCast(to_copy);
        }
        
        current_cluster = get_fat_entry(drive, bpb, current_cluster);
        if (current_cluster == 0) break;
    }
    
    return @intCast(bytes_read);
}

/// Streams a file to the console without loading it all into RAM
pub fn stream_to_console(drive: ata.Drive, bpb: BPB, name: []const u8) bool {
    const entry = find_entry(drive, bpb, name) orelse return false;
    
    var current_cluster = @as(u32, entry.first_cluster_low);
    var bytes_processed: u32 = 0;
    const total_size = entry.file_size;
    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);

    while (current_cluster < eof_val and bytes_processed < total_size) {
        const lba = bpb.first_data_sector + (current_cluster - 2) * bpb.sectors_per_cluster;
        
        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster and bytes_processed < total_size) : (s += 1) {
            var sector_buf: [512]u8 = undefined;
            ata.read_sector(drive, lba + s, &sector_buf);
            
            const to_print = @min(total_size - bytes_processed, 512);
            for (0..to_print) |j| common.print_char(sector_buf[j]);
            bytes_processed += @intCast(to_print);
        }
        
        current_cluster = get_fat_entry(drive, bpb, current_cluster);
        if (current_cluster == 0) break;
    }
    common.printZ("\n");
    return true;
}

pub const EntryLocation = struct {
    sector: u32,
    offset: u32,
};

pub const FatName = struct {
    name: []const u8,
    ext: []const u8,
};

fn fat_parse_name(name: []const u8) FatName {
    // Locate the LAST dot to follow standard extensions, 
    // but handle leading dots specially for Unix-style dotfiles.
    var last_dot: ?usize = null;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        if (name[i] == '.') last_dot = i;
    }

    if (last_dot) |dot| {
        // If the ONLY dot is at the start (e.g. ".history" or ".gitignore")
        // treat it as the filename, with no extension.
        if (dot == 0) {
             return FatName{ .name = name, .ext = "" };
        }
        
        return FatName{ .name = name[0..dot], .ext = name[dot+1..] };
    }
    
    return FatName{ .name = name, .ext = "" };
}

pub fn find_entry_location(drive: ata.Drive, bpb: BPB, name: []const u8) ?EntryLocation {
    var buffer: [512]u8 = undefined;
    var sector = bpb.first_root_dir_sector;
    
    const parts = fat_parse_name(name);
    const name_part = parts.name;
    const ext_part = parts.ext;

    while (sector < bpb.first_data_sector) : (sector += 1) {
        ata.read_sector(drive, sector, &buffer);
        var i: u32 = 0;
        while (i < 512) : (i += 32) {
            if (buffer[i] == 0) return null;
            if (buffer[i] == 0xE5) continue;
            
            // Standard Match
            var match_standard = true;
            for (0..8) |j| {
                const c = if (j < name_part.len) toUpper(name_part[j]) else ' ';
                if (buffer[i + j] != c) { match_standard = false; break; }
            }
            if (match_standard) {
                for (0..3) |j| {
                    const c = if (j < ext_part.len) toUpper(ext_part[j]) else ' ';
                    if (buffer[i + 8 + j] != c) { match_standard = false; break; }
                }
            }
            if (match_standard) return EntryLocation{ .sector = sector, .offset = i };

            // Legacy/Buggy Match: Check for Empty Name + Ext (how old code wrote .history)
            // Only try this if the requested name starts with '.' and has no other dots
            if (name.len > 1 and name[0] == '.') {
                const legacy_ext = name[1..];
                var match_legacy = true;
                
                // Name must be all spaces
                for (0..8) |j| {
                    if (buffer[i + j] != ' ') { match_legacy = false; break; }
                }

                if (match_legacy) {
                    // Ext must match legacy_ext (truncated to 3)
                    for (0..3) |j| {
                        const c = if (j < legacy_ext.len) toUpper(legacy_ext[j]) else ' ';
                        if (buffer[i + 8 + j] != c) { match_legacy = false; break; }
                    }
                }
                
                if (match_legacy) return EntryLocation{ .sector = sector, .offset = i };
            }
        }
    }
    return null;
}

pub fn find_entry(drive: ata.Drive, bpb: BPB, name: []const u8) ?DirEntry {
    const loc = find_entry_location(drive, bpb, name) orelse return null;
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, loc.sector, &buffer);
    
    const i = loc.offset;
    var entry: DirEntry = undefined;
    entry.first_cluster_low = @as(u16, buffer[i + 26]) | (@as(u16, buffer[i + 27]) << 8);
    entry.file_size = @as(u32, buffer[i + 28]) | (@as(u32, buffer[i + 29]) << 8) | (@as(u32, buffer[i + 30]) << 16) | (@as(u32, buffer[i + 31]) << 24);
    return entry;
}

pub fn delete_file(drive: ata.Drive, bpb: BPB, name: []const u8) bool {
    const loc = find_entry_location(drive, bpb, name) orelse return false;
    
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, loc.sector, &buffer);
    
    // 1. Get first cluster
    const cluster = @as(u32, buffer[loc.offset + 26]) | (@as(u32, buffer[loc.offset + 27]) << 8);
    
    // 2. Mark entry as deleted (0xE5)
    buffer[loc.offset] = 0xE5;
    ata.write_sector(drive, loc.sector, &buffer);
    
    // 3. Free entire cluster chain
    free_cluster_chain(drive, bpb, cluster);
    
    return true;
}

fn free_cluster_chain(drive: ata.Drive, bpb: BPB, start_cluster: u32) void {
    if (start_cluster < 2) return;
    var current = start_cluster;
    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);

    while (current < eof_val) {
        const next = get_fat_entry(drive, bpb, current);
        set_fat_entry(drive, bpb, current, 0);
        if (next < 2 or next >= eof_val) break;
        current = next;
    }
}

pub fn write_file(drive: ata.Drive, bpb: BPB, name: []const u8, data: []const u8) bool {
    var cluster: u32 = 0;
    const exists = find_entry(drive, bpb, name);
    
    if (exists) |entry| {
        cluster = entry.first_cluster_low;
    } else {
        cluster = find_free_cluster(drive, bpb) orelse return false;
        const eof_val: u32 = if (bpb.fat_type == .FAT12) 0xFFF else 0xFFFF;
        set_fat_entry(drive, bpb, cluster, eof_val);
        if (!add_root_entry(drive, bpb, name, cluster, @intCast(data.len))) return false;
    }

    var bytes_written: u32 = 0;
    var current_cluster = cluster;
    const eof_val: u32 = if (bpb.fat_type == .FAT12) 0xFFF else 0xFFFF;

    while (bytes_written < data.len) {
        const lba = bpb.first_data_sector + (current_cluster - 2) * bpb.sectors_per_cluster;
        
        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster and bytes_written < data.len) : (s += 1) {
            var sector_buf: [512]u8 = [_]u8{0} ** 512;
            const to_copy = @min(data.len - bytes_written, 512);
            for (0..to_copy) |j| sector_buf[j] = data[bytes_written + j];
            ata.write_sector(drive, lba + s, &sector_buf);
            bytes_written += @intCast(to_copy);
        }
        
        if (bytes_written < data.len) {
            var next = get_fat_entry(drive, bpb, current_cluster);
            if (next >= (if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8))) {
                next = find_free_cluster(drive, bpb) orelse return false;
                set_fat_entry(drive, bpb, current_cluster, next);
                set_fat_entry(drive, bpb, next, eof_val);
            }
            current_cluster = next;
        } else {
            // We finished writing. If there's a leftover chain, free it.
            const next = get_fat_entry(drive, bpb, current_cluster);
            const eof_limit = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);
            if (next >= 2 and next < eof_limit) {
                free_cluster_chain(drive, bpb, next);
                // Mark current as EOF
                set_fat_entry(drive, bpb, current_cluster, eof_val);
            }
        }
    }
    
    return update_root_entry_size(drive, bpb, name, @intCast(data.len));
}

fn update_root_entry_size(drive: ata.Drive, bpb: BPB, name: []const u8, size: u32) bool {
    var buffer: [512]u8 = undefined;
    var sector = bpb.first_root_dir_sector;
    
    const parts = fat_parse_name(name);
    const name_part = parts.name;
    const ext_part = parts.ext;

    while (sector < bpb.first_data_sector) : (sector += 1) {
        ata.read_sector(drive, sector, &buffer);
        var i: usize = 0;
        var modified = false;
        while (i < 512) : (i += 32) {
            if (buffer[i] == 0) break;
            if (buffer[i] == 0xE5) continue;
            
            var match = true;
            for (0..8) |j| {
                const c = if (j < name_part.len) toUpper(name_part[j]) else ' ';
                if (buffer[i + j] != c) { match = false; break; }
            }
            if (match) {
                for (0..3) |j| {
                    const c = if (j < ext_part.len) toUpper(ext_part[j]) else ' ';
                    if (buffer[i + 8 + j] != c) { match = false; break; }
                }
            }
            
            if (match) {
                buffer[i + 28] = @intCast(size & 0xFF);
                buffer[i + 29] = @intCast((size >> 8) & 0xFF);
                buffer[i + 30] = @intCast((size >> 16) & 0xFF);
                buffer[i + 31] = @intCast((size >> 24) & 0xFF);
                modified = true;
                break;
            }
        }
        if (modified) {
            ata.write_sector(drive, sector, &buffer);
            return true;
        }
    }
    return false;
}

fn find_free_cluster(drive: ata.Drive, bpb: BPB) ?u32 {
    var cluster: u32 = 2; // Clusters 0 and 1 are reserved
    
    const max_clusters = if (bpb.fat_type == .FAT12) @as(u32, 4085) else @as(u32, 65525);
    
    while (cluster < max_clusters) : (cluster += 1) {
        const val = get_fat_entry(drive, bpb, cluster);
        if (val == 0) return cluster;
    }
    return null;
}

fn get_fat_entry(drive: ata.Drive, bpb: BPB, cluster: u32) u32 {
    var buffer: [1024]u8 = undefined; // 2 sectors for FAT12 safety
    
    if (bpb.fat_type == .FAT12) {
        const fat_offset = cluster + (cluster / 2);
        const sector = bpb.first_fat_sector + (fat_offset / 512);
        const ent_offset = fat_offset % 512;
        
        ata.read_sector(drive, sector, buffer[0..512].ptr);
        ata.read_sector(drive, sector + 1, buffer[512..1024].ptr);
        
        const val = @as(u16, buffer[ent_offset]) | (@as(u16, buffer[ent_offset + 1]) << 8);
        return if (cluster % 2 == 1) val >> 4 else val & 0xFFF;
    } else {
        const fat_offset = cluster * 2;
        const sector = bpb.first_fat_sector + (fat_offset / 512);
        const ent_offset = fat_offset % 512;
        
        ata.read_sector(drive, sector, buffer[0..512].ptr);
        return @as(u16, buffer[ent_offset]) | (@as(u16, buffer[ent_offset + 1]) << 8);
    }
}

fn set_fat_entry(drive: ata.Drive, bpb: BPB, cluster: u32, value: u32) void {
    var buffer: [1024]u8 = undefined;
    
    if (bpb.fat_type == .FAT12) {
        const fat_offset = cluster + (cluster / 2);
        const sector = bpb.first_fat_sector + (fat_offset / 512);
        const ent_offset = fat_offset % 512;
        
        ata.read_sector(drive, sector, buffer[0..512].ptr);
        ata.read_sector(drive, sector + 1, buffer[512..1024].ptr);
        
        var val = @as(u16, buffer[ent_offset]) | (@as(u16, buffer[ent_offset + 1]) << 8);
        if (cluster % 2 == 1) {
            val = (val & 0x000F) | (@as(u16, @intCast(value)) << 4);
        } else {
            val = (val & 0xF000) | (@as(u16, @intCast(value)) & 0x0FFF);
        }
        
        buffer[ent_offset] = @intCast(val & 0xFF);
        buffer[ent_offset + 1] = @intCast(val >> 8);
        
        ata.write_sector(drive, sector, buffer[0..512].ptr);
        ata.write_sector(drive, sector + 1, buffer[512..1024].ptr);
    } else {
        const fat_offset = cluster * 2;
        const sector = bpb.first_fat_sector + (fat_offset / 512);
        const ent_offset = fat_offset % 512;
        
        ata.read_sector(drive, sector, buffer[0..512].ptr);
        buffer[ent_offset] = @intCast(value & 0xFF);
        buffer[ent_offset + 1] = @intCast(value >> 8);
        ata.write_sector(drive, sector, buffer[0..512].ptr);
    }
}

fn add_root_entry(drive: ata.Drive, bpb: BPB, name: []const u8, cluster: u32, size: u32) bool {
    var buffer: [512]u8 = undefined;
    var sector = bpb.first_root_dir_sector;
    
    while (sector < bpb.first_data_sector) : (sector += 1) {
        ata.read_sector(drive, sector, &buffer);
        
        var i: usize = 0;
        while (i < 512) : (i += 32) {
            if (buffer[i] == 0 or buffer[i] == 0xE5) {
                // Free slot!
                for (0..32) |j| buffer[i + j] = 0;
                
                // Parse name and extension
                const parts = fat_parse_name(name);
                const name_part = parts.name;
                const ext_part = parts.ext;
                
                // Fill name (8 bytes)
                var case_bits: u8 = 0;
                var all_lower = true;
                var all_upper = true;

                for (name_part) |c| {
                    if (c >= 'a' and c <= 'z') all_upper = false;
                    if (c >= 'A' and c <= 'Z') all_lower = false;
                }
                if (all_lower) case_bits |= 0x08;

                for (0..8) |j| buffer[i + j] = ' ';
                for (0..@min(name_part.len, 8)) |j| buffer[i + j] = toUpper(name_part[j]);
                
                // Fill ext (3 bytes)
                all_lower = true;
                all_upper = true;
                for (ext_part) |c| {
                    if (c >= 'a' and c <= 'z') all_upper = false;
                    if (c >= 'A' and c <= 'Z') all_lower = false;
                }
                if (all_lower) case_bits |= 0x10;

                for (0..3) |j| buffer[i + 8 + j] = ' ';
                for (0..@min(ext_part.len, 3)) |j| buffer[i + 8 + j] = toUpper(ext_part[j]);
                
                buffer[i + 11] = 0x20; // Archive attribute
                buffer[i + 12] = case_bits; // NT Case Bits
                
                // Clusters
                buffer[i + 26] = @intCast(cluster & 0xFF);
                buffer[i + 27] = @intCast(cluster >> 8);
                
                // Size
                buffer[i + 28] = @intCast(size & 0xFF);
                buffer[i + 29] = @intCast((size >> 8) & 0xFF);
                buffer[i + 30] = @intCast((size >> 16) & 0xFF);
                buffer[i + 31] = @intCast((size >> 24) & 0xFF);
                
                ata.write_sector(drive, sector, &buffer);
                return true;
            }
        }
    }
    return false;
}

fn toUpper(c: u8) u8 {
    if (c >= 'a' and c <= 'z') return c - 'a' + 'A';
    return c;
}
