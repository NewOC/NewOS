const shell_cmds = @import("shell_cmds.zig");
const keyboard_isr = @import("keyboard_isr.zig");
const common = @import("commands/common.zig");
const shell = @import("shell.zig");
const timer = @import("drivers/timer.zig");
const acpi = @import("drivers/acpi.zig");
const memory = @import("memory.zig");
const exceptions = @import("exceptions.zig");
const smp = @import("smp.zig");
const scheduler = @import("scheduler.zig");

comptime {
    _ = shell_cmds;
    _ = keyboard_isr;
    _ = shell;
    _ = timer;
    _ = acpi;
    _ = memory;
    _ = exceptions;
    _ = smp;
    _ = scheduler;
    _ = @import("drivers/vga.zig");
}

extern fn read_command() void;
extern fn execute_command() void;

export fn kernel_panic(msg_ptr: [*]const u8, msg_len: usize) noreturn {
    exceptions.panic(msg_ptr[0..msg_len]);
}

pub fn panic(msg: []const u8) noreturn {
    exceptions.panic(msg);
}

fn shell_task_wrapper() callconv(.c) void {
    while (true) {
        read_command();
        execute_command();
    }
}

export fn kmain() noreturn {
    // 1. Memory and Core initialization
    memory.pmm.init();
    memory.heap.init();
    memory.init_paging();
    smp.init_sse();

    shell_cmds.zig_init();
    timer.init();
    _ = acpi.init();

    // 2. Initialize RT Scheduler Infrastructure
    smp.init();

    // 3. Spawn Shell as high-priority task (Priority 24)
    _ = smp.spawn("Shell", 24, @intFromPtr(&shell_task_wrapper), 0);

    common.printZ("OS as Process: Shell spawned. Entering scheduler...\n");

    // Enable interrupts so LAPIC timer can trigger switches
    asm volatile ("sti");

    // Manually start the Shell on the BSP (Core 0)
    if (scheduler.scheduler_get_next(0)) |task| {
        smp.run_task(0, task);
    }

    while (true) {
        asm volatile ("hlt");
    }
}
