// Copyright (c) 2025 Egor Lazarchuk
// SPDX-License-Identifier: MIT

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const miniz_mod = create_miniz_module(b, target, optimize);
    const volk_mod = create_volk_module(b, target, optimize);

    create_gen_exe(b, target, optimize, volk_mod);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "miniz", .module = miniz_mod },
            .{ .name = "volk", .module = volk_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "glacier",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
    {
        const run_cmd = b.addRunArtifact(exe);
        if (b.option(bool, "use_radv", "Use RADV driver") == null) {
            run_cmd.setEnvironmentVariable("AMD_VULKAN_ICD", "RADV");
        }
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

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

pub fn create_gen_exe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    volk_mod: *std.Build.Module,
) void {
    const gen_mod = b.createModule(.{
        .root_source_file = b.path("gen/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "volk", .module = volk_mod },
        },
    });

    const exe_unit_tests = b.addTest(.{
        .name = "gen_unit_test",
        .root_module = gen_mod,
        .filters = b.args orelse &.{},
    });
    b.installArtifact(exe_unit_tests);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    run_exe_unit_tests.step.dependOn(b.getInstallStep());
    const test_step = b.step("gen_test", "Run gen unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const gen = b.addExecutable(.{
        .name = "gen",
        .root_module = gen_mod,
    });
    b.installArtifact(gen);

    const run_cmd = b.addRunArtifact(gen);
    const run_step = b.step("gen", "Gen");
    run_step.dependOn(&run_cmd.step);
}

pub fn create_miniz_module(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const miniz_config_header = b.addConfigHeader(
        .{ .include_path = "miniz_export.h" },
        .{ .MINIZ_EXPORT = void{} },
    );
    const miniz_c = b.addWriteFiles().add("translate_miniz.h",
        \\#define MINIZ_EXPORT
        \\#define MINIZ_NO_STDIO
        \\#define MINIZ_NO_MALLOC
        \\#define MINIZ_NO_ARCHIVE_APIS
        \\#define MINIZ_NO_DEFLATE_APIS
        \\#define MINIZ_LITTLE_ENDIAN 1
        \\#define MINIZ_HAS_64BIT_REGISTERS 1
        \\#include "miniz.h"
    );
    const miniz_translate = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = miniz_c,
    });
    miniz_translate.addConfigHeader(miniz_config_header);
    miniz_translate.addIncludePath(b.path("thirdparty/miniz"));
    const miniz_mod = b.createModule(.{
        .root_source_file = miniz_translate.getOutput(),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    miniz_mod.addConfigHeader(miniz_config_header);
    miniz_mod.addIncludePath(b.path("thirdparty/miniz"));
    miniz_mod.addCSourceFiles(.{
        .files = &.{
            "thirdparty/miniz/miniz.c",
            "thirdparty/miniz/miniz_tdef.c",
            "thirdparty/miniz/miniz_tinfl.c",
            "thirdparty/miniz/miniz_zip.c",
        },
    });
    return miniz_mod;
}

pub fn create_volk_module(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const volk_c = b.addWriteFiles().add("translate_volk.h",
        \\#include "volk.h"
    );
    const volk_translate = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = volk_c,
    });
    volk_translate.addIncludePath(b.path("thirdparty/volk"));
    volk_translate.addIncludePath(b.path("thirdparty/Vulkan-Headers/include"));
    const volk_mod = b.createModule(.{
        .root_source_file = volk_translate.getOutput(),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    volk_mod.addIncludePath(b.path("thirdparty/volk"));
    volk_mod.addIncludePath(b.path("thirdparty/Vulkan-Headers/include"));
    volk_mod.addCSourceFile(.{ .file = b.path("thirdparty/volk/volk.c") });
    return volk_mod;
}
