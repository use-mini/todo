const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_flags = [_][]const u8{
        "-DSQLITE_THREADSAFE=1",
        "-DSQLITE_DEFAULT_MEMSTATUS=0",
        "-DSQLITE_DQS=0",
    };

    const sqlite_dep = b.dependency("sqlite", .{});

    const exe = b.addExecutable(.{
        .name = "todo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.link_libc = true;
    exe.root_module.addCSourceFile(.{
        .file = sqlite_dep.path("sqlite3.c"),
        .flags = &sqlite_flags,
    });
    exe.root_module.addIncludePath(sqlite_dep.path("."));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run todo");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.link_libc = true;
    unit_tests.root_module.addCSourceFile(.{
        .file = sqlite_dep.path("sqlite3.c"),
        .flags = &sqlite_flags,
    });
    unit_tests.root_module.addIncludePath(sqlite_dep.path("."));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
