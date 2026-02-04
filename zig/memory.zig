// NewOS Memory Management Module - Advanced Edition
const common = @import("commands/common.zig");
const config = @import("config.zig");

pub const PAGE_SIZE = 4096;
pub const MAX_MEMORY = 128 * 1024 * 1024; // 128MB
pub const POISON_ADDRESS = 0xDEADC0DE;
pub const RESERVED_HIGH_BASE = 0xF0000000;
pub const TOTAL_PAGES = MAX_MEMORY / PAGE_SIZE;
pub const BITMAP_SIZE = TOTAL_PAGES / 8;

extern const ebss: anyopaque;

var bitmap: [BITMAP_SIZE]u8 = [_]u8{0} ** BITMAP_SIZE;
var last_free_page: u32 = 0;

/// Paging structures
const PageDirectory = [1024]u32;
const PageTable = [1024]u32;

var page_directory: PageDirectory align(4096) = [_]u32{0} ** 1024;
// Map first 128MB (32 tables)
var page_tables: [32]PageTable align(4096) = [_]PageTable{[_]u32{0} ** 1024} ** 32;

pub fn init_paging() void {
    // 1. Prepare Page Tables (Identity Map first 32MB)
    // We map 8 tables initially to be safe (covers kernel, stacks, ACPI, BDA).
    for (0..8) |t| {
        for (0..1024) |i| {
            const addr = (t * 1024 + i) * PAGE_SIZE;

            // NULL protection: first page (0x0000 - 0x0FFF) is NOT present
            if (t == 0 and i == 0) {
                page_tables[t][i] = 0; // Present = 0
            } else {
                page_tables[t][i] = @as(u32, @intCast(addr)) | 0x03; // Present + R/W
            }
        }
        // 2. Map Page Table into Page Directory
        page_directory[t] = @as(u32, @intCast(@intFromPtr(&page_tables[t]))) | 0x03; // Present + R/W
    }

    // 3. Enable Paging
    const pd_addr = @intFromPtr(&page_directory);
    var tmp: u32 = undefined;
    asm volatile (
        \\mov %[pd], %%cr3
        \\mov %%cr0, %[tmp]
        \\or $0x80000000, %[tmp]
        \\mov %[tmp], %%cr0
        \\jmp 1f
        \\1:
        : [tmp] "=&r" (tmp)
        : [pd] "r" (pd_addr)
        : "memory"
    );
}

/// Map a virtual page to a physical frame on demand
pub fn map_page(vaddr: usize) bool {
    // 1. Check for reserved/poison addresses
    if (vaddr >= RESERVED_HIGH_BASE) return false;

    // Check if the address falls into the same page as our poison label
    if ((vaddr & 0xFFFFF000) == (POISON_ADDRESS & 0xFFFFF000)) {
        return false;
    }

    const pd_idx = vaddr >> 22;
    const pt_idx = (vaddr >> 12) & 0x3FF;

    // 2. Support mapping up to 128MB (32 page tables)
    if (pd_idx >= 32) return false;

    // 1. Ensure Page Table is present in Page Directory
    if ((page_directory[pd_idx] & 0x01) == 0) {
        page_directory[pd_idx] = @as(u32, @intCast(@intFromPtr(&page_tables[pd_idx]))) | 0x03; // Present + R/W
    }

    // 2. Allocate a physical frame from PMM
    if (pmm.alloc_page()) |paddr| {
        // 3. Map virtual page to physical frame
        page_tables[pd_idx][pt_idx] = @as(u32, @intCast(paddr)) | 0x03; // Present + R/W

        // 4. Flush TLB for this address
        asm volatile ("invlpg (%[addr])" : : [addr] "r" (vaddr) : "memory");
        return true;
    }

    return false;
}

/// Physical Memory Manager (PMM)
pub const pmm = struct {
    pub fn init() void {
        const kernel_end = @intFromPtr(&ebss);
        for (&bitmap) |*b| b.* = 0;
        const reserved_up_to = if (kernel_end < 0x100000) 0x100000 else kernel_end;
        const reserved_pages = (reserved_up_to / PAGE_SIZE) + 1;
        var i: u32 = 0;
        while (i < reserved_pages) : (i += 1) set_page_busy(i);
    }

    pub fn alloc_page() ?usize {
        var i = last_free_page;
        while (i < TOTAL_PAGES) : (i += 1) {
            if (!is_page_busy(i)) {
                set_page_busy(i);
                last_free_page = i;
                return i * PAGE_SIZE;
            }
        }
        return null;
    }

    pub fn free_page(addr: usize) void {
        const idx = @as(u32, @intCast(addr / PAGE_SIZE));
        clear_page_busy(idx);
        if (idx < last_free_page) last_free_page = idx;
    }
};

fn set_page_busy(idx: u32) void {
    if (idx >= TOTAL_PAGES) return;
    bitmap[idx / 8] |= @as(u8, 1) << @as(u3, @intCast(idx % 8));
}

fn clear_page_busy(idx: u32) void {
    if (idx >= TOTAL_PAGES) return;
    bitmap[idx / 8] &= ~(@as(u8, 1) << @as(u3, @intCast(idx % 8)));
}

fn is_page_busy(idx: u32) bool {
    if (idx >= TOTAL_PAGES) return true;
    return (bitmap[idx / 8] & (@as(u8, 1) << @as(u3, @intCast(idx % 8)))) != 0;
}

/// --- Linked List Heap Allocator ---

const BlockHeader = struct {
    size: usize,
    is_free: bool,
    next: ?*BlockHeader,
};

var first_block: ?*BlockHeader = null;

pub const heap = struct {
    pub fn init() void {
        if (pmm.alloc_page()) |addr| {
            first_block = @as(*BlockHeader, @ptrFromInt(addr));
            first_block.?.* = .{
                .size = PAGE_SIZE - @sizeOf(BlockHeader),
                .is_free = true,
                .next = null,
            };
        }
    }

    pub fn alloc(size: usize) ?[*]u8 {
        // Align to 8 bytes
        const aligned_size = (size + 7) & ~@as(usize, 7);
        var current = first_block;

        // 1. Search for a free block
        while (current) |block| : (current = block.next) {
            if (block.is_free and block.size >= aligned_size) {
                // If the block is significantly larger, split it
                if (block.size > aligned_size + @sizeOf(BlockHeader) + 16) {
                    const next_ptr = @as(usize, @intFromPtr(block)) + @sizeOf(BlockHeader) + aligned_size;
                    const new_block = @as(*BlockHeader, @ptrFromInt(next_ptr));
                    new_block.* = .{
                        .size = block.size - aligned_size - @sizeOf(BlockHeader),
                        .is_free = true,
                        .next = block.next,
                    };
                    block.size = aligned_size;
                    block.next = new_block;
                }
                block.is_free = false;
                return @as([*]u8, @ptrFromInt(@intFromPtr(block) + @sizeOf(BlockHeader)));
            }
        }

        // 2. Not found? Try to get more pages and link them
        if (pmm.alloc_page()) |addr| {
            const new_block = @as(*BlockHeader, @ptrFromInt(addr));
            new_block.* = .{
                .size = PAGE_SIZE - @sizeOf(BlockHeader),
                .is_free = true,
                .next = null,
            };
            
            // Link to the end of the chain
            var last = first_block;
            while (last.?.next) |n| { last = n; }
            last.?.next = new_block;
            
            // Try allotting again now that we have space
            return alloc(size);
        }

        return null;
    }

    pub fn free(ptr: [*]u8) void {
        const header_ptr = @intFromPtr(ptr) - @sizeOf(BlockHeader);
        const header = @as(*BlockHeader, @ptrFromInt(header_ptr));
        header.is_free = true;
        
        // If GC is on, we might trigger a collection or let the collector handle it
        if (config.USE_GARBAGE_COLLECTOR) {
            garbage_collect();
        } else {
            // Simple immediate coalescing with next block
            coalesce();
        }
    }

    /// Garbage Collector / Memory Cleaner
    /// Merges adjacent free blocks to prevent fragmentation
    pub fn garbage_collect() void {
        if (!config.USE_GARBAGE_COLLECTOR) return;
        
        common.printZ("GC: Running memory cleanup...\n");
        coalesce();
    }

    fn coalesce() void {
        var current = first_block;
        while (current) |block| {
            if (block.is_free) {
                if (block.next) |next_block| {
                    if (next_block.is_free) {
                        // Check if they are physically adjacent
                        const current_end = @intFromPtr(block) + @sizeOf(BlockHeader) + block.size;
                        if (current_end == @intFromPtr(next_block)) {
                            block.size += @sizeOf(BlockHeader) + next_block.size;
                            block.next = next_block.next;
                            // Don't move to next yet, might need to coalesce more
                            continue;
                        }
                    }
                }
            }
            current = block.next;
        }
    }
};
