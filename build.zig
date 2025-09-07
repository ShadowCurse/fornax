const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gen = b.addExecutable(.{
        .name = "gen",
        .root_source_file = b.path("gen/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const rc = b.addRunArtifact(gen);
    const rs = b.step("gen", "Gen");
    rs.dependOn(&rc.step);

    const miniz_config_header = b.addConfigHeader(
        .{ .include_path = "miniz_export.h" },
        .{ .MINIZ_EXPORT = void{} },
    );

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe_mod.addIncludePath(miniz_config_header.getOutput());
    exe_mod.addIncludePath(b.path("thirdparty/volk"));
    exe_mod.addIncludePath(b.path("thirdparty/miniz"));
    exe_mod.addIncludePath(b.path("thirdparty/Vulkan-Headers/include"));
    exe_mod.addCSourceFile(.{ .file = b.path("thirdparty/volk/volk.c") });
    exe_mod.addConfigHeader(miniz_config_header);
    exe_mod.addCSourceFiles(.{
        .files = &.{
            "thirdparty/miniz/miniz.c",
            "thirdparty/miniz/miniz_tdef.c",
            "thirdparty/miniz/miniz_tinfl.c",
            "thirdparty/miniz/miniz_zip.c",
        },
    });

    const exe = b.addExecutable(.{
        .name = "glacier",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .name = "unit_test",
        .root_module = exe_mod,
        .filters = b.args orelse &.{},
    });
    b.installArtifact(exe_unit_tests);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    run_exe_unit_tests.step.dependOn(b.getInstallStep());
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
