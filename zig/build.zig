const std = @import("std");

pub fn build(b: *std.Build) void {
    // Target: i386 freestanding (no OS)
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
        .cpu_features_sub = std.Target.x86.featureSet(&[_]std.Target.x86.Feature{
            .mmx,
            .sse,
            .sse2,
            .sse3,
            .ssse3,
            .sse4_1,
            .sse4_2,
            .avx,
            .avx2,
        }),
    });

    const optimize = .ReleaseSmall;

    // Create the kernel module first
    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("kernel.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build options
    const history_size = b.option(u32, "history_size", "Number of commands to keep in history");
    const options = b.addOptions();
    options.addOption(?u32, "history_size", history_size);
    kernel_mod.addOptions("build_config", options);

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
