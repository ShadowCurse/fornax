// Copyright (c) 2025 Egor Lazarchuk
// SPDX-License-Identifier: MIT

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const args: Args = .init(b);

    const miniz_mod = create_miniz_module(b, target, optimize);
    const volk_mod = create_volk_module(b, target, optimize);
    const spirv_mod = create_spirv_module(b, target, optimize);

    create_replay_exe(b, target, optimize, &args, miniz_mod, volk_mod, spirv_mod);
    create_exe(
        b,
        target,
        optimize,
        &args,
        "print_entries",
        "src/print_entries.zig",
        &.{
            .{ .name = "miniz", .module = miniz_mod },
            .{ .name = "volk", .module = volk_mod },
        },
    );
    create_exe(
        b,
        target,
        optimize,
        &args,
        "gen",
        "gen/main.zig",
        &.{.{ .name = "volk", .module = volk_mod }},
    );
    create_exe(
        b,
        target,
        optimize,
        &args,
        "vk_registry",
        "gen/vk_registry.zig",
        &.{.{ .name = "volk", .module = volk_mod }},
    );
}

const Args = struct {
    use_llvm: bool,
    profile: bool,
    no_driver: bool,
    disable_shader_cache: bool,
    shader_cache_dir: ?[]const u8,

    const Self = @This();
    fn init(b: *std.Build) Self {
        return .{
            .use_llvm = b.option(bool, "use_llvm", "Use LLVM backend") != null,
            .profile = b.option(bool, "profile", "Enable profiling") != null,
            .no_driver = b.option(bool, "no_driver", "Replace driver calls with stubs") != null,
            .disable_shader_cache = b.option(
                bool,
                "disable_shader_cache",
                "Set MESA_SHADER_CACHE_DISABLE",
            ) != null,
            .shader_cache_dir = b.option(
                []const u8,
                "shader_cache_dir",
                "Set MESA_SHADER_CACHE_DIR",
            ),
        };
    }
};

fn create_replay_exe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    args: *const Args,
    miniz_mod: *std.Build.Module,
    volk_mod: *std.Build.Module,
    spirv_mod: *std.Build.Module,
) void {
    const build_options = b.addOptions();
    build_options.addOption(bool, "profile", args.profile);
    build_options.addOption(bool, "no_driver", args.no_driver);

    const root_mudule = b.createModule(.{
        .root_source_file = b.path("src/replay.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "miniz", .module = miniz_mod },
            .{ .name = "volk", .module = volk_mod },
            .{ .name = "spirv", .module = spirv_mod },
        },
    });
    root_mudule.addOptions("build_options", build_options);

    const exe = b.addExecutable(.{
        .name = "replay",
        .root_module = root_mudule,
        .use_llvm = args.use_llvm,
    });
    const install_step = b.addInstallArtifact(exe, .{});

    const unit_tests = b.addTest(.{
        .name = "replay_unit_test",
        .root_module = root_mudule,
        .filters = b.args orelse &.{},
    });
    const unit_tests_install_step = b.addInstallArtifact(unit_tests, .{});

    const run_cmd = b.addRunArtifact(exe);
    if (args.disable_shader_cache)
        run_cmd.setEnvironmentVariable("MESA_SHADER_CACHE_DISABLE", "1");
    if (args.shader_cache_dir) |scd|
        run_cmd.setEnvironmentVariable("MESA_SHADER_CACHE_DIR", scd);
    if (b.args) |a| run_cmd.addArgs(a);
    run_cmd.step.dependOn(&install_step.step);
    const run_step = b.step("replay_run", "Run the `replay` binary");
    run_step.dependOn(&run_cmd.step);

    const unit_tests_run_cmd = b.addRunArtifact(unit_tests);
    unit_tests_run_cmd.step.dependOn(&unit_tests_install_step.step);
    const test_step = b.step("replay_test", "Run `repaly` unit tests");
    test_step.dependOn(&unit_tests_run_cmd.step);
}

fn create_exe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    args: *const Args,
    comptime name: []const u8,
    source_file: []const u8,
    imports: []const std.Build.Module.Import,
) void {
    const root_mudule = b.createModule(.{
        .root_source_file = b.path(source_file),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    });

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = root_mudule,
        .use_llvm = args.use_llvm,
    });
    const install_step = b.addInstallArtifact(exe, .{});

    const unit_tests = b.addTest(.{
        .name = name ++ "_unit_test",
        .root_module = root_mudule,
        .filters = b.args orelse &.{},
    });
    const unit_tests_install_step = b.addInstallArtifact(unit_tests, .{});

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |a| run_cmd.addArgs(a);
    run_cmd.step.dependOn(&install_step.step);
    const run_step = b.step(name ++ "_run", "Run the `" ++ name ++ "` binary");
    run_step.dependOn(&run_cmd.step);

    const unit_tests_run_cmd = b.addRunArtifact(unit_tests);
    unit_tests_run_cmd.step.dependOn(&unit_tests_install_step.step);
    const test_step = b.step(name ++ "_test", "Run `" ++ name ++ "` unit tests");
    test_step.dependOn(&unit_tests_run_cmd.step);
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

pub fn create_spirv_module(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const spirv_c = b.addWriteFiles().add("translate_spirv.h",
        \\#include "spirv.h"
    );
    const spirv_translate = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = spirv_c,
    });
    spirv_translate.addIncludePath(b.path("thirdparty/SPIRV-Headers/include/spirv/unified1"));
    const spirv_mod = b.createModule(.{
        .root_source_file = spirv_translate.getOutput(),
        .target = target,
        .optimize = optimize,
    });
    return spirv_mod;
}
