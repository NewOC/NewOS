const std = @import("std");

pub fn build(b: *std.Build) void {
    // Target: i386 freestanding (no OS)
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
    });

    const optimize = .ReleaseSmall;

    // Create the kernel module first
    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("kernel.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build the kernel object file
    const kernel = b.addObject(.{
        .name = "kernel",
        .root_module = kernel_mod,
    });

    // Install the object file to ../build
    const install_kernel = b.addInstallArtifact(kernel, .{
        .dest_dir = .{ .override = .{ .custom = "../build" } },
    });

    b.default_step.dependOn(&install_kernel.step);
}
