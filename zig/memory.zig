// NewOS Memory Management Module - Advanced Edition
const common = @import("commands/common.zig");
const config = @import("config.zig");

pub const PAGE_SIZE = 4096;
pub const MAX_MEMORY = 128 * 1024 * 1024; // 128MB
pub const TOTAL_PAGES = MAX_MEMORY / PAGE_SIZE;
pub const BITMAP_SIZE = TOTAL_PAGES / 8;

extern const ebss: anyopaque;

var bitmap: [BITMAP_SIZE]u8 = [_]u8{0} ** BITMAP_SIZE;
var last_free_page: u32 = 0;

pub const PageDirectoryEntry = u32;
pub const PageTableEntry = u32;

pub const PDE_PRESENT = 0x01;
pub const PDE_RW = 0x02;
pub const PDE_USER = 0x04;

pub const PTE_PRESENT = 0x01;
pub const PTE_RW = 0x02;
pub const PTE_USER = 0x04;

pub var page_directory: *[1024]PageDirectoryEntry = undefined;

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

pub fn init_paging() void {
    // 1. Allocate Page Directory
    if (pmm.alloc_page()) |pd_addr| {
        page_directory = @ptrFromInt(pd_addr);
        @memset(@as([*]u8, @ptrCast(page_directory))[0..4096], 0);

        // 2. Setup first Page Tables (Identity Map 0-8MB)
        // This covers Kernel, Stack, VGA, and enough room for PTs
        var pt_idx: usize = 0;
        while (pt_idx < 2) : (pt_idx += 1) {
            if (pmm.alloc_page()) |pt_addr| {
                const pt: *[1024]PageTableEntry = @ptrFromInt(pt_addr);
                var i: u32 = 0;
                while (i < 1024) : (i += 1) {
                    pt[i] = (@as(u32, @intCast(pt_idx)) * 1024 * PAGE_SIZE + i * PAGE_SIZE) | PTE_PRESENT | PTE_RW;
                }
                page_directory[pt_idx] = pt_addr | PDE_PRESENT | PDE_RW;
            }
        }

            // 3. Enable Paging
            asm volatile ("mov %[addr], %%cr3" : : [addr] "r" (pd_addr));
            asm volatile (
                \\mov %cr0, %eax
                \\or $0x80000000, %eax
                \\mov %eax, %cr0
            );
        }
    }
}

pub fn map_page(vaddr: usize, paddr: usize) bool {
    const pd_idx = vaddr >> 22;
    const pt_idx = (vaddr >> 12) & 0x3FF;

    if ((page_directory[pd_idx] & PDE_PRESENT) == 0) {
        if (pmm.alloc_page()) |new_pt_addr| {
            const pt_ptr: [*]u8 = @ptrFromInt(new_pt_addr);
            @memset(pt_ptr[0..4096], 0);
            page_directory[pd_idx] = @as(u32, @intCast(new_pt_addr)) | PDE_PRESENT | PDE_RW;
        } else return false;
    }

    const pt_addr = page_directory[pd_idx] & ~@as(u32, 0xFFF);
    const pt: *[1024]PageTableEntry = @ptrFromInt(pt_addr);
    pt[pt_idx] = @as(u32, @intCast(paddr & ~@as(u32, 0xFFF))) | PTE_PRESENT | PTE_RW;

    // Invalidate TLB for this page
    asm volatile ("invlpg (%[addr])" : : [addr] "r" (vaddr) : "memory");
    return true;
}

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
