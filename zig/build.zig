const std = @import("std");

pub fn build(b: *std.Build) void {
    // Target: i386 freestanding (no OS)
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const optimize = .ReleaseSmall;

    // Build the file system module
    const fs_mod = b.createModule(.{
        .root_source_file = b.path("fs.zig"),
        .target = target,
        .optimize = optimize,
    });

    const fs = b.addObject(.{
        .name = "fs",
        .root_module = fs_mod,
    });

    // Build shell commands module
    const shell_mod = b.createModule(.{
        .root_source_file = b.path("shell_cmds.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fs", .module = fs_mod },
        },
    });

    const shell = b.addObject(.{
        .name = "shell_cmds",
        .root_module = shell_mod,
    });

    // Build Nova interpreter module
    const nova_mod = b.createModule(.{
        .root_source_file = b.path("nova.zig"),
        .target = target,
        .optimize = optimize,
    });

    const nova = b.addObject(.{
        .name = "nova",
        .root_module = nova_mod,
    });

    // Install all object files
    const install_fs = b.addInstallArtifact(fs, .{
        .dest_dir = .{ .override = .{ .custom = "../build" } },
    });

    const install_shell = b.addInstallArtifact(shell, .{
        .dest_dir = .{ .override = .{ .custom = "../build" } },
    });

    const install_nova = b.addInstallArtifact(nova, .{
        .dest_dir = .{ .override = .{ .custom = "../build" } },
    });

    b.default_step.dependOn(&install_fs.step);
    b.default_step.dependOn(&install_shell.step);
    b.default_step.dependOn(&install_nova.step);
}
