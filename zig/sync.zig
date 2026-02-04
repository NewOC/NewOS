// Spinlock implementation for SMP synchronization
const std = @import("std");

pub const Spinlock = struct {
    lock: u32 = 0,

    pub fn acquire(self: *Spinlock) void {
        while (@atomicRmw(u32, &self.lock, .Xchg, 1, .seq_cst) != 0) {
            asm volatile ("pause");
        }
    }

    pub fn release(self: *Spinlock) void {
        @atomicStore(u32, &self.lock, 0, .seq_cst);
    }

    pub fn is_locked(self: *Spinlock) bool {
        return @atomicLoad(u32, &self.lock, .seq_cst) != 0;
    }
};
