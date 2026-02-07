const memory = @import("../memory.zig");
const common = @import("common.zig");

pub fn ArrayList(comptime T: type) type {
    return struct {
        items: []T,
        len: usize,
        capacity: usize,

        const Self = @This();

        pub fn init() Self {
            return .{
                .items = &[_]T{},
                .len = 0,
                .capacity = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.capacity > 0) {
                memory.heap.free(@ptrCast(self.items.ptr));
            }
            self.* = init();
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) bool {
            if (new_capacity <= self.capacity) return true;

            var actual_new_cap = if (self.capacity == 0) 8 else self.capacity;
            while (actual_new_cap < new_capacity) actual_new_cap *= 2;

            const new_ptr = memory.heap.alloc(actual_new_cap * @sizeOf(T)) orelse return false;
            const new_slice = @as([*]T, @ptrCast(new_ptr))[0..actual_new_cap];

            if (self.len > 0) {
                for (0..self.len) |i| {
                    new_slice[i] = self.items[i];
                }
                memory.heap.free(@ptrCast(self.items.ptr));
            }

            self.items = new_slice;
            self.capacity = actual_new_cap;
            return true;
        }

        pub fn append(self: *Self, item: T) bool {
            if (!self.ensureTotalCapacity(self.len + 1)) return false;
            self.items[self.len] = item;
            self.len += 1;
            return true;
        }
    };
}

pub fn hashStr(str: []const u8) u32 {
    // DJB2 hash
    var hash: u32 = 5381;
    for (str) |c| {
        hash = ((hash << 5) +% hash) +% @as(u32, c);
    }
    return hash;
}

pub fn HashTable(comptime V: type) type {
    return struct {
        pub const Entry = struct {
            key: []const u8,
            value: V,
            used: bool = false,
        };

        entries: []Entry,
        len: usize,
        capacity: usize,

        const Self = @This();

        pub fn init() Self {
            return .{
                .entries = &[_]Entry{},
                .len = 0,
                .capacity = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.capacity > 0) {
                // We should also free the keys if they were allocated,
                // but usually keys are slices from the source or persistent strings.
                memory.heap.free(@ptrCast(self.entries.ptr));
            }
            self.* = init();
        }

        pub fn put(self: *Self, key: []const u8, value: V) bool {
            if (self.capacity == 0 or (self.len * 100 / self.capacity) >= 70) {
                if (!self.grow()) return false;
            }

            const h = hashStr(key);
            var idx = h % self.capacity;

            while (self.entries[idx].used) {
                if (common.streq(self.entries[idx].key, key)) {
                    self.entries[idx].value = value;
                    return true;
                }
                idx = (idx + 1) % self.capacity;
            }

            self.entries[idx] = .{
                .key = key,
                .value = value,
                .used = true,
            };
            self.len += 1;
            return true;
        }

        pub fn get(self: Self, key: []const u8) ?V {
            if (self.capacity == 0) return null;

            const h = hashStr(key);
            var idx = h % self.capacity;
            const start_idx = idx;

            while (self.entries[idx].used) {
                if (common.streq(self.entries[idx].key, key)) {
                    return self.entries[idx].value;
                }
                idx = (idx + 1) % self.capacity;
                if (idx == start_idx) break;
            }

            return null;
        }

        pub fn contains(self: Self, key: []const u8) bool {
            return self.get(key) != null;
        }

        fn grow(self: *Self) bool {
            const new_capacity = if (self.capacity == 0) 16 else self.capacity * 2;
            const new_ptr = memory.heap.alloc(new_capacity * @sizeOf(Entry)) orelse return false;
            const new_entries = @as([*]Entry, @ptrCast(new_ptr))[0..new_capacity];

            for (0..new_capacity) |i| {
                new_entries[i] = .{ .key = "", .value = undefined, .used = false };
            }

            const old_entries = self.entries;
            const old_capacity = self.capacity;

            self.entries = new_entries;
            self.capacity = new_capacity;
            self.len = 0;

            if (old_capacity > 0) {
                for (old_entries) |entry| {
                    if (entry.used) {
                        _ = self.put(entry.key, entry.value);
                    }
                }
                memory.heap.free(@ptrCast(old_entries.ptr));
            }

            return true;
        }
    };
}
