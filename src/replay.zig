// Copyright (c) 2026 Egor Lazarchuk
// SPDX-License-Identifier: MIT

const std = @import("std");
const build_options = @import("build_options");
const root = @import("root.zig");
const log = @import("log.zig");
const args_parser = @import("args_parser.zig");
const parsing = @import("parsing.zig");
const profiler = @import("profiler.zig");
const control_block = @import("control_block.zig");

const vk = @import("vk.zig");
const vv = @import("vk_validation.zig");
const vulkan = @import("vulkan.zig");

const Allocator = std.mem.Allocator;
const Barrier = @import("barrier.zig");
const Database = @import("database.zig");

pub const log_options = log.Options{
    .level = .info,
};

pub const profiler_options = profiler.Options{
    .enabled = build_options.profile,
};

pub const MEASUREMENTS = profiler.Measurements("main", &.{
    "main",
    "process",
    "parse",
    "create",
});

const ALL_MEASUREMENTS = &.{
    MEASUREMENTS,
    parsing.MEASUREMENTS,
    vulkan.MEASUREMENTS,
    Database.MEASUREMENTS,
};

const Args = struct {
    help: bool = false,
    device_index: ?u32 = null,
    enable_validation: bool = false,
    spirv_val: bool = false,
    on_disk_pipeline_cache: ?[]const u8 = null,
    on_disk_validation_cache: ?[]const u8 = null,
    on_disk_validation_blacklist: ?[]const u8 = null,
    on_disk_validation_whitelist: ?[]const u8 = null,
    on_disk_replay_whitelist: ?[]const u8 = null,
    on_disk_replay_whitelist_mask: ?[]const u8 = null,
    num_threads: ?u32 = null,
    loop: ?u32 = null,
    pipeline_hash: ?u32 = null,
    graphics_pipeline_range: ?u32 = null,
    compute_pipeline_range: ?u32 = null,
    raytracing_pipeline_range: ?u32 = null,
    enable_pipeline_stats: ?[]const u8 = null,
    on_disk_module_identifier: ?[]const u8 = null,
    quiet_slave: bool = false,
    master_process: bool = false,
    slave_process: bool = false,
    progress: bool = false,
    shmem_fd: ?std.posix.fd_t = null,
    control_fd: ?std.posix.fd_t = null,
    shader_cache_size: ?u32 = null,
    // Deprecated
    ignore_derived_pipelines: void = {},
    log_memory: bool = false,
    null_device: bool = false,
    timeout_seconds: ?u32 = null,
    implicit_whitelist: ?u32 = null,
    replayer_cache: ?[]const u8 = null,
    disable_signal_handler: bool = false,
    disable_rate_limiter: bool = false,
    database_paths: args_parser.RemainingArgs = .{},
};

pub fn main() !void {
    profiler.start_measurement();
    defer profiler.print(ALL_MEASUREMENTS);
    defer profiler.end_measurement();

    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena_alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const tmp_alloc = tmp_arena.allocator();

    const args = try args_parser.parse(Args, arena_alloc);

    if (std.posix.getenv("GLACIER_LOG_PATH")) |log_path| {
        const log_file = try std.fs.createFileAbsolute(log_path, .{});
        log.output_fd = log_file.handle;
        args_parser.print_args(args);
    }

    if (args.help or args.database_paths.values.len == 0) {
        args_parser.print_help(Args);
        return;
    }

    const db_path = std.mem.span(args.database_paths.values[0]);
    var db: Database = try .init(tmp_alloc, db_path);
    _ = tmp_arena.reset(.retain_capacity);

    const thread_count = root.actual_thread_count(args.num_threads);
    log.info(@src(), "Using {d} threads", .{thread_count});

    if (args.shmem_fd) |shmem_fd| try control_block.init(shmem_fd, &db, thread_count);

    var validation: vv.Validation = undefined;
    const vk_device = try vulkan.init(
        arena_alloc,
        tmp_alloc,
        &db,
        args.enable_validation,
        &validation,
    );
    _ = tmp_arena.reset(.retain_capacity);

    const root_entries = try root.init_root_entries(arena_alloc, &db);
    var work_queue: root.WorkQueue = .{ .entries = root_entries };

    var progress = std.Progress.start(.{});
    defer progress.end();
    var progress_root = progress.start("processing", 0);
    defer progress_root.end();

    var shared_arena: std.heap.ThreadSafeAllocator = .{ .child_allocator = db.arena.allocator() };
    const shared_alloc = shared_arena.allocator();
    var barrier: Barrier = .{ .total_threads = thread_count };
    const contexts = try root.init_contexts(
        arena_alloc,
        shared_alloc,
        &progress_root,
        &barrier,
        &db,
        &work_queue,
        thread_count,
        &validation,
        vk_device,
    );
    // Reuse already existing arena
    contexts[0].arena = tmp_arena;

    const secondary_threads = try root.spawn_threads(
        arena_alloc,
        secondary_thread_process,
        contexts[1..],
    );
    process(&contexts[0]);
    for (secondary_threads) |st| st.join();

    // Don't set the completion because otherwise Steam will remember that everything
    // is replayed and will not try to replay shaders again.
    // if (control_block) |cb|
    //     cb.progress_complete.store(1, .release);

    var total_used_bytes = arena.queryCapacity() + db.arena.queryCapacity();
    for (contexts) |*c| total_used_bytes += c.arena.queryCapacity();
    log.info(@src(), "Total allocators memory: {d}MB", .{total_used_bytes / 1024 / 1024});
    const rusage = std.posix.getrusage(0);
    log.info(@src(), "Resource usage: max rss: {d}MB minor faults: {d} major faults: {d}", .{
        @as(usize, @intCast(rusage.maxrss)) / 1024,
        rusage.minflt,
        rusage.majflt,
    });
}

pub fn secondary_thread_process(context: *root.Context) void {
    profiler.start_measurement();
    defer profiler.end_measurement();

    process(context);
}

pub fn process(context: *root.Context) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    parse(context);
    context.barrier.wait();
    create(context);
}

const DryCreate = struct {
    const Self = @This();

    pub const create_vk_sampler = Self.create;
    pub const create_descriptor_set_layout = Self.create;
    pub const create_pipeline_layout = Self.create;
    pub const parse_shader_module = Self.create;
    pub const create_shader_module = Self.create;
    pub const create_render_pass = Self.create;
    pub const create_raytracing_pipeline = Self.create;
    pub const create_compute_pipeline = Self.create;
    pub const create_graphics_pipeline = Self.create;

    fn create(vk_device: vk.VkDevice, create_info: *align(8) const anyopaque) !?*anyopaque {
        var result: *anyopaque = @ptrFromInt(0x69);
        asm volatile (""
            :
            : [vk_device] "r" (vk_device),
            : .{ .memory = true });
        asm volatile (""
            :
            : [create_info] "r" (create_info),
            : .{ .memory = true });
        asm volatile (""
            : [result] "=r" (result),
        );
        return result;
    }
};

const DryDestroy = struct {
    const Self = @This();

    pub const destroy_vk_sampler = Self.destroy;
    pub const destroy_descriptor_set_layout = Self.destroy;
    pub const destroy_pipeline_layout = Self.destroy;
    pub const parse_shader_module = Self.destroy;
    pub const destroy_shader_module = Self.destroy;
    pub const destroy_render_pass = Self.destroy;
    pub const destroy_pipeline = Self.destroy;

    fn destroy(vk_device: vk.VkDevice, handle: *const anyopaque) void {
        asm volatile (""
            :
            : [vk_device] "r" (vk_device),
        );
        asm volatile (""
            :
            : [handle] "r" (handle),
        );
    }
};

const PARSE = parsing;
const CREATE = if (build_options.no_driver) DryCreate else vulkan;
const DESTROY = if (build_options.no_driver) DryDestroy else vulkan;

pub fn parse(context: *root.Context) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    root.parse(PARSE, vv, context) catch unreachable;
}

pub fn create(context: *root.Context) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    root.create(PARSE, CREATE, DESTROY, context) catch unreachable;
}

comptime {
    _ = @import("parsing.zig");
    _ = @import("crc32.zig");
    _ = @import("root.zig");
}
