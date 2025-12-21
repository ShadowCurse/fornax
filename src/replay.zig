// Copyright (c) 2025 Egor Lazarchuk
// SPDX-License-Identifier: MIT

const std = @import("std");
const build_options = @import("build_options");
const root = @import("root.zig");
const vk = @import("volk");
const log = @import("log.zig");
const args_parser = @import("args_parser.zig");
const parsing = @import("parsing.zig");
const vv = @import("vulkan_validation.zig");
const vulkan = @import("vulkan.zig");
const profiler = @import("profiler.zig");
const control_block = @import("control_block.zig");

const Allocator = std.mem.Allocator;
const Barrier = @import("barrier.zig");
const Database = @import("database.zig");

pub const log_options = log.Options{
    .level = .Info,
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

    parse_inner(PARSE, vv, context) catch unreachable;
}
pub fn parse_inner(comptime P: type, comptime V: type, context: *root.Context) !void {
    var progress = context.progress.start("parsing", 0);
    defer progress.end();

    const work_queue = context.work_queue;
    const shared_alloc = context.shared_alloc;
    const thread_alloc = context.arena.allocator();
    defer _ = context.arena.reset(.retain_capacity);

    var gpa_allocator: std.heap.DebugAllocator(.{}) = .{ .backing_allocator = thread_alloc };
    const gpa_alloc = gpa_allocator.allocator();

    var in_progress: u8 = 0;
    var tasks: root.Tasks = .{};
    for (&tasks.tasks) |*t| t.arena = .init(gpa_alloc);
    while (true) {
        defer progress.completeOne();

        const task = tasks.next();
        if (!task.in_progress) {
            if (work_queue.take_next_parse()) |root_entry| {
                in_progress += 1;
                task.root_entry = root_entry;
                task.in_progress = true;
                task.queue = .empty;
                _ = task.arena.reset(.retain_capacity);
                try task.queue.append(task.arena.allocator(), .{ root_entry.entry, 0 });
            }
        }
        if (in_progress == 0) break;

        const tmp_alloc = task.arena.allocator();
        while (task.queue.pop()) |tuple| {
            const curr_entry, const next_dep = tuple;

            switch (curr_entry.parse(
                P,
                V,
                shared_alloc,
                task.root_entry.arena.allocator(),
                thread_alloc,
                context.db,
                context.validation,
            )) {
                .parsed => {
                    if (next_dep != curr_entry.dependencies.len) {
                        try task.queue.append(tmp_alloc, .{ curr_entry, next_dep + 1 });
                        const dep = curr_entry.dependencies[next_dep];
                        try task.queue.append(tmp_alloc, .{ dep.entry, 0 });
                    }
                },
                .parsing => {
                    try task.queue.append(tmp_alloc, .{ curr_entry, next_dep });
                    break;
                },
                .invalid => {
                    log.debug(
                        @src(),
                        "Encountered invalid entry during parsing {t} 0x{x:0>16}",
                        .{ curr_entry.tag, curr_entry.hash },
                    );
                    curr_entry.decrement_dependencies();
                    for (0..task.queue.items.len) |i| {
                        const e, _ = task.queue.items[task.queue.items.len - i - 1];
                        log.debug(
                            @src(),
                            "Invalidating parent: {t} 0x{x:0>16}",
                            .{ e.tag, e.hash },
                        );
                        e.status.store(.invalid, .seq_cst);
                        e.decrement_dependencies();
                    }
                    control_block.record_failed_entry(task.root_entry.entry.tag);
                    in_progress -= 1;
                    task.in_progress = false;
                    break;
                },
            }
        } else {
            in_progress -= 1;
            task.in_progress = false;
            control_block.record_parsed_entry(task.root_entry.entry.tag);
        }
    }
}

pub fn create(context: *root.Context) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    create_inner(PARSE, CREATE, DESTROY, context) catch unreachable;
}
pub fn create_inner(
    comptime P: type,
    comptime C: type,
    comptime D: type,
    context: *root.Context,
) !void {
    var progress = context.progress.start("creation", 0);
    defer progress.end();

    const work_queue = context.work_queue;
    const thread_alloc = context.arena.allocator();

    var gpa_allocator: std.heap.DebugAllocator(.{}) = .{ .backing_allocator = thread_alloc };
    const gpa_alloc = gpa_allocator.allocator();

    var in_progress: u8 = 0;
    var tasks: root.Tasks = .{};
    for (&tasks.tasks) |*t| t.arena = .init(gpa_alloc);
    while (true) {
        defer progress.completeOne();

        const task = tasks.next();
        if (!task.in_progress) {
            if (work_queue.take_next_create()) |root_entry| {
                in_progress += 1;
                task.root_entry = root_entry;
                task.in_progress = true;
                task.queue = .empty;
                _ = task.arena.reset(.retain_capacity);
                try task.queue.append(task.arena.allocator(), .{ root_entry.entry, 0 });
            }
        }
        if (in_progress == 0) break;

        const tmp_alloc = task.arena.allocator();
        while (task.queue.pop()) |tuple| {
            const curr_entry, const next_dep = tuple;

            switch (curr_entry.create(
                P,
                C,
                tmp_alloc,
                context.db,
                context.validation,
                context.vk_device,
            )) {
                .dependencies => {
                    if (next_dep != curr_entry.dependencies.len) {
                        try task.queue.append(tmp_alloc, .{ curr_entry, next_dep + 1 });
                        const dep = curr_entry.dependencies[next_dep];
                        try task.queue.append(tmp_alloc, .{ dep.entry, 0 });
                    }
                },
                .creating => {
                    try task.queue.append(tmp_alloc, .{ curr_entry, next_dep });
                    break;
                },
                .created => {
                    curr_entry.destroy(D, context.vk_device);
                },
                .invalid => {
                    log.debug(
                        @src(),
                        "Encountered invalid entry during creating {t} 0x{x:0>16}",
                        .{ curr_entry.tag, curr_entry.hash },
                    );
                    curr_entry.destroy_dependencies(D, context.vk_device);
                    for (0..task.queue.items.len) |i| {
                        const e, _ = task.queue.items[task.queue.items.len - i - 1];
                        log.debug(
                            @src(),
                            "Invalidating parent: {t} 0x{x:0>16}",
                            .{ e.tag, e.hash },
                        );
                        e.status.store(.invalid, .release);
                        e.destroy_dependencies(D, context.vk_device);
                    }
                    in_progress -= 1;
                    task.in_progress = false;
                    _ = task.arena.reset(.retain_capacity);
                    break;
                },
            }
        } else {
            in_progress -= 1;
            task.in_progress = false;
            _ = task.arena.reset(.retain_capacity);
            control_block.record_successful_entry(task.root_entry.entry.tag);
        }
    }
}

test "parse" {
    const Dummy = struct {
        fn parse(
            _: Allocator,
            _: Allocator,
            _: *const Database,
            _: []const u8,
        ) parsing.Error!parsing.Result {
            unreachable;
        }
        fn parse_with_dependencies(
            _: Allocator,
            _: Allocator,
            _: *const Database,
            _: []const u8,
        ) parsing.Error!parsing.ResultWithDependencies {
            unreachable;
        }

        fn put_pipelines(
            alloc: Allocator,
            db: *Database,
            data: []const struct {
                hash: u32,
                dependent_by: u32 = 0,
                create_info: ?*align(8) const anyopaque = null,
            },
        ) !void {
            db.entries.getPtr(.graphics_pipeline).deinit(alloc);
            db.entries = .initFill(.empty);
            for (data) |d| {
                try db.entries.getPtr(.graphics_pipeline).put(alloc, d.hash, .{
                    .tag = .graphics_pipeline,
                    .hash = d.hash,
                    .payload_flag = .not_compressed,
                    .payload_crc = 0,
                    .payload_stored_size = 0,
                    .payload_decompressed_size = 0,
                    .payload_file_offset = 0,
                    .status = if (d.create_info != null) .init(.parsed) else .init(.not_parsed),
                    .create_info = d.create_info,
                    .dependent_by = .init(d.dependent_by),
                });
            }
        }

        fn create(_: vk.VkDevice, _: *align(8) const anyopaque) !?*anyopaque {
            unreachable;
        }
        fn destroy(_: vk.VkDevice, _: *const anyopaque) void {
            unreachable;
        }

        fn validate(
            _: *const vv.Extensions,
            _: *const vk.VkRayTracingPipelineCreateInfoKHR,
            _: bool,
        ) bool {
            return true;
        }
    };

    const TestValidate = struct {
        pub const validate_VkSamplerCreateInfo = Dummy.validate;
        pub const validate_VkDescriptorSetLayoutCreateInfo = Dummy.validate;
        pub const validate_VkPipelineLayoutCreateInfo = Dummy.validate;
        pub const validate_VkRenderPassCreateInfo = Dummy.validate;
        pub const validate_VkGraphicsPipelineCreateInfo = Dummy.validate;
        pub const validate_VkComputePipelineCreateInfo = Dummy.validate;
        pub const validate_VkRayTracingPipelineCreateInfoKHR = Dummy.validate;
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var progress = std.Progress.start(.{});
    defer progress.end();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const tmp_file = try tmp_dir.dir.createFile("parse_test", .{});

    // Simple root node with 2 deps
    {
        const TestParse = struct {
            const Global = struct {
                var n: u32 = 0;
                var gp: vk.VkGraphicsPipelineCreateInfo = .{};
            };

            pub const parse_sampler = Dummy.parse;
            pub const parse_descriptor_set_layout = Dummy.parse_with_dependencies;
            pub const parse_pipeline_layout = Dummy.parse_with_dependencies;
            pub const parse_render_pass = Dummy.parse;
            pub const parse_compute_pipeline = Dummy.parse_with_dependencies;
            pub const parse_raytracing_pipeline = Dummy.parse_with_dependencies;
            pub fn parse_graphics_pipeline(
                _: Allocator,
                _: Allocator,
                _: *const Database,
                _: []const u8,
            ) parsing.Error!parsing.ResultWithDependencies {
                defer Global.n += 1;

                var dependencies: []const parsing.Dependency = &.{
                    .{ .tag = .graphics_pipeline, .hash = 1 },
                    .{ .tag = .graphics_pipeline, .hash = 2 },
                };
                if (Global.n != 0) dependencies = &.{};
                return .{
                    .version = 6,
                    .hash = Global.n,
                    .create_info = @ptrCast(&Global.gp),
                    .dependencies = dependencies,
                };
            }
        };

        var db: Database = .{ .file = tmp_file, .entries = .initFill(.empty), .arena = arena };
        try Dummy.put_pipelines(alloc, &db, &.{
            .{ .hash = 1 },
            .{ .hash = 2 },
        });
        var test_entry: Database.Entry = .{
            .tag = .graphics_pipeline,
            .hash = 0,
            .payload_flag = .not_compressed,
            .payload_crc = 0,
            .payload_stored_size = 0,
            .payload_decompressed_size = 0,
            .payload_file_offset = 0,
        };
        var root_entries: [1]root.RootEntry = .{.{ .entry = &test_entry, .arena = .init(alloc) }};
        var work_queue: root.WorkQueue = .{ .entries = &root_entries };
        var validation: vv.Validation = undefined;
        var thread_context: root.Context = .{
            .arena = .init(alloc),
            .shared_alloc = alloc,
            .progress = &progress,
            .barrier = undefined,
            .db = &db,
            .work_queue = &work_queue,
            .thread_count = 1,
            .validation = &validation,
            .vk_device = undefined,
        };
        try parse_inner(TestParse, TestValidate, &thread_context);
        try std.testing.expectEqual(.parsed, test_entry.status.raw);
        const pipelines = db.entries.getPtr(.graphics_pipeline);
        for (pipelines.values()) |*entry| {
            try std.testing.expectEqual(.parsed, entry.status.raw);
            try std.testing.expectEqual(1, entry.dependent_by.raw);
        }
    }

    // Simple root node with 2 deps, one of deps is invalid
    {
        const TestParse = struct {
            const Global = struct {
                var n: u32 = 0;
                var gp: vk.VkGraphicsPipelineCreateInfo = .{};
            };

            pub const parse_sampler = Dummy.parse;
            pub const parse_descriptor_set_layout = Dummy.parse_with_dependencies;
            pub const parse_pipeline_layout = Dummy.parse_with_dependencies;
            pub const parse_render_pass = Dummy.parse;
            pub const parse_compute_pipeline = Dummy.parse_with_dependencies;
            pub const parse_raytracing_pipeline = Dummy.parse_with_dependencies;
            pub fn parse_graphics_pipeline(
                _: Allocator,
                _: Allocator,
                _: *const Database,
                _: []const u8,
            ) parsing.Error!parsing.ResultWithDependencies {
                defer Global.n += 1;

                var dependencies: []const parsing.Dependency = undefined;
                var hash: u32 = undefined;
                switch (Global.n) {
                    0 => {
                        hash = 0;
                        dependencies = &.{
                            .{ .tag = .graphics_pipeline, .hash = 1 },
                            .{ .tag = .graphics_pipeline, .hash = 2 },
                        };
                    },
                    1 => {
                        hash = 1;
                        dependencies = &.{};
                    },
                    2 => {
                        return error.InvalidJson;
                    },
                    else => unreachable,
                }
                return .{
                    .version = 6,
                    .hash = hash,
                    .create_info = @ptrCast(&Global.gp),
                    .dependencies = dependencies,
                };
            }
        };

        var db: Database = .{ .file = tmp_file, .entries = .initFill(.empty), .arena = arena };
        try Dummy.put_pipelines(alloc, &db, &.{
            .{ .hash = 1 },
            .{ .hash = 2 },
        });

        var test_entry: Database.Entry = .{
            .tag = .graphics_pipeline,
            .hash = 0,
            .payload_flag = .not_compressed,
            .payload_crc = 0,
            .payload_stored_size = 0,
            .payload_decompressed_size = 0,
            .payload_file_offset = 0,
        };
        var root_entries: [1]root.RootEntry = .{.{ .entry = &test_entry, .arena = .init(alloc) }};
        var work_queue: root.WorkQueue = .{ .entries = &root_entries };
        var validation: vv.Validation = undefined;
        var thread_context: root.Context = .{
            .arena = .init(alloc),
            .shared_alloc = alloc,
            .progress = &progress,
            .barrier = undefined,
            .db = &db,
            .work_queue = &work_queue,
            .thread_count = 1,
            .validation = &validation,
            .vk_device = undefined,
        };
        try parse_inner(TestParse, TestValidate, &thread_context);
        try std.testing.expectEqual(.invalid, test_entry.status.raw);
        const pipelines = db.entries.getPtr(.graphics_pipeline);
        for (pipelines.values()) |*entry| {
            if (entry.hash == 1) {
                try std.testing.expectEqual(.parsed, entry.status.raw);
                try std.testing.expectEqual(0, entry.dependent_by.raw);
            }
            if (entry.hash == 2) {
                try std.testing.expectEqual(.invalid, entry.status.raw);
                try std.testing.expectEqual(0, entry.dependent_by.raw);
            }
        }
    }

    // Create simple root node with 2 deps
    // Make sure the creation and destruction order is correct
    {
        const Global = struct {
            var create_counter: u32 = 0;
            var destroy_counter: u32 = 0;
            var gp0: u64 = 0xA;
            var gp0_1: u64 = 0;
            var gp0_2: u64 = 0;
            var gp1: u64 = 0xB;
            var gp2: u64 = 0xC;
        };
        const Parse = struct {
            pub const parse_sampler = Dummy.parse;
            pub const parse_shader_module = Dummy.parse;
            pub const parse_descriptor_set_layout = Dummy.parse_with_dependencies;
            pub const parse_pipeline_layout = Dummy.parse_with_dependencies;
            pub const parse_render_pass = Dummy.parse;
            pub const parse_compute_pipeline = Dummy.parse_with_dependencies;
            pub const parse_raytracing_pipeline = Dummy.parse_with_dependencies;
            pub const parse_graphics_pipeline = Dummy.parse_with_dependencies;
        };
        const Create = struct {
            pub const create_vk_sampler = Dummy.create;
            pub const create_descriptor_set_layout = Dummy.create;
            pub const create_pipeline_layout = Dummy.create;
            pub const parse_shader_module = Dummy.create;
            pub const create_shader_module = Dummy.create;
            pub const create_render_pass = Dummy.create;
            pub const create_raytracing_pipeline = Dummy.create;
            pub const create_compute_pipeline = Dummy.create;
            pub fn create_graphics_pipeline(
                _: vk.VkDevice,
                create_info: *align(8) const anyopaque,
            ) !?*anyopaque {
                defer Global.create_counter += 1;
                const c: *const u64 = @ptrCast(create_info);
                switch (Global.create_counter) {
                    0 => try std.testing.expectEqual(0xB, c.*),
                    1 => try std.testing.expectEqual(0xC, c.*),
                    2 => try std.testing.expectEqual(0xA, c.*),
                    else => unreachable,
                }
                return @ptrFromInt(c.*);
            }
        };
        const Destroy = struct {
            pub const destroy_vk_sampler = Dummy.destroy;
            pub const destroy_descriptor_set_layout = Dummy.destroy;
            pub const destroy_pipeline_layout = Dummy.destroy;
            pub const parse_shader_module = Dummy.destroy;
            pub const destroy_shader_module = Dummy.destroy;
            pub const destroy_render_pass = Dummy.destroy;
            pub fn destroy_pipeline(_: vk.VkDevice, handle: *const anyopaque) void {
                defer Global.destroy_counter += 1;
                const c: u64 = @intFromPtr(handle);
                switch (Global.destroy_counter) {
                    0 => std.testing.expectEqual(0xA, c) catch unreachable,
                    1 => std.testing.expectEqual(0xB, c) catch unreachable,
                    2 => std.testing.expectEqual(0xC, c) catch unreachable,
                    else => unreachable,
                }
            }
        };

        var db: Database = .{ .file = tmp_file, .entries = .initFill(.empty), .arena = arena };
        try Dummy.put_pipelines(
            alloc,
            &db,
            &.{
                .{ .hash = 0xB, .dependent_by = 1, .create_info = &Global.gp1 },
                .{ .hash = 0xC, .dependent_by = 1, .create_info = &Global.gp2 },
            },
        );
        var test_entry: Database.Entry = .{
            .tag = .graphics_pipeline,
            .hash = 0xA,
            .payload_flag = .not_compressed,
            .payload_crc = 0,
            .payload_stored_size = 0,
            .payload_decompressed_size = 0,
            .payload_file_offset = 0,
            .status = .init(.parsed),
            .create_info = &Global.gp0,
            .dependencies = &.{
                .{
                    .entry = db.entries.getPtr(.graphics_pipeline).getPtr(0xB).?,
                    .ptr_to_handle = @ptrCast(&Global.gp0_1),
                },
                .{
                    .entry = db.entries.getPtr(.graphics_pipeline).getPtr(0xC).?,
                    .ptr_to_handle = @ptrCast(&Global.gp0_2),
                },
            },
        };
        var root_entries: [1]root.RootEntry = .{.{ .entry = &test_entry, .arena = .init(alloc) }};
        var work_queue: root.WorkQueue = .{ .entries = &root_entries };
        var thread_context: root.Context = .{
            .arena = .init(alloc),
            .shared_alloc = alloc,
            .progress = &progress,
            .barrier = undefined,
            .db = &db,
            .work_queue = &work_queue,
            .thread_count = 1,
            .validation = undefined,
            .vk_device = undefined,
        };
        try create_inner(Parse, Create, Destroy, &thread_context);

        try std.testing.expectEqual(0xB, Global.gp0_1);
        try std.testing.expectEqual(0xC, Global.gp0_2);
        try std.testing.expectEqual(.created, test_entry.status.raw);
        try std.testing.expectEqual(true, test_entry.dependencies_destroyed.raw);
        const pipelines = db.entries.getPtr(.graphics_pipeline);
        for (pipelines.values()) |*entry| {
            try std.testing.expectEqual(.created, entry.status.raw);
            try std.testing.expectEqual(0, entry.dependent_by.raw);
            try std.testing.expectEqual(true, entry.dependencies_destroyed.raw);
        }
    }

    // Create simple root node with 2 deps, but one is uncreatable
    // Make sure the creation and destruction order is correct
    {
        const Global = struct {
            var create_counter: u32 = 0;
            var destroy_counter: u32 = 0;
            var gp0: u64 = 0xA;
            var gp0_1: u64 = 0;
            var gp0_2: u64 = 0;
            var gp1: u64 = 0xB;
            var gp2: u64 = 0xC;
        };
        const Parse = struct {
            pub const parse_sampler = Dummy.parse;
            pub const parse_shader_module = Dummy.parse;
            pub const parse_descriptor_set_layout = Dummy.parse_with_dependencies;
            pub const parse_pipeline_layout = Dummy.parse_with_dependencies;
            pub const parse_render_pass = Dummy.parse;
            pub const parse_compute_pipeline = Dummy.parse_with_dependencies;
            pub const parse_raytracing_pipeline = Dummy.parse_with_dependencies;
            pub const parse_graphics_pipeline = Dummy.parse_with_dependencies;
        };
        const Create = struct {
            pub const create_vk_sampler = Dummy.create;
            pub const create_descriptor_set_layout = Dummy.create;
            pub const create_pipeline_layout = Dummy.create;
            pub const parse_shader_module = Dummy.create;
            pub const create_shader_module = Dummy.create;
            pub const create_render_pass = Dummy.create;
            pub const create_raytracing_pipeline = Dummy.create;
            pub const create_compute_pipeline = Dummy.create;
            pub fn create_graphics_pipeline(
                _: vk.VkDevice,
                create_info: *align(8) const anyopaque,
            ) !?*anyopaque {
                defer Global.create_counter += 1;
                const c: *const u64 = @ptrCast(create_info);
                switch (Global.create_counter) {
                    0 => try std.testing.expectEqual(0xB, c.*),
                    1 => {
                        try std.testing.expectEqual(0xC, c.*);
                        return error.SomeError;
                    },
                    2 => try std.testing.expectEqual(0xA, c.*),
                    else => unreachable,
                }
                return @ptrFromInt(c.*);
            }
        };
        const Destroy = struct {
            pub const destroy_vk_sampler = Dummy.destroy;
            pub const destroy_descriptor_set_layout = Dummy.destroy;
            pub const destroy_pipeline_layout = Dummy.destroy;
            pub const parse_shader_module = Dummy.destroy;
            pub const destroy_shader_module = Dummy.destroy;
            pub const destroy_render_pass = Dummy.destroy;
            pub fn destroy_pipeline(_: vk.VkDevice, handle: *const anyopaque) void {
                defer Global.destroy_counter += 1;
                const c: u64 = @intFromPtr(handle);
                switch (Global.destroy_counter) {
                    0 => std.testing.expectEqual(0xB, c) catch unreachable,
                    else => unreachable,
                }
            }
        };

        var db: Database = .{ .file = tmp_file, .entries = .initFill(.empty), .arena = arena };
        try Dummy.put_pipelines(
            alloc,
            &db,
            &.{
                .{ .hash = 0xB, .dependent_by = 1, .create_info = &Global.gp1 },
                .{ .hash = 0xC, .dependent_by = 1, .create_info = &Global.gp2 },
            },
        );
        var test_entry: Database.Entry = .{
            .tag = .graphics_pipeline,
            .hash = 0xA,
            .payload_flag = .not_compressed,
            .payload_crc = 0,
            .payload_stored_size = 0,
            .payload_decompressed_size = 0,
            .payload_file_offset = 0,
            .status = .init(.parsed),
            .create_info = &Global.gp0,
            .dependencies = &.{
                .{
                    .entry = db.entries.getPtr(.graphics_pipeline).getPtr(0xB).?,
                    .ptr_to_handle = @ptrCast(&Global.gp0_1),
                },
                .{
                    .entry = db.entries.getPtr(.graphics_pipeline).getPtr(0xC).?,
                    .ptr_to_handle = @ptrCast(&Global.gp0_2),
                },
            },
        };
        var root_entries: [1]root.RootEntry = .{.{ .entry = &test_entry, .arena = .init(alloc) }};
        var work_queue: root.WorkQueue = .{ .entries = &root_entries };
        var thread_context: root.Context = .{
            .arena = .init(alloc),
            .shared_alloc = alloc,
            .progress = &progress,
            .barrier = undefined,
            .db = &db,
            .work_queue = &work_queue,
            .thread_count = 1,
            .validation = undefined,
            .vk_device = undefined,
        };
        try create_inner(Parse, Create, Destroy, &thread_context);

        try std.testing.expectEqual(0, Global.gp0_1);
        try std.testing.expectEqual(0, Global.gp0_2);
        try std.testing.expectEqual(.invalid, test_entry.status.raw);
        try std.testing.expectEqual(true, test_entry.dependencies_destroyed.raw);
        const pipelines = db.entries.getPtr(.graphics_pipeline);
        for (pipelines.values()) |*entry| {
            switch (entry.hash) {
                0xB => {
                    try std.testing.expectEqual(.created, entry.status.raw);
                    try std.testing.expectEqual(0, entry.dependent_by.raw);
                    try std.testing.expectEqual(true, entry.dependencies_destroyed.raw);
                },
                0xC => {
                    try std.testing.expectEqual(.invalid, entry.status.raw);
                    try std.testing.expectEqual(0, entry.dependent_by.raw);
                    try std.testing.expectEqual(true, entry.dependencies_destroyed.raw);
                },
                else => unreachable,
            }
        }
    }
}

comptime {
    _ = @import("parsing.zig");
    _ = @import("crc32.zig");
}
