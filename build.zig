const std = @import("std");

pub fn build(b: *std.Build) !void {
    const check = b.step("check", "");
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "pb_test",
        .root_source_file = b.path("src/pb_test.zig"),
        .target = target,
        .optimize = opt,
    });
    const check_exe = try b.allocator.create(std.Build.Step.Compile);
    check_exe.* = exe.*;
    check.dependOn(&check_exe.step);
    b.installArtifact(exe);
}
