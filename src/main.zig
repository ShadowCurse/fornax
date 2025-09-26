// Copyright (c) 2025 Egor Lazarchuk
//
// Based in part on Fossilize project which is:
// Copyright (c) 2025 Hans-Kristian Arntzen
//
// SPDX-License-Identifier: MIT

const std = @import("std");
const vk = @import("volk");
const log = @import("log.zig");
const args_parser = @import("args_parser.zig");
const parsing = @import("parsing.zig");
const vu = @import("vulkan_utils.zig");
const vulkan = @import("vulkan.zig");
const Database = @import("database.zig");

const Allocator = std.mem.Allocator;

pub const log_options = log.Options{
    .level = .Info,
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
    shmem_fd: ?i32 = null,
    control_fd: ?i32 = null,
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

pub fn log_args(args: *const Args) void {
    log.info(@src(), "Args:", .{});
    log.info(@src(), "help: {}", .{args.help});
    log.info(@src(), "device_index: {?}", .{args.device_index});
    log.info(@src(), "enable_validation: {}", .{args.enable_validation});
    log.info(@src(), "spirv_val: {}", .{args.spirv_val});
    log.info(@src(), "on_disk_pipeline_cache: {?s}", .{args.on_disk_pipeline_cache});
    log.info(@src(), "on_disk_validation_cache: {?s}", .{args.on_disk_validation_cache});
    log.info(@src(), "on_disk_validation_blacklist: {?s}", .{args.on_disk_validation_blacklist});
    log.info(@src(), "on_disk_validation_whitelist: {?s}", .{args.on_disk_validation_whitelist});
    log.info(@src(), "on_disk_replay_whitelist: {?s}", .{args.on_disk_replay_whitelist});
    log.info(@src(), "on_disk_replay_whitelist_mask: {?s}", .{args.on_disk_replay_whitelist_mask});
    log.info(@src(), "num_threads: {?}", .{args.num_threads});
    log.info(@src(), "loop: {?}", .{args.loop});
    log.info(@src(), "pipeline_hash: {?}", .{args.pipeline_hash});
    log.info(@src(), "graphics_pipeline_range: {?}", .{args.graphics_pipeline_range});
    log.info(@src(), "compute_pipeline_range: {?}", .{args.compute_pipeline_range});
    log.info(@src(), "raytracing_pipeline_range: {?}", .{args.raytracing_pipeline_range});
    log.info(@src(), "enable_pipeline_stats: {?s}", .{args.enable_pipeline_stats});
    log.info(@src(), "on_disk_module_identifier: {?s}", .{args.on_disk_module_identifier});
    log.info(@src(), "quiet_slave: {}", .{args.quiet_slave});
    log.info(@src(), "master_process: {}", .{args.master_process});
    log.info(@src(), "slave_process: {}", .{args.slave_process});
    log.info(@src(), "progress: {}", .{args.progress});
    log.info(@src(), "shmem_fd: {?}", .{args.shmem_fd});
    log.info(@src(), "control_fd: {?}", .{args.control_fd});
    log.info(@src(), "shader_cache_size: {?}", .{args.shader_cache_size});
    log.info(@src(), "log_memory: {}", .{args.log_memory});
    log.info(@src(), "null_device: {}", .{args.null_device});
    log.info(@src(), "timeout_seconds: {?}", .{args.timeout_seconds});
    log.info(@src(), "implicit_whitelist: {?}", .{args.implicit_whitelist});
    log.info(@src(), "replayer_cache: {?s}", .{args.replayer_cache});
    log.info(@src(), "disable_signal_handler: {}", .{args.disable_signal_handler});
    log.info(@src(), "disable_rate_limiter: {}", .{args.disable_rate_limiter});
    log.info(@src(), "databases:", .{});
    for (args.database_paths.values) |p|
        log.info(@src(), "{s}", .{p});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena_alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const tmp_alloc = tmp_arena.allocator();

    const args = try args_parser.parse(Args, arena_alloc);

    if (std.posix.getenv("GLACIER_LOG_PATH")) |log_path| {
        const log_file = try std.fs.createFileAbsolute(log_path, .{});
        log.output_fd = log_file.handle;
        log_args(&args);
    }

    if (args.help or args.database_paths.values.len == 0) {
        try args_parser.print_help(Args);
        return;
    }

    if (args.shmem_fd) |shmem_fd|
        try open_control_block(shmem_fd);

    var progress = std.Progress.start(.{});
    defer progress.end();

    var progress_root = progress.start("glacier", 0);
    defer progress_root.end();

    const db_path = std.mem.span(args.database_paths.values[0]);

    var db: Database = try .init(tmp_alloc, &progress_root, db_path);
    _ = tmp_arena.reset(.retain_capacity);

    if (control_block) |cb| {
        const graphics: u32 =
            @intCast(db.entries.getPtrConst(.graphics_pipeline).values().len);
        cb.static_total_count_graphics.store(graphics, .release);
        const compute: u32 =
            @intCast(db.entries.getPtrConst(.compute_pipeline).values().len);
        cb.static_total_count_compute.store(compute, .release);
        const raytracing: u32 =
            @intCast(db.entries.getPtrConst(.raytracing_pipeline).values().len);
        cb.static_total_count_raytracing.store(raytracing, .release);

        cb.num_running_processes.store(args.num_threads.? + 1, .release);
        cb.num_processes_memory_stats.store(args.num_threads.? + 1, .release);

        cb.progress_started.store(1, .release);
    }

    const app_infos = db.entries.getPtrConst(.application_info).values();
    if (app_infos.len == 0)
        return error.NoApplicationInfoInTheDatabase;
    const app_info_entry = &app_infos[0];
    const app_info_payload = try app_info_entry.get_payload(arena_alloc, tmp_alloc, &db);
    const parsed_application_info = try parsing.parse_application_info(
        arena_alloc,
        tmp_alloc,
        &db,
        app_info_payload,
    );
    if (parsed_application_info.version != 6)
        return error.ApllicationInfoVersionMissmatch;

    try vu.check_result(vk.volkInitialize());
    const instance = try vulkan.create_vk_instance(
        tmp_alloc,
        parsed_application_info.application_info,
        args.enable_validation,
    );
    vk.volkLoadInstance(instance.instance);
    if (args.enable_validation)
        _ = try vulkan.init_debug_callback(instance.instance);

    const physical_device = try vulkan.select_physical_device(
        tmp_alloc,
        instance.instance,
        args.enable_validation,
    );
    const vk_device = try vulkan.create_vk_device(
        tmp_alloc,
        &instance,
        &physical_device,
        parsed_application_info.device_features2,
        args.enable_validation,
    );
    _ = tmp_arena.reset(.retain_capacity);

    var thread_pool: ThreadPool = undefined;
    try init_thread_pool_context(&thread_pool, args.num_threads);
    const tread_contexts = try init_thread_contexts(
        arena_alloc,
        args.num_threads,
        &progress_root,
        &db,
        vk_device,
    );

    try parse_threaded(&thread_pool, tread_contexts, &db);
    try create_threaded(tmp_alloc, &thread_pool, tread_contexts, &db, vk_device);

    // Don't set the completion because otherwise Steam will remember that everything
    // is replayed and will not try to replay shaders again.
    // if (control_block) |cb|
    //     cb.progress_complete.store(1, .release);

    var total_used_bytes = arena.queryCapacity() + tmp_arena.queryCapacity();
    for (tread_contexts) |*context| {
        total_used_bytes += context.arena.queryCapacity();
        total_used_bytes += context.tmp_arena.queryCapacity();
    }
    log.info(@src(), "Total memory usage: {d}MB", .{total_used_bytes / 1024 / 1024});
}

pub const MAX_PROCESS_STATS = 256;
pub const CONTROL_BLOCK_MAGIC = 0x19bcde1d;
pub const SharedControlBlock = struct {
    version_cookie: u32,
    futex_lock: u32,

    successful_modules: std.atomic.Value(u32),
    successful_graphics: std.atomic.Value(u32),
    successful_compute: std.atomic.Value(u32),
    successful_raytracing: std.atomic.Value(u32),
    skipped_graphics: std.atomic.Value(u32),
    skipped_compute: std.atomic.Value(u32),
    skipped_raytracing: std.atomic.Value(u32),
    cached_graphics: std.atomic.Value(u32),
    cached_compute: std.atomic.Value(u32),
    cached_raytracing: std.atomic.Value(u32),
    clean_process_deaths: std.atomic.Value(u32),
    dirty_process_deaths: std.atomic.Value(u32),
    parsed_graphics: std.atomic.Value(u32),
    parsed_compute: std.atomic.Value(u32),
    parsed_raytracing: std.atomic.Value(u32),
    parsed_graphics_failures: std.atomic.Value(u32),
    parsed_compute_failures: std.atomic.Value(u32),
    parsed_raytracing_failures: std.atomic.Value(u32),
    parsed_module_failures: std.atomic.Value(u32),
    total_graphics: std.atomic.Value(u32),
    total_compute: std.atomic.Value(u32),
    total_raytracing: std.atomic.Value(u32),
    total_modules: std.atomic.Value(u32),
    banned_modules: std.atomic.Value(u32),
    module_validation_failures: std.atomic.Value(u32),
    progress_started: std.atomic.Value(u32),
    progress_complete: std.atomic.Value(u32),

    // Need to set before `progress_started` is set
    // This is a total number of pipelines
    static_total_count_graphics: std.atomic.Value(u32),
    static_total_count_compute: std.atomic.Value(u32),
    static_total_count_raytracing: std.atomic.Value(u32),

    num_running_processes: std.atomic.Value(u32),
    num_processes_memory_stats: std.atomic.Value(u32),
    metadata_shared_size_mib: std.atomic.Value(u32),
    process_reserved_memory_mib: [MAX_PROCESS_STATS]std.atomic.Value(u32),
    process_shared_memory_mib: [MAX_PROCESS_STATS]std.atomic.Value(u32),
    process_heartbeats: [MAX_PROCESS_STATS]std.atomic.Value(u32),

    dirty_pages_mib: std.atomic.Value(i32),
    io_stall_percentage: std.atomic.Value(i32),

    write_count: u32,
    read_count: u32,
    read_offset: u32,
    write_offset: u32,
    ring_buffer_offset: u32,
    ring_buffer_size: u32,
};

var control_block: ?*SharedControlBlock = null;
pub fn open_control_block(shmem_fd: i32) !void {
    const fstat = try std.posix.fstat(shmem_fd);
    if (fstat.size < @as(i64, @intCast(@sizeOf(SharedControlBlock))))
        return error.SharedMemoryIsSmallerThanControlBlock;
    const mem = try std.posix.mmap(
        null,
        @intCast(fstat.size),
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        shmem_fd,
        0,
    );
    control_block = @ptrCast(@alignCast(mem.ptr));
    if (control_block.?.version_cookie != CONTROL_BLOCK_MAGIC)
        return error.InvalidControlBlockMagic;
}

pub const ThreadContext = struct {
    arena: std.heap.ArenaAllocator,
    tmp_arena: std.heap.ArenaAllocator,
    work_queue: std.ArrayListUnmanaged(*Database.Entry),
    progress: *std.Progress.Node,
    db: *Database,
    vk_device: vk.VkDevice,

    pub fn reset(self: *ThreadContext) void {
        _ = self.arena.reset(.retain_capacity);
        _ = self.tmp_arena.reset(.retain_capacity);
        self.work_queue = .empty;
    }
};

pub fn init_thread_contexts(
    alloc: Allocator,
    num_threads: ?u32,
    progress: *std.Progress.Node,
    db: *Database,
    vk_device: vk.VkDevice,
) ![]align(64) ThreadContext {
    const host_threads = std.Thread.getCpuCount() catch 1;
    const n_threads = if (num_threads) |nt| blk: {
        if (nt == 0) break :blk host_threads else break :blk nt;
    } else host_threads;

    const contexts = try alloc.alignedAlloc(ThreadContext, .@"64", n_threads);

    for (contexts) |*c| {
        c.* = .{
            .arena = .init(std.heap.page_allocator),
            .tmp_arena = .init(std.heap.page_allocator),
            .work_queue = .empty,
            .progress = progress,
            .db = db,
            .vk_device = vk_device,
        };
    }
    return contexts;
}

pub const ThreadPool = struct {
    wait_group: std.Thread.WaitGroup,
    pool: std.Thread.Pool,
};
pub fn init_thread_pool_context(
    context: *ThreadPool,
    num_threads: ?u32,
) !void {
    const host_threads = std.Thread.getCpuCount() catch 1;
    const n_threads = if (num_threads) |nt| blk: {
        if (nt == 0) break :blk host_threads else break :blk nt;
    } else host_threads;
    log.info(@src(), "Using {d} threads", .{n_threads});

    context.wait_group = .{};
    try context.pool.init(.{ .allocator = std.heap.smp_allocator, .n_jobs = n_threads });
}

pub fn parse(context: *ThreadContext) void {
    parse_inner(parsing, context) catch unreachable;
}
pub fn parse_inner(comptime PARSE: type, context: *ThreadContext) !void {
    const alloc = context.arena.allocator();
    const tmp_alloc = context.tmp_arena.allocator();

    var valid: u32 = 0;
    var invalid: u32 = 0;
    const start = try std.time.Instant.now();

    var progress = context.progress.start("parsing", context.work_queue.items.len);
    defer progress.end();

    while (context.work_queue.pop()) |root_entry| {
        defer _ = context.tmp_arena.reset(.retain_capacity);
        defer progress.completeOne();

        var queue: std.ArrayListUnmanaged(struct { *Database.Entry, u32 }) = .empty;
        try queue.append(tmp_alloc, .{ root_entry, 0 });
        while (queue.pop()) |tuple| {
            const curr_entry, const next_dep = tuple;

            switch (curr_entry.parse(PARSE, alloc, tmp_alloc, context.db)) {
                .parsed => {
                    if (next_dep != curr_entry.dependencies.len) {
                        try queue.append(tmp_alloc, .{ curr_entry, next_dep + 1 });
                        const dep = curr_entry.dependencies[next_dep];
                        const dep_entry = context.db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                        try queue.append(tmp_alloc, .{ dep_entry, 0 });
                    }
                },
                .deferred => try queue.append(tmp_alloc, .{ curr_entry, next_dep }),
                .invalid => {
                    invalid += 1;
                    for (queue.items) |t| {
                        const e, _ = t;
                        @atomicStore(Database.Entry.Status, &e.status, .invalid, .seq_cst);
                        e.decrement_dependencies(context.db);
                    }
                    break;
                },
            }
        } else {
            valid += 1;
        }
    }

    const now = try std.time.Instant.now();
    const dt = @as(f64, @floatFromInt(now.since(start))) / 1000_000.0;
    const thread_id = std.Thread.getCurrentId();
    log.info(
        @src(),
        "Thread {d}: parsed entries: valid {d:>6} invalid: {d:>6} in {d:>6.3}ms",
        .{ thread_id, valid, invalid, dt },
    );
}

pub fn parse_threaded(
    thread_pool: *ThreadPool,
    thread_contexts: []align(64) ThreadContext,
    db: *Database,
) !void {
    var remaining_entries = db.entries.getPtr(.graphics_pipeline).values();
    if (thread_contexts.len != 1) {
        const chunk_size = remaining_entries.len / (thread_contexts.len - 1);
        for (thread_contexts[1..]) |*tc| {
            const chunk = remaining_entries[0..chunk_size];
            for (chunk) |*e| try tc.work_queue.append(tc.arena.allocator(), e);
            remaining_entries = remaining_entries[chunk_size..];
            thread_pool.pool.spawnWg(&thread_pool.wait_group, parse, .{tc});
        }
    }
    for (remaining_entries) |*e| try thread_contexts[0].work_queue.append(
        thread_contexts[0].arena.allocator(),
        e,
    );
    thread_pool.pool.spawnWg(&thread_pool.wait_group, parse, .{&thread_contexts[0]});
    thread_pool.wait_group.wait();
    thread_pool.wait_group.reset();
}

pub fn print_time(
    comptime WORK: []const u8,
    start: std.time.Instant,
    counters: *const std.EnumArray(Database.Entry.Tag, u32),
) void {
    const now = std.time.Instant.now() catch unreachable;
    const dt = @as(f64, @floatFromInt(now.since(start))) / 1000_000.0;
    const thread_id = std.Thread.getCurrentId();
    log.info(
        @src(),
        "Thread {d}: {s} {t}: {d:>6} {t}: {d:>6} {t}: {d:>6} {t}: {d:>6} {t}: {d:>6} {t}: {d:>6} {t}: {d:>6} {t}: {d:>6} in {d:>6.3}ms",
        .{
            thread_id,
            WORK,
            Database.Entry.Tag.sampler,
            counters.get(.sampler),
            Database.Entry.Tag.descriptor_set_layout,
            counters.get(.descriptor_set_layout),
            Database.Entry.Tag.pipeline_layout,
            counters.get(.pipeline_layout),
            Database.Entry.Tag.shader_module,
            counters.get(.shader_module),
            Database.Entry.Tag.render_pass,
            counters.get(.render_pass),
            Database.Entry.Tag.graphics_pipeline,
            counters.get(.graphics_pipeline),
            Database.Entry.Tag.compute_pipeline,
            counters.get(.compute_pipeline),
            Database.Entry.Tag.raytracing_pipeline,
            counters.get(.raytracing_pipeline),
            dt,
        },
    );
}
pub fn create(context: *ThreadContext, vk_device: vk.VkDevice) void {
    create_inner(context, vk_device) catch unreachable;
}
pub fn create_inner(context: *ThreadContext, vk_device: vk.VkDevice) !void {
    const alloc = context.arena.allocator();

    var counters: std.EnumArray(Database.Entry.Tag, u32) = .initFill(0);
    const t_start = try std.time.Instant.now();
    defer print_time("created", t_start, &counters);

    var progress = context.progress.start("creation", 0);
    defer progress.end();

    while (context.work_queue.pop()) |entry| {
        defer progress.completeOne();

        switch (try entry.create(vk_device, context.db)) {
            .dependencies => {
                try context.work_queue.append(alloc, entry);
                for (entry.dependencies) |dep| {
                    const dep_entry = context.db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    const d_status =
                        @atomicLoad(Database.Entry.Status, &dep_entry.status, .seq_cst);
                    if (d_status != .created) try context.work_queue.append(alloc, dep_entry);
                }
            },
            .creating => try context.work_queue.append(alloc, entry),
            .created => {
                entry.destroy_dependencies(vk_device, context.db);

                counters.getPtr(entry.tag).* += 1;
                if (control_block) |cb| {
                    switch (entry.tag) {
                        .graphics_pipeline => {
                            _ = cb.successful_graphics.fetchAdd(1, .release);
                            _ = cb.parsed_graphics_failures.fetchAdd(1, .release);
                        },
                        .compute_pipeline => {
                            _ = cb.successful_compute.fetchAdd(1, .release);
                            _ = cb.parsed_compute_failures.fetchAdd(1, .release);
                        },
                        .raytracing_pipeline => {
                            _ = cb.successful_raytracing.fetchAdd(1, .release);
                            _ = cb.parsed_raytracing_failures.fetchAdd(1, .release);
                        },
                        else => {},
                    }
                }
            },
        }
    }
}

pub fn create_threaded(
    tmp_alloc: Allocator,
    thread_pool: *ThreadPool,
    thread_contexts: []align(64) ThreadContext,
    db: *Database,
    vk_device: vk.VkDevice,
) !void {
    var valid_entries: std.ArrayListUnmanaged(*Database.Entry) = .empty;
    for (db.entries.getPtr(.graphics_pipeline).values()) |*entry| {
        if (entry.status != .invalid)
            try valid_entries.append(tmp_alloc, entry);
    }
    var remaining_entries = valid_entries.items;
    if (thread_contexts.len != 1) {
        const chunk_size = remaining_entries.len / (thread_contexts.len - 1);
        for (thread_contexts[1..]) |*tc| {
            const chunk = remaining_entries[0..chunk_size];
            for (chunk) |e| try tc.work_queue.append(tc.arena.allocator(), e);
            remaining_entries = remaining_entries[chunk_size..];
            thread_pool.pool.spawnWg(&thread_pool.wait_group, create, .{ tc, vk_device });
        }
    }
    for (remaining_entries) |e| try thread_contexts[0].work_queue.append(
        thread_contexts[0].arena.allocator(),
        e,
    );
    thread_pool.pool.spawnWg(
        &thread_pool.wait_group,
        create,
        .{ &thread_contexts[0], vk_device },
    );
    thread_pool.wait_group.wait();
    thread_pool.wait_group.reset();
}

test "parse" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var progress = std.Progress.start(.{});
    defer progress.end();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const tmp_file = try tmp_dir.dir.createFile("parse_test", .{});

    var db: Database = .{ .file = tmp_file, .entries = .initFill(.empty), .arena = arena };
    try db.entries.getPtr(.graphics_pipeline).put(alloc, 70, .{
        .tag = .graphics_pipeline,
        .hash = 70,
        .payload_flag = .not_compressed,
        .payload_crc = 0,
        .payload_stored_size = 0,
        .payload_decompressed_size = 0,
        .payload_file_offset = 0,
    });
    try db.entries.getPtr(.graphics_pipeline).put(alloc, 71, .{
        .tag = .graphics_pipeline,
        .hash = 71,
        .payload_flag = .not_compressed,
        .payload_crc = 0,
        .payload_stored_size = 0,
        .payload_decompressed_size = 0,
        .payload_file_offset = 0,
    });
    var thread_context: ThreadContext = .{
        .arena = .init(std.heap.page_allocator),
        .tmp_arena = .init(std.heap.page_allocator),
        .work_queue = .empty,
        .progress = &progress,
        .db = &db,
        .vk_device = undefined,
    };
    var test_entry: Database.Entry = .{
        .tag = .graphics_pipeline,
        .hash = 69,
        .payload_flag = .not_compressed,
        .payload_crc = 0,
        .payload_stored_size = 0,
        .payload_decompressed_size = 0,
        .payload_file_offset = 0,
    };
    try thread_context.work_queue.append(thread_context.arena.allocator(), &test_entry);

    const TestParse = struct {
        fn dummy_parse(
            _: Allocator,
            _: Allocator,
            _: *const Database,
            _: []const u8,
        ) parsing.Error!parsing.Result {
            unreachable;
        }
        fn dummy_parse_with_dependencies(
            _: Allocator,
            _: Allocator,
            _: *const Database,
            _: []const u8,
        ) parsing.Error!parsing.ResultWithDependencies {
            unreachable;
        }
        pub const parse_sampler = dummy_parse;
        pub const parse_descriptor_set_layout = dummy_parse_with_dependencies;
        pub const parse_pipeline_layout = dummy_parse_with_dependencies;
        pub const parse_shader_module = dummy_parse;
        pub const parse_render_pass = dummy_parse;
        pub const parse_compute_pipeline = dummy_parse_with_dependencies;
        pub const parse_raytracing_pipeline = dummy_parse_with_dependencies;
        pub fn parse_graphics_pipeline(
            _: Allocator,
            _: Allocator,
            _: *const Database,
            _: []const u8,
        ) parsing.Error!parsing.ResultWithDependencies {
            const Global = struct {
                var n: u32 = 0;
            };
            defer Global.n += 1;

            var dependencies: []const Database.Entry.Dependency = &.{
                .{ .tag = .graphics_pipeline, .hash = 70 },
                .{ .tag = .graphics_pipeline, .hash = 71 },
            };
            if (Global.n != 0) dependencies = &.{};
            return .{
                .version = 6,
                .hash = 69 + Global.n,
                .create_info = undefined,
                .dependencies = dependencies,
            };
        }
    };
    try parse_inner(TestParse, &thread_context);
    try std.testing.expectEqual(.parsed, test_entry.status);
    const pipelines = db.entries.getPtr(.graphics_pipeline);
    for (pipelines.values()) |*entry|
        try std.testing.expectEqual(.parsed, entry.status);
}

comptime {
    _ = @import("parsing.zig");
}
