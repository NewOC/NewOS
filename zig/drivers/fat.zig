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

pub fn list_directory(drive: ata.Drive, bpb: BPB, dir_cluster: u32) void {
    if (dir_cluster == 0) {
        var sector = bpb.first_root_dir_sector;
        while (sector < bpb.first_data_sector) : (sector += 1) {
            if (!list_sector(drive, sector)) break;
        }
    } else {
        var current = dir_cluster;
        const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);
        while (current < eof_val) {
            const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
            var s: u32 = 0;
            while (s < bpb.sectors_per_cluster) : (s += 1) {
                if (!list_sector(drive, lba + s)) break;
            }
            current = get_fat_entry(drive, bpb, current);
            if (current == 0) break;
        }
    }
}

fn list_sector(drive: ata.Drive, sector: u32) bool {
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, sector, &buffer);
    var i: u32 = 0;
    while (i < 512) : (i += 32) {
        if (buffer[i] == 0) return false;
        if (buffer[i] == 0xE5) continue;
        if (buffer[i + 11] == 0x0F) continue; // LFN

        const attr = buffer[i + 11];
        const is_dir = (attr & 0x10) != 0;
        
        const case_bits = buffer[i + 12];
        const name_lower = (case_bits & 0x08) != 0;
        const ext_lower = (case_bits & 0x10) != 0;

        common.printZ(if (is_dir) "<DIR> " else "      ");

        // Print name
        var printed: usize = 0;
        for (0..8) |j| {
            const c = buffer[i + j];
            if (c == ' ') break;
            common.print_char(if (name_lower and c >= 'A' and c <= 'Z') c + 32 else c);
            printed += 1;
        }
        // Print extension if exists
        if (buffer[i + 8] != ' ' and buffer[i + 8] != 0) {
            common.print_char('.');
            printed += 1;
            for (0..3) |j| {
                const c = buffer[i + 8 + j];
                if (c == ' ' or c == 0) break;
                common.print_char(if (ext_lower and c >= 'A' and c <= 'Z') c + 32 else c);
                printed += 1;
            }
        }

        // Padding
        while (printed < 15) : (printed += 1) common.print_char(' ');

        if (!is_dir) {
            const size = @as(u32, buffer[i + 28]) | (@as(u32, buffer[i + 29]) << 8) | (@as(u32, buffer[i + 30]) << 16) | (@as(u32, buffer[i + 31]) << 24);
            common.printZ("  ");
            common.printNum(@intCast(size));
            common.printZ(" bytes");
        }
        common.printZ("\n");
    }
    return true;
}

pub fn read_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8, output: [*]u8) i32 {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return read_file_literal(drive, bpb, res.dir_cluster, res.file_name, output);
    }
    return -1;
}

pub fn read_file_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8, output: [*]u8) i32 {
    const entry = find_entry_literal(drive, bpb, dir_cluster, name) orelse return -1;
    
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
pub fn stream_to_console(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) bool {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return stream_to_console_literal(drive, bpb, res.dir_cluster, res.file_name);
    }
    return false;
}

pub fn stream_to_console_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) bool {
    const entry = find_entry_literal(drive, bpb, dir_cluster, name) orelse return false;
    
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

pub const PathResolution = struct {
    dir_cluster: u32,
    file_name: []const u8,
};

pub fn resolve_path(drive: ata.Drive, bpb: BPB, start_dir: u32, path: []const u8) ?PathResolution {
    if (path.len == 0) return null;

    var current_dir = start_dir;
    var remainder = path;

    // Handle absolute path
    if (path[0] == '/' or path[0] == '\\') {
        current_dir = 0;
        remainder = path[1..];
    }

    // Iterate through components
    while (true) {
        var i: usize = 0;
        while (i < remainder.len and remainder[i] != '/' and remainder[i] != '\\') : (i += 1) {}
        
        const component = remainder[0..i];
        
        // If this is the last component
        if (i == remainder.len) {
             if (component.len == 0) {
                 // Path ended with a slash: "dir/" 
                 return PathResolution{ .dir_cluster = current_dir, .file_name = "." };
             }
             return PathResolution{ .dir_cluster = current_dir, .file_name = component };
        }

        // Otherwise, move into the directory
        if (component.len > 0) {
            if (common.std_mem_eql(component, ".")) {
                // Stay in same dir
            } else if (common.std_mem_eql(component, "..")) {
                if (current_dir != 0) {
                    const entry = find_entry_literal(drive, bpb, current_dir, "..") orelse return null;
                    current_dir = entry.first_cluster_low;
                }
            } else {
                const entry = find_entry_literal(drive, bpb, current_dir, component) orelse return null;
                if ((entry.attr & 0x10) == 0) return null; // Not a directory
                current_dir = entry.first_cluster_low;
            }
        }

        remainder = remainder[i + 1 ..];
        // If nothing left after slash, we are done
        if (remainder.len == 0) return PathResolution{ .dir_cluster = current_dir, .file_name = "." };
    }
}

fn fat_parse_name(name: []const u8) FatName {
    if (common.std_mem_eql(name, ".")) return FatName{ .name = ".", .ext = "" };
    if (common.std_mem_eql(name, "..")) return FatName{ .name = "..", .ext = "" };

    // Locate the LAST dot to follow standard extensions, 
    // but handle leading dots specially for Unix-style dotfiles.
    // Also stop at slashes.
    var last_dot: ?usize = null;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        if (name[i] == '/' or name[i] == '\\') break;
        if (name[i] == '.') last_dot = i;
    }

    if (last_dot) |dot| {
        // If the ONLY dot is at the start (e.g. ".history" or ".gitignore")
        // treat it as the filename, with no extension.
        if (dot == 0) {
             return FatName{ .name = name[0..i], .ext = "" };
        }
        
        return FatName{ .name = name[0..dot], .ext = name[dot+1..i] };
    }
    
    return FatName{ .name = name[0..i], .ext = "" };
}

fn find_entry_in_sectors(drive: ata.Drive, name: []const u8, start_sector: u32, end_sector: u32) ?EntryLocation {
    var buffer: [512]u8 = undefined;
    const parts = fat_parse_name(name);
    const name_part = parts.name;
    const ext_part = parts.ext;

    var sector = start_sector;
    while (sector < end_sector) : (sector += 1) {
        ata.read_sector(drive, sector, &buffer);
        var i: u32 = 0;
        while (i < 512) : (i += 32) {
            if (buffer[i] == 0) return null;
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
            if (match) return EntryLocation{ .sector = sector, .offset = i };
        }
    }
    return null;
}

pub fn find_entry_location(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) ?EntryLocation {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return find_entry_location_literal(drive, bpb, res.dir_cluster, res.file_name);
    }
    return null;
}

fn find_entry_location_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) ?EntryLocation {
    if (dir_cluster == 0) {
        return find_entry_in_sectors(drive, name, bpb.first_root_dir_sector, bpb.first_data_sector);
    }

    var current = dir_cluster;
    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);
    while (current < eof_val) {
        const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
        if (find_entry_in_sectors(drive, name, lba, lba + bpb.sectors_per_cluster)) |loc| return loc;
        current = get_fat_entry(drive, bpb, current);
        if (current == 0) break;
    }
    return null;
}

pub fn find_entry(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) ?DirEntry {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return find_entry_literal(drive, bpb, res.dir_cluster, res.file_name);
    }
    return null;
}

pub fn find_entry_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) ?DirEntry {
    if (common.std_mem_eql(name, ".")) {
        var entry: DirEntry = undefined;
        for (0..8) |j| entry.name[j] = ' ';
        entry.name[0] = '.';
        for (0..3) |j| entry.ext[j] = ' ';
        entry.attr = 0x10;
        entry.first_cluster_low = @intCast(dir_cluster & 0xFFFF);
        entry.first_cluster_high = @intCast((dir_cluster >> 16) & 0xFFFF);
        entry.file_size = 0;
        return entry;
    }

    if (dir_cluster == 0 and common.std_mem_eql(name, "..")) {
        // Parent of root is root
        return find_entry_literal(drive, bpb, 0, ".");
    }

    const loc = find_entry_location_literal(drive, bpb, dir_cluster, name) orelse return null;
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, loc.sector, &buffer);
    
    const i = loc.offset;
    var entry: DirEntry = undefined;
    for (0..8) |j| entry.name[j] = buffer[i + j];
    for (0..3) |j| entry.ext[j] = buffer[i + 8 + j];
    entry.attr = buffer[i + 11];
    entry.reserved = buffer[i + 12];
    entry.creation_time_tenth = buffer[i + 13];
    entry.creation_time = @as(u16, buffer[i + 14]) | (@as(u16, buffer[i + 15]) << 8);
    entry.creation_date = @as(u16, buffer[i + 16]) | (@as(u16, buffer[i + 17]) << 8);
    entry.last_access_date = @as(u16, buffer[i + 18]) | (@as(u16, buffer[i + 19]) << 8);
    entry.first_cluster_high = @as(u16, buffer[i + 20]) | (@as(u16, buffer[i + 21]) << 8);
    entry.write_time = @as(u16, buffer[i + 22]) | (@as(u16, buffer[i + 23]) << 8);
    entry.write_date = @as(u16, buffer[i + 24]) | (@as(u16, buffer[i + 25]) << 8);
    entry.first_cluster_low = @as(u16, buffer[i + 26]) | (@as(u16, buffer[i + 27]) << 8);
    entry.file_size = @as(u32, buffer[i + 28]) | (@as(u32, buffer[i + 29]) << 8) | (@as(u32, buffer[i + 30]) << 16) | (@as(u32, buffer[i + 31]) << 24);
    return entry;
}

pub fn delete_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) bool {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return delete_file_literal(drive, bpb, res.dir_cluster, res.file_name);
    }
    return false;
}

fn delete_file_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) bool {
    const loc = find_entry_location_literal(drive, bpb, dir_cluster, name) orelse return false;
    
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

pub fn delete_directory(drive: ata.Drive, bpb: BPB, parent_cluster: u32, path: []const u8, recursive: bool) bool {
    if (resolve_path(drive, bpb, parent_cluster, path)) |res| {
        return delete_directory_literal(drive, bpb, res.dir_cluster, res.file_name, recursive);
    }
    return false;
}

fn delete_directory_literal(drive: ata.Drive, bpb: BPB, parent_cluster: u32, name: []const u8, recursive: bool) bool {
    const entry = find_entry_literal(drive, bpb, parent_cluster, name) orelse return false;
    if ((entry.attr & 0x10) == 0) return delete_file_literal(drive, bpb, parent_cluster, name);
    
    const cluster = entry.first_cluster_low;
    if (cluster == 0) return false; // Safety: Never delete root or its dots

    // Check if empty if not recursive
    if (!recursive) {
        if (!is_directory_empty(drive, bpb, cluster)) return false;
    }

    // 1. Delete all contents
    delete_all_in_directory(drive, bpb, cluster, recursive, true);
    
    // 2. Delete the entry
    return delete_file_literal(drive, bpb, parent_cluster, name);
}

pub fn is_directory_empty(drive: ata.Drive, bpb: BPB, dir_cluster: u32) bool {
    var buffer: [512]u8 = undefined;
    if (dir_cluster == 0) return false; // Root is never "empty" in a way we want to delete

    var current = dir_cluster;
    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);
    while (current < eof_val) {
        const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster) : (s += 1) {
            ata.read_sector(drive, lba + s, &buffer);
            var i: u32 = 0;
            while (i < 512) : (i += 32) {
                if (buffer[i] == 0) return true; // End of entries
                if (buffer[i] == 0xE5) continue;
                if (buffer[i + 11] == 0x0F) continue; // LFN

                const name = get_name_from_raw(buffer[i..i+32]);
                const n = name.buf[0..name.len];
                if (common.std_mem_eql(n, ".") or common.std_mem_eql(n, "..")) continue;
                
                return false; // Found something else
            }
        }
        current = get_fat_entry(drive, bpb, current);
        if (current == 0) break;
    }
    return true;
}

pub fn delete_all_in_directory(drive: ata.Drive, bpb: BPB, dir_cluster: u32, recursive: bool, delete_subdirs: bool) void {
    var buffer: [512]u8 = undefined;
    if (dir_cluster == 0) {
        var sector = bpb.first_root_dir_sector;
        while (sector < bpb.first_data_sector) : (sector += 1) {
            ata.read_sector(drive, sector, &buffer);
            delete_all_in_sector(drive, bpb, sector, &buffer, recursive, delete_subdirs);
        }
    } else {
        var current = dir_cluster;
        const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);
        while (current < eof_val) {
            const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
            var s: u32 = 0;
            while (s < bpb.sectors_per_cluster) : (s += 1) {
                ata.read_sector(drive, lba + s, &buffer);
                delete_all_in_sector(drive, bpb, lba + s, &buffer, recursive, delete_subdirs);
            }
            current = get_fat_entry(drive, bpb, current);
            if (current == 0) break;
        }
    }
}

fn delete_all_in_sector(drive: ata.Drive, bpb: BPB, sector: u32, buffer: *[512]u8, recursive: bool, delete_subdirs: bool) void {
    var i: u32 = 0;
    var changed = false;
    while (i < 512) : (i += 32) {
        if (buffer[i] == 0) break;
        if (buffer[i] == 0xE5) continue;
        if (buffer[i + 11] == 0x0F) continue; // LFN

        const name = get_name_from_raw(buffer[i..i+32]);
        const n = name.buf[0..name.len];
        if (common.std_mem_eql(n, ".") or common.std_mem_eql(n, "..")) continue;

        const is_dir = (buffer[i + 11] & 0x10) != 0;
        const cluster = @as(u32, buffer[i + 26]) | (@as(u32, buffer[i + 27]) << 8);

        if (is_dir) {
            if (delete_subdirs) {
                if (recursive) {
                    delete_all_in_directory(drive, bpb, cluster, true, true);
                } else {
                    if (!is_directory_empty(drive, bpb, cluster)) {
                        common.printZ("Skipping non-empty directory: ");
                        common.printZ(n);
                        common.printZ(" (use -r)\n");
                        continue;
                    }
                }
                free_cluster_chain(drive, bpb, cluster);
                buffer[i] = 0xE5;
                changed = true;
            } else {
                common.printZ("Skipping directory: ");
                common.printZ(n);
                common.printZ(" (use -d)\n");
            }
        } else {
            free_cluster_chain(drive, bpb, cluster);
            buffer[i] = 0xE5;
            changed = true;
        }
    }
    if (changed) ata.write_sector(drive, sector, buffer);
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

pub fn write_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8, data: []const u8) bool {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return write_file_literal(drive, bpb, res.dir_cluster, res.file_name, data);
    }
    return false;
}

fn write_file_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8, data: []const u8) bool {
    var cluster: u32 = 0;
    const exists = find_entry_literal(drive, bpb, dir_cluster, name);
    
    if (exists) |entry| {
        cluster = entry.first_cluster_low;
    } else {
        cluster = find_free_cluster(drive, bpb) orelse return false;
        const eof_val: u32 = if (bpb.fat_type == .FAT12) 0xFFF else 0xFFFF;
        set_fat_entry(drive, bpb, cluster, eof_val);
        if (!add_directory_entry(drive, bpb, dir_cluster, name, cluster, @intCast(data.len), 0x20)) return false;
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
    
    return update_entry_size_literal(drive, bpb, dir_cluster, name, @intCast(data.len));
}

fn update_entry_size_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8, size: u32) bool {
    const loc = find_entry_location_literal(drive, bpb, dir_cluster, name) orelse return false;
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, loc.sector, &buffer);
    
    const i = loc.offset;
    buffer[i + 28] = @intCast(size & 0xFF);
    buffer[i + 29] = @intCast((size >> 8) & 0xFF);
    buffer[i + 30] = @intCast((size >> 16) & 0xFF);
    buffer[i + 31] = @intCast((size >> 24) & 0xFF);
    
    ata.write_sector(drive, loc.sector, &buffer);
    return true;
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

pub fn get_fat_entry(drive: ata.Drive, bpb: BPB, cluster: u32) u32 {
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

pub fn create_directory(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) bool {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return create_directory_literal(drive, bpb, res.dir_cluster, res.file_name);
    }
    return false;
}

fn create_directory_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) bool {
    // 1. Check if name exists
    if (find_entry_literal(drive, bpb, dir_cluster, name) != null) return false;

    // 2. Find free cluster
    const cluster = find_free_cluster(drive, bpb) orelse return false;
    const eof_val: u32 = if (bpb.fat_type == .FAT12) 0xFFF else 0xFFFF;
    set_fat_entry(drive, bpb, cluster, eof_val);

    // 3. Add entry to parent
    if (!add_directory_entry(drive, bpb, dir_cluster, name, cluster, 0, 0x10)) return false;

    // 4. Initialize new directory cluster with . and ..
    var buffer: [512]u8 = [_]u8{0} ** 512;
    
    // "." entry
    for (0..32) |j| buffer[j] = ' ';
    buffer[0] = '.';
    buffer[11] = 0x10;
    buffer[26] = @intCast(cluster & 0xFF);
    buffer[27] = @intCast(cluster >> 8);

    // ".." entry
    for (0..32) |j| buffer[32 + j] = ' ';
    buffer[32 + 0] = '.';
    buffer[32 + 1] = '.';
    buffer[32 + 11] = 0x10;
    buffer[32 + 26] = @intCast(dir_cluster & 0xFF);
    buffer[32 + 27] = @intCast(dir_cluster >> 8);

    const lba = bpb.first_data_sector + (cluster - 2) * bpb.sectors_per_cluster;
    ata.write_sector(drive, lba, &buffer);
    
    // Clear rest of sectors in cluster if spc > 1
    var s: u32 = 1;
    zero_sector(&buffer);
    while (s < bpb.sectors_per_cluster) : (s += 1) {
        ata.write_sector(drive, lba + s, &buffer);
    }
    
    return true;
}

fn zero_sector(buf: *[512]u8) void {
    for (0..512) |i| buf[i] = 0;
}

fn add_directory_entry(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8, cluster: u32, size: u32, attr: u8) bool {
    if (dir_cluster == 0) {
        return add_root_entry_internal(drive, bpb, name, cluster, size, attr);
    }

    var current = dir_cluster;
    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);
    const fat_eof = if (bpb.fat_type == .FAT12) @as(u32, 0xFFF) else @as(u32, 0xFFFF);

    while (current < eof_val) {
        const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster) : (s += 1) {
            if (add_entry_to_sector(drive, lba + s, name, cluster, size, attr)) return true;
        }
        
        // No space in current cluster, get next
        var next = get_fat_entry(drive, bpb, current);
        if (next >= eof_val) {
            // Need to allocate new cluster for directory
            next = find_free_cluster(drive, bpb) orelse return false;
            set_fat_entry(drive, bpb, current, next);
            set_fat_entry(drive, bpb, next, fat_eof);
            
            // Zero the new cluster
            var buffer: [512]u8 = [_]u8{0} ** 512;
            const new_lba = bpb.first_data_sector + (next - 2) * bpb.sectors_per_cluster;
            var j: u32 = 0;
            while (j < bpb.sectors_per_cluster) : (j += 1) {
                ata.write_sector(drive, new_lba + j, &buffer);
            }
        }
        current = next;
    }
    return false;
}

fn add_entry_to_sector(drive: ata.Drive, sector: u32, name: []const u8, cluster: u32, size: u32, attr: u8) bool {
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, sector, &buffer);
    var i: u32 = 0;
    while (i < 512) : (i += 32) {
        if (buffer[i] == 0 or buffer[i] == 0xE5) {
            // Free slot
            const parts = fat_parse_name(name);
            const case_bits: u8 = 0;
            
            // Name
            for (0..8) |j| buffer[i + j] = ' ';
            for (0..@min(parts.name.len, 8)) |j| buffer[i + j] = toUpper(parts.name[j]);
            
            // Ext
            for (0..3) |j| buffer[i + 8 + j] = ' ';
            for (0..@min(parts.ext.len, 3)) |j| buffer[i + 8 + j] = toUpper(parts.ext[j]);
            
            buffer[i + 11] = attr;
            buffer[i + 12] = case_bits;
            
            // Cluster
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
    return false;
}

fn add_root_entry_internal(drive: ata.Drive, bpb: BPB, name: []const u8, cluster: u32, size: u32, attr: u8) bool {
    var sector = bpb.first_root_dir_sector;
    while (sector < bpb.first_data_sector) : (sector += 1) {
        if (add_entry_to_sector(drive, sector, name, cluster, size, attr)) return true;
    }
    return false;
}

fn toUpper(c: u8) u8 {
    if (c >= 'a' and c <= 'z') return c - 'a' + 'A';
    return c;
}
pub fn format(drive: ata.Drive, bpb: BPB, progress_cb: ?*const fn(u32, u32) void) bool {
    var buffer: [512]u8 = [_]u8{0} ** 512;

    const root_dir_sectors = bpb.root_dir_sectors;
    const total_fat_sectors = bpb.num_fats * bpb.sectors_per_fat;
    
    // Total ops = FAT sectors + Root Dir sectors
    const total_ops = total_fat_sectors + root_dir_sectors;
    var current_op: u32 = 0;

    // 1. Clear FATs
    var sector = bpb.first_fat_sector;
    var end_sector = bpb.first_fat_sector + total_fat_sectors;
    
    while (sector < end_sector) : (sector += 1) {
        ata.write_sector(drive, @intCast(sector), &buffer);
        current_op += 1;
        if (progress_cb) |cb| cb(current_op, total_ops);
    }
    
    // 2. Clear Root Directory
    sector = bpb.first_root_dir_sector;
    end_sector = bpb.first_root_dir_sector + root_dir_sectors;
    while (sector < end_sector) : (sector += 1) {
        ata.write_sector(drive, @intCast(sector), &buffer);
        current_op += 1;
        if (progress_cb) |cb| cb(current_op, total_ops);
    }

    // 3. Re-initialize the first FAT entries (FAT header)
    // Sector 0 of FAT 1
    ata.read_sector(drive, @intCast(bpb.first_fat_sector), &buffer);
    if (bpb.fat_type == .FAT12) {
        buffer[0] = 0xF8;
        buffer[1] = 0xFF;
        buffer[2] = 0xFF;
    } else {
        buffer[0] = 0xF8;
        buffer[1] = 0xFF;
        buffer[2] = 0xFF;
        buffer[3] = 0xFF;
    }
    ata.write_sector(drive, @intCast(bpb.first_fat_sector), &buffer);
    
    // If there's a second FAT, copy it there too
    if (bpb.num_fats > 1) {
        ata.write_sector(drive, @intCast(bpb.first_fat_sector + bpb.sectors_per_fat), &buffer);
    }
    
    return true;
}

pub fn rename_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, old_path: []const u8, new_path: []const u8) bool {
    const old_res = resolve_path(drive, bpb, dir_cluster, old_path) orelse return false;
    const new_res = resolve_path(drive, bpb, dir_cluster, new_path) orelse return false;
    
    // 1. Check if new name already exists
    if (find_entry_literal(drive, bpb, new_res.dir_cluster, new_res.file_name) != null) return false;

    // 2. Find legacy file
    const loc = find_entry_location_literal(drive, bpb, old_res.dir_cluster, old_res.file_name) orelse return false;

    // 3. Update entry
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, loc.sector, &buffer);

    const i = loc.offset;
    
    // Parse new name
    const parts = fat_parse_name(new_res.file_name);
    const name_part = parts.name;
    const ext_part = parts.ext;

    // Determine case
    var case_bits: u8 = 0;
    var all_lower = true;
    var all_upper = true;

    for (name_part) |c| {
        if (c >= 'a' and c <= 'z') all_upper = false;
        if (c >= 'A' and c <= 'Z') all_lower = false;
    }
    if (all_lower) case_bits |= 0x08;

    // Clear name fields
    for (0..8) |j| buffer[i + j] = ' ';
    for (0..3) |j| buffer[i + 8 + j] = ' ';

    // Write Name
    for (0..@min(name_part.len, 8)) |j| buffer[i + j] = toUpper(name_part[j]);
    
    // Write Ext
    all_lower = true;
    all_upper = true;
    for (ext_part) |c| {
        if (c >= 'a' and c <= 'z') all_upper = false;
        if (c >= 'A' and c <= 'Z') all_lower = false;
    }
    if (all_lower) case_bits |= 0x10;

    for (0..@min(ext_part.len, 3)) |j| buffer[i + 8 + j] = toUpper(ext_part[j]);

    // For now, let's just support rename in place.
    if (old_res.dir_cluster != new_res.dir_cluster) return false;

    // Update case bits
    buffer[i + 12] = case_bits;

    ata.write_sector(drive, loc.sector, &buffer);
    return true;
}

pub fn get_name_from_raw(entry: []const u8) struct { buf: [13]u8, len: usize } {
    var res: [13]u8 = [_]u8{0} ** 13;
    var n_len: usize = 0;
    const case_bits = entry[12];
    const name_lower = (case_bits & 0x08) != 0;
    const ext_lower = (case_bits & 0x10) != 0;
    for (0..8) |k| {
        const c = entry[k];
        if (c == ' ') break;
        res[n_len] = if (name_lower and c >= 'A' and c <= 'Z') c + 32 else c;
        n_len += 1;
    }
    if (entry[8] != ' ' and entry[8] != 0) {
        res[n_len] = '.';
        n_len += 1;
        for (0..3) |k| {
            const c = entry[8 + k];
            if (c == ' ' or c == 0) break;
            res[n_len] = if (ext_lower and c >= 'A' and c <= 'Z') c + 32 else c;
            n_len += 1;
        }
    }
    return .{ .buf = res, .len = n_len };
}
