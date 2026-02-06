const common = @import("commands/common.zig");
const acpi = @import("drivers/acpi.zig");

pub const MAX_TASKS = 128;
pub const MAX_CORES = 16;
pub const PRIORITY_LEVELS = 32;

fn get_lapic_id() u8 {
    if (acpi.lapic_addr == 0) return 0;
    var lapic = @as([*]volatile u32, @ptrFromInt(acpi.lapic_addr));
    return @as(u8, @intCast(lapic[0x20 / 4] >> 24));
}

pub const TaskStatus = enum(u8) {
    Ready = 0,
    Running = 1,
    Waiting = 2,
    Dead = 3,
};

/// Process Control Block (PCB)
pub const Task = struct {
    pid: u32,
    name: [16]u8,
    priority: u8,
    status: TaskStatus,
    context_ptr: usize, // Pointer to saved registers on stack
    cpu_affinity: i8, // -1 = any, 0-15 = specific core
    total_ticks: u64 = 0,
    stack_base: usize = 0,
    stack_ptr: usize = 0,
};

const TASK_STACK_SIZE = 16384;
var task_stacks: [MAX_TASKS][TASK_STACK_SIZE]u8 align(4096) = undefined;

/// CPU Control Block (CPCB)
pub const CpuControlBlock = struct {
    id: u32,
    lapic_id: u8,
    is_guardian: bool = false,

    // Bitmask Pyramid: O(1) scheduling
    priority_bitmap: u32 = 0, // Bit n = 1 if priority n has tasks
    task_bitmaps: [32][4]u32 = [_][4]u32{[_]u32{0} ** 4} ** 32, // Support 128 tasks

    current_task: ?*Task = null,
    quantum_remaining: u32 = 0,
    total_tasks: u32 = 0,
    task_count: u32 = 0,

    lock: u32 = 0, // Spinlock for this core's queues
};

// Global Task Pool
pub var task_pool: [MAX_TASKS]Task = undefined;
pub var task_active: [MAX_TASKS]bool = [_]bool{false} ** MAX_TASKS;
pub var next_pid: u32 = 1;

// Per-core Control Blocks
pub var cpcbs: [MAX_CORES]CpuControlBlock = undefined;
pub var detected_cores: u32 = 1;

/// IRQ-Safe Atomic Spinlock
fn spin_lock_irq(lock: *volatile u32) u32 {
    const flags = common.irq_save();
    while (@atomicRmw(u32, lock, .Xchg, 1, .acquire) == 1) {
        asm volatile ("pause");
    }
    return flags;
}

fn spin_unlock_irq(lock: *volatile u32, flags: u32) void {
    @atomicStore(u32, lock, 0, .release);
    common.irq_restore(flags);
}

/// Register a task in the bitmask pyramid
pub fn register_task(core_id: u32, task_idx: u32, priority: u8) void {
    const cpu = &cpcbs[core_id];
    const flags = spin_lock_irq(&cpu.lock);
    defer spin_unlock_irq(&cpu.lock, flags);

    cpu.priority_bitmap |= (@as(u32, 1) << @as(u5, @intCast(priority)));
    const word_idx = task_idx / 32;
    const bit_idx = task_idx % 32;
    cpu.task_bitmaps[priority][word_idx] |= (@as(u32, 1) << @as(u5, @intCast(bit_idx)));
    cpu.task_count += 1;
}

/// Remove a task from the bitmask pyramid
pub fn unregister_task(core_id: u32, task_idx: u32, priority: u8) void {
    const cpu = &cpcbs[core_id];
    const flags = spin_lock_irq(&cpu.lock);
    defer spin_unlock_irq(&cpu.lock, flags);

    const word_idx = task_idx / 32;
    const bit_idx = task_idx % 32;
    cpu.task_bitmaps[priority][word_idx] &= ~(@as(u32, 1) << @as(u5, @intCast(bit_idx)));

    // Check if priority still has tasks
    var any_remaining = false;
    for (cpu.task_bitmaps[priority]) |word| {
        if (word != 0) {
            any_remaining = true;
            break;
        }
    }

    if (!any_remaining) {
        cpu.priority_bitmap &= ~(@as(u32, 1) << @as(u5, @intCast(priority)));
    }
    cpu.task_count -= 1;
}

/// The Hot Path: O(1) Scheduler selection
pub fn scheduler_get_next(core_id: u32) ?*Task {
    const cpu = &cpcbs[core_id];

    const flags = spin_lock_irq(&cpu.lock);

    if (cpu.priority_bitmap == 0) {
        spin_unlock_irq(&cpu.lock, flags);
        return try_steal_task(core_id);
    }

    const highest_prio = 31 - @clz(cpu.priority_bitmap);

    // Find first word with bits
    var word_idx: usize = 0;
    while (word_idx < 4) : (word_idx += 1) {
        if (cpu.task_bitmaps[highest_prio][word_idx] != 0) break;
    }

    const bit_idx = @ctz(cpu.task_bitmaps[highest_prio][word_idx]);
    const task_idx = word_idx * 32 + bit_idx;

    if (task_idx < MAX_TASKS and task_active[task_idx]) {
        // REMOVE from bitmask so nobody else picks it
        cpu.task_bitmaps[highest_prio][word_idx] &= ~(@as(u32, 1) << @as(u5, @intCast(bit_idx)));

        var any_remaining = false;
        for (cpu.task_bitmaps[highest_prio]) |word| {
            if (word != 0) {
                any_remaining = true;
                break;
            }
        }
        if (!any_remaining) {
            cpu.priority_bitmap &= ~(@as(u32, 1) << @as(u5, @intCast(highest_prio)));
        }
        cpu.task_count -= 1;
        spin_unlock_irq(&cpu.lock, flags);
        return &task_pool[task_idx];
    }

    spin_unlock_irq(&cpu.lock, flags);
    return null;
}

/// Called from Timer Interrupt to switch tasks
pub fn scheduler_yield(core_id: u32, current_context_ptr: *usize) void {
    const cpu = &cpcbs[core_id];

    // 1. Save current task state and put back into ready queue
    if (cpu.current_task) |curr| {
        if (curr.status == .Running or curr.status == .Ready) {
            curr.status = .Ready;
            curr.context_ptr = current_context_ptr.*;
            register_task(core_id, @intCast(find_task_idx(curr)), curr.priority);
        }
    }

    // 2. Select next task (this removes it from bitmask)
    const next_task = scheduler_get_next(core_id);

    if (next_task) |next| {
        cpu.current_task = next;
        next.status = .Running;
        cpu.total_tasks += 1;
        current_context_ptr.* = next.context_ptr;
    }
}

fn find_task_idx(task: *Task) usize {
    return (@intFromPtr(task) - @intFromPtr(&task_pool)) / @sizeOf(Task);
}

/// Atomic Work-Stealing
fn try_steal_task(my_id: u32) ?*Task {
    var other_id: u32 = (my_id + 1) % detected_cores;

    while (other_id != my_id) : (other_id = (other_id + 1) % detected_cores) {
        const victim = &cpcbs[other_id];
        if (victim.priority_bitmap == 0) continue;

        const flags = spin_lock_irq(&victim.lock);
        // Re-check after lock
        if (victim.priority_bitmap > 0) {
            // Steal high priority first (bits 16-31)
            const prio_mask = victim.priority_bitmap;
            const target_prio = 31 - @clz(prio_mask);

            // Find first word with task bits
            var word_idx: usize = 0;
            while (word_idx < 4) : (word_idx += 1) {
                if (victim.task_bitmaps[target_prio][word_idx] != 0) break;
            }

            const bit_idx = @ctz(victim.task_bitmaps[target_prio][word_idx]);
            const task_idx = word_idx * 32 + bit_idx;

            victim.task_bitmaps[target_prio][word_idx] &= ~(@as(u32, 1) << @as(u5, @intCast(bit_idx)));

            var any_remaining = false;
            for (victim.task_bitmaps[target_prio]) |word| {
                if (word != 0) {
                    any_remaining = true;
                    break;
                }
            }
            if (!any_remaining) {
                victim.priority_bitmap &= ~(@as(u32, 1) << @as(u5, @intCast(target_prio)));
            }
            victim.task_count -= 1;

            spin_unlock_irq(&victim.lock, flags);
            return &task_pool[task_idx];
        }
        spin_unlock_irq(&victim.lock, flags);
    }
    return null;
}

pub fn init_task(name: []const u8, priority: u8, entry_point: usize, arg: usize) ?u32 {
    // Find empty slot
    var i: usize = 0;
    while (i < MAX_TASKS) : (i += 1) {
        if (!task_active[i]) {
            const task = &task_pool[i];
            task.pid = next_pid;
            next_pid += 1;
            task.priority = priority;
            task.status = .Ready;
            task.cpu_affinity = -1;

            // Set name
            const len = if (name.len > 15) 15 else name.len;
            @memcpy(task.name[0..len], name[0..len]);
            task.name[len] = 0;

            task.stack_base = @intFromPtr(&task_stacks[i]);
            task.stack_ptr = task.stack_base + TASK_STACK_SIZE;

            init_task_context(task, entry_point, arg);

            task_active[i] = true;
            // Initially put all tasks on Core 0 (BSP)
            // They will be stolen by other cores if Core 0 is busy.
            register_task(0, @intCast(i), priority);
            return task.pid;
        }
    }
    return null;
}

/// Called when a task naturally returns from its entry point
pub export fn task_exit() noreturn {
    const lapic_id = get_lapic_id();
    var core_id: u32 = 0;

    // Find our core_id from lapic_id
    var i: u32 = 0;
    while (i < detected_cores) : (i += 1) {
        if (cpcbs[i].lapic_id == lapic_id) {
            core_id = i;
            break;
        }
    }

    const cpu = &cpcbs[core_id];

    if (cpu.current_task) |task| {
        // Find task index
        var found_idx: usize = MAX_TASKS;
        for (0..MAX_TASKS) |task_idx| {
            if (task_active[task_idx] and &task_pool[task_idx] == task) {
                found_idx = task_idx;
                break;
            }
        }

        if (found_idx < MAX_TASKS) {
            task_active[found_idx] = false;
        }
        cpu.current_task = null;
    }

    // Trigger scheduler to pick next task
    while (true) {
        asm volatile ("int $0x30"); // Manually trigger scheduler (0x30 is timer vector)
        asm volatile ("hlt");
    }
}

fn init_task_context(task: *Task, entry: usize, arg: usize) void {
    // 16-byte alignment for SSE/AVX.
    // We want ESP to be (16N - 4) at task entry (after retaddr is pushed).
    // top = 16N.
    // [top-16] = Arg
    // [top-20] = task_exit (Return Address)
    // [top-24] = EFLAGS
    // [top-28] = CS
    // [top-32] = EIP
    // [top-36..top-64] = Regs (8 dwords)

    var sp = @as([*]usize, @ptrFromInt(task.stack_ptr));
    sp -= 4; // top-16

    // 1. Function Arguments
    sp[0] = arg; // [top-16]
    sp -= 1;
    sp[0] = @intFromPtr(&task_exit); // [top-20]

    // 2. Hardware IRET frame
    sp -= 1;
    sp[0] = 0x202; // EFLAGS [top-24]
    sp -= 1;
    sp[0] = 0x08; // CS [top-28]
    sp -= 1;
    sp[0] = entry; // EIP [top-32]

    // 3. Registers (EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX)
    sp -= 1;
    sp[0] = 0; // EAX [top-36]
    sp -= 1;
    sp[0] = 0; // ECX
    sp -= 1;
    sp[0] = 0; // EDX
    sp -= 1;
    sp[0] = 0; // EBX
    sp -= 1;
    sp[0] = task.stack_ptr; // ESP (ignored)
    sp -= 1;
    sp[0] = task.stack_ptr; // EBP
    sp -= 1;
    sp[0] = 0; // ESI
    sp -= 1;
    sp[0] = 0; // EDI [top-64]

    task.context_ptr = @intFromPtr(sp);
}

pub fn perform_aging() void {
    var i: usize = 0;
    while (i < MAX_TASKS) : (i += 1) {
        if (task_active[i] and task_pool[i].priority < 31) {
            const old_prio = task_pool[i].priority;
            const new_prio = old_prio + 1;

            unregister_task(0, @intCast(i), old_prio);
            task_pool[i].priority = new_prio;
            register_task(0, @intCast(i), new_prio);
        }
    }
}
