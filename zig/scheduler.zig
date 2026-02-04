// SMP Task Scheduler
const std = @import("std");
const sync = @import("sync.zig");
const common = @import("commands/common.zig");

pub const TaskStatus = enum {
    Ready,
    Running,
    Done,
};

pub const Task = struct {
    func: *const fn(?*anyopaque) void,
    arg: ?*anyopaque,
    status: TaskStatus = .Ready,
    lock: sync.Spinlock = .{},
    next: ?*Task = null,
};

var queue_lock = sync.Spinlock{};
var task_queue_head: ?*Task = null;
var task_queue_tail: ?*Task = null;

pub fn enqueue(task: *Task) void {
    queue_lock.acquire();
    defer queue_lock.release();

    task.status = .Ready;
    task.next = null;

    if (task_queue_tail) |tail| {
        tail.next = task;
        task_queue_tail = task;
    } else {
        task_queue_head = task;
        task_queue_tail = task;
    }
}

pub fn dequeue() ?*Task {
    queue_lock.acquire();
    defer queue_lock.release();

    if (task_queue_head) |task| {
        task_queue_head = task.next;
        if (task_queue_head == null) {
            task_queue_tail = null;
        }
        return task;
    }
    return null;
}

pub fn schedule_and_wait(func: *const fn(?*anyopaque) void, arg: ?*anyopaque) void {
    var task = Task{
        .func = func,
        .arg = arg,
    };

    enqueue(&task);

    // Wait for completion
    while (@atomicLoad(TaskStatus, &task.status, .seq_cst) != .Done) {
        asm volatile ("pause");
    }
}
