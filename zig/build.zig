const std = @import("std");

pub fn build(b: *std.Build) void {
    // Target: i386 freestanding (no OS)
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
    });

    // Build the file system module
    const fs = b.addObject(.{
        .name = "fs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("fs.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
        }),
    });

    // Output object file
    const install = b.addInstallArtifact(fs, .{
        .dest_dir = .{ .override = .{ .custom = "../build" } },
    });

    b.default_step.dependOn(&install.step);
}
