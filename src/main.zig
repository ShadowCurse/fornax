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
const PDF = @import("physical_device_features.zig");
const vu = @import("vulkan_utils.zig");
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

    // var db: Database = try .init(tmp_alloc, &progress_root, db_path);
    // _ = tmp_arena.reset(.retain_capacity);

    var db: Database = try .init(tmp_alloc, &progress_root, db_path);
    _ = tmp_arena.reset(.retain_capacity);

    if (control_block) |cb| {
        const graphics: u32 =
            @intCast(db.entries.getPtrConst(.GRAPHICS_PIPELINE).values().len);
        cb.static_total_count_graphics.store(graphics, .release);
        const compute: u32 =
            @intCast(db.entries.getPtrConst(.COMPUTE_PIPELINE).values().len);
        cb.static_total_count_compute.store(compute, .release);
        const raytracing: u32 =
            @intCast(db.entries.getPtrConst(.RAYTRACING_PIPELINE).values().len);
        cb.static_total_count_raytracing.store(raytracing, .release);

        cb.num_running_processes.store(args.num_threads.? + 1, .release);
        cb.num_processes_memory_stats.store(args.num_threads.? + 1, .release);

        cb.progress_started.store(1, .release);
    }

    const app_infos = db.entries.getPtrConst(.APPLICATION_INFO).values();
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
    const instance = try create_vk_instance(
        tmp_alloc,
        parsed_application_info.application_info,
        args.enable_validation,
    );
    vk.volkLoadInstance(instance.instance);
    if (args.enable_validation)
        _ = try init_debug_callback(instance.instance);

    const physical_device = try select_physical_device(
        tmp_alloc,
        instance.instance,
        args.enable_validation,
    );
    const vk_device = try create_vk_device(
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
    try create_threaded(&thread_pool, tread_contexts, &db, vk_device);

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

pub fn check_version_and_hash(v: anytype, entry: *const Database.Entry) !void {
    const tag = entry.get_tag() catch unreachable;
    const hash: u64 = entry.get_value() catch unreachable;
    if (v.version != 6) {
        log.err(
            @src(),
            "{s} has invalid version: {d} != {d}",
            .{ @tagName(tag), v.version, @as(u32, 6) },
        );
        return error.InvalidVerson;
    }
    if (v.hash != hash) {
        log.err(
            @src(),
            "{s} hash not equal to json version: 0x{x} != 0x{x}",
            .{ @tagName(tag), v.hash, hash },
        );
        return error.InvalidHash;
    }
}

pub const Action = union(enum) {
    Pass: struct { u64, u64 },
    Defer,
    Remove,
};
pub const REPLAY_FN =
    fn (Allocator, *Database.EntryMeta, *const Database, vk.VkDevice) anyerror!Action;
pub fn create_replay_fn(
    comptime TAG: Database.Entry.Tag,
    comptime PARSE_FN: anytype,
    comptime CREATE_FN: anytype,
) REPLAY_FN {
    const Inner = struct {
        pub fn replay(
            tmp_alloc: Allocator,
            entry: *Database.EntryMeta,
            db: *const Database,
            vk_device: vk.VkDevice,
        ) anyerror!Action {
            const e = Database.Entry.from_ptr(entry.entry_ptr);
            const parse_start = try std.time.Instant.now();
            const result = PARSE_FN(tmp_alloc, tmp_alloc, db, entry.payload) catch |err| {
                if (err == error.NoHandleFound) return .Defer;
                if (err == error.NoObjectFound) return .Remove;
                log.err(
                    @src(),
                    "Encountered error {} while parsing {s}",
                    .{ err, @tagName(TAG) },
                );
                log.debug(@src(), "json: {s}", .{entry.payload});
                return err;
            };
            const parse_end = try std.time.Instant.now();
            try check_version_and_hash(result, &e);
            const create_start = try std.time.Instant.now();
            const handle = CREATE_FN(vk_device, result.create_info) catch |err| {
                log.err(
                    @src(),
                    "Encountered error {} while creating {s}",
                    .{ err, @tagName(TAG) },
                );
                vu.print_struct(result.create_info);
                return .Remove;
            };
            const create_end = try std.time.Instant.now();
            @atomicStore(?*anyopaque, &entry.handle, handle, .seq_cst);
            return .{ .Pass = .{ parse_end.since(parse_start), create_end.since(create_start) } };
        }
    };
    return Inner.replay;
}

pub const ThreadContext = struct {
    arena: std.heap.ArenaAllocator,
    tmp_arena: std.heap.ArenaAllocator,
    work_queue: std.ArrayListUnmanaged(*Database.EntryMeta),
    parse_time_acc: u64,
    create_time_acc: u64,
    progress: *std.Progress.Node,
    db: *Database,
    vk_device: vk.VkDevice,

    pub fn reset(self: *ThreadContext) void {
        _ = self.arena.reset(.retain_capacity);
        _ = self.tmp_arena.reset(.retain_capacity);
        self.work_queue = .empty;
        self.parse_time_acc = 0;
        self.create_time_acc = 0;
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
            .parse_time_acc = 0,
            .create_time_acc = 0,
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

pub const replay_sampler = create_replay_fn(
    .SAMPLER,
    parsing.parse_sampler,
    create_vk_sampler,
);

pub const replay_descriptor_set = create_replay_fn(
    .DESCRIPTOR_SET_LAYOUT,
    parsing.parse_descriptor_set_layout,
    create_descriptor_set_layout,
);

pub const replay_pipeline_layout = create_replay_fn(
    .PIPELINE_LAYOUT,
    parsing.parse_pipeline_layout,
    create_pipeline_layout,
);

pub const replay_render_pass = create_replay_fn(
    .RENDER_PASS,
    parsing.parse_render_pass,
    create_render_pass,
);

pub const replay_shader_module = create_replay_fn(
    .SHADER_MODULE,
    parsing.parse_shader_module,
    create_shader_module,
);

pub const replay_graphics_pipeline = create_replay_fn(
    .GRAPHICS_PIPELINE,
    parsing.parse_graphics_pipeline,
    create_graphics_pipeline,
);

pub const replay_compute_pipeline = create_replay_fn(
    .COMPUTE_PIPELINE,
    parsing.parse_compute_pipeline,
    create_compute_pipeline,
);

pub const replay_raytracing_pipeline = create_replay_fn(
    .RAYTRACING_PIPELINE,
    parsing.parse_raytracing_pipeline,
    create_raytracing_pipeline,
);

pub fn replay_chunk(
    context: *ThreadContext,
    chunk: []Database.EntryMeta,
    tag: Database.Entry.Tag,
    replay_fn: *const REPLAY_FN,
) void {
    const alloc = context.arena.allocator();

    const name = std.fmt.allocPrint(alloc, "replaying {s}", .{@tagName(tag)}) catch unreachable;
    var sub_progress = context.progress.start(name, chunk.len);
    defer sub_progress.end();

    var tmp_allocator = std.heap.ArenaAllocator.init(alloc);
    const tmp_alloc = tmp_allocator.allocator();
    for (chunk) |*gp| {
        defer _ = tmp_allocator.reset(.retain_capacity);
        defer sub_progress.completeOne();

        const action = replay_fn(tmp_alloc, gp, context.db, context.vk_device) catch break;
        switch (action) {
            .Pass => |times| {
                const parse_time_ns, const create_time_ns = times;
                context.parse_time_acc += parse_time_ns;
                context.create_time_acc += create_time_ns;
            },
            .Defer => context.deferred_entries.append(alloc, gp.*) catch unreachable,
            .Remove => context.removed_entries.append(alloc, gp.*) catch unreachable,
        }
    }
}

pub fn print_replay_time(
    start: std.time.Instant,
    tag: Database.Entry.Tag,
    processed: usize,
    removed: usize,
    total_parse_ns: u64,
    total_create_ns: u64,
) void {
    const now = std.time.Instant.now() catch unreachable;
    const dt = @as(f64, @floatFromInt(now.since(start))) / 1000_000.0;
    const avg_parse = if (processed == 0) 0 else total_parse_ns / processed;
    const avg_create = if (processed == 0) 0 else total_create_ns / processed;
    log.info(
        @src(),
        "Replayed {d:>6} {s:<21} in {d:>9.3}ms Skipped {d:>6} Avg parse time: {d:>8}ns Avg create time: {d:>8}ns",
        .{
            processed,
            @tagName(tag),
            dt,
            removed,
            avg_parse,
            avg_create,
        },
    );
}
pub fn replay(
    tmp_allocator: *std.heap.ArenaAllocator,
    thread_pool: *ThreadPool,
    thread_contexts: []align(64) ThreadContext,
    db: *Database,
    tag: Database.Entry.Tag,
    replay_fn: *const REPLAY_FN,
) !void {
    const entries = db.entries.getPtrConst(tag).values();

    var processed = entries.len;
    var removed: usize = 0;
    var total_parse_ns: u64 = 0;
    var total_create_ns: u64 = 0;
    const t_start = try std.time.Instant.now();
    defer print_replay_time(t_start, tag, processed, removed, total_parse_ns, total_create_ns);

    const tmp_alloc = tmp_allocator.allocator();
    defer _ = tmp_allocator.reset(.retain_capacity);

    var remaining_entries = entries;
    while (remaining_entries.len != 0) {
        if (thread_contexts.len != 1) {
            const chunk_size = remaining_entries.len / (thread_contexts.len - 1);

            for (thread_contexts[1..]) |*tc| {
                const chunk = remaining_entries[0..chunk_size];
                remaining_entries = remaining_entries[chunk_size..];
                thread_pool.pool.spawnWg(
                    &thread_pool.wait_group,
                    replay_chunk,
                    .{ tc, chunk, tag, replay_fn },
                );
            }
        }
        thread_pool.pool.spawnWg(
            &thread_pool.wait_group,
            replay_chunk,
            .{ &thread_contexts[0], remaining_entries, tag, replay_fn },
        );
        thread_pool.wait_group.wait();
        thread_pool.wait_group.reset();

        _ = tmp_allocator.reset(.retain_capacity);
        var deferred_entries: std.ArrayListUnmanaged(Database.EntryMeta) = .empty;
        for (thread_contexts) |*context| {
            total_parse_ns += context.parse_time_acc;
            total_create_ns += context.create_time_acc;
            processed -= context.removed_entries.items.len;
            removed += context.removed_entries.items.len;

            try deferred_entries.appendSlice(tmp_alloc, context.deferred_entries.items);
            for (context.removed_entries.items) |r| {
                const e = Database.Entry.from_ptr(r.entry_ptr);
                _ = db.entries.getPtr(tag).swapRemove(try e.get_value());
            }
            context.reset();
        }
        remaining_entries = deferred_entries.items;
    }

    if (control_block) |cb| {
        switch (tag) {
            .SHADER_MODULE => {
                cb.total_modules.store(@intCast(processed), .release);
                cb.successful_modules.store(@intCast(processed), .release);
                cb.parsed_module_failures.store(@intCast(removed), .release);
            },
            .GRAPHICS_PIPELINE => {
                cb.total_graphics.store(@intCast(processed), .release);
                cb.parsed_graphics.store(@intCast(processed), .release);
                cb.successful_graphics.store(@intCast(processed), .release);
                cb.parsed_graphics_failures.store(@intCast(removed), .release);
            },
            .COMPUTE_PIPELINE => {
                cb.total_compute.store(@intCast(processed), .release);
                cb.parsed_compute.store(@intCast(processed), .release);
                cb.successful_compute.store(@intCast(processed), .release);
                cb.parsed_compute_failures.store(@intCast(removed), .release);
            },
            .RAYTRACING_PIPELINE => {
                cb.total_raytracing.store(@intCast(processed), .release);
                cb.parsed_raytracing.store(@intCast(processed), .release);
                cb.successful_raytracing.store(@intCast(processed), .release);
                cb.parsed_raytracing_failures.store(@intCast(removed), .release);
            },
            else => {},
        }
    }
}

pub fn parse(context: *ThreadContext) void {
    parse_inner(context) catch unreachable;
}
pub fn parse_inner(context: *ThreadContext) !void {
    const alloc = context.arena.allocator();
    const tmp_alloc = context.tmp_arena.allocator();

    while (context.work_queue.pop()) |entry| {
        defer _ = context.tmp_arena.reset(.retain_capacity);

        if (!try entry.parse(alloc, tmp_alloc, context.db)) {
            try context.work_queue.append(alloc, entry);
            continue;
        }
        for (entry.dependencies) |dep| {
            const dep_entry = context.db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
            const d_status =
                @atomicLoad(Database.EntryMeta.Status, &dep_entry.status, .seq_cst);
            if (d_status != .parsed) try context.work_queue.append(alloc, dep_entry);
        }
    }
}

pub fn parse_threaded(
    thread_pool: *ThreadPool,
    thread_contexts: []align(64) ThreadContext,
    db: *Database,
) !void {
    var remaining_entries = db.entries.getPtr(.GRAPHICS_PIPELINE).values();
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

pub fn create(context: *ThreadContext, vk_device: vk.VkDevice) void {
    create_inner(context, vk_device) catch unreachable;
}
pub fn create_inner(context: *ThreadContext, vk_device: vk.VkDevice) !void {
    const alloc = context.arena.allocator();
    while (context.work_queue.pop()) |entry| {
        switch (try entry.create(vk_device, context.db)) {
            .dependencies => {
                try context.work_queue.append(alloc, entry);
                for (entry.dependencies) |dep| {
                    const dep_entry = context.db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    const d_status =
                        @atomicLoad(Database.EntryMeta.Status, &dep_entry.status, .seq_cst);
                    if (d_status != .created) try context.work_queue.append(alloc, dep_entry);
                }
            },
            .creating => try context.work_queue.append(alloc, entry),
            .created => {
                entry.destroy_dependencies(vk_device, context.db);
            },
        }
    }
}
pub fn create_threaded(
    thread_pool: *ThreadPool,
    thread_contexts: []align(64) ThreadContext,
    db: *Database,
    vk_device: vk.VkDevice,
) !void {
    var remaining_entries = db.entries.getPtr(.GRAPHICS_PIPELINE).values();
    if (thread_contexts.len != 1) {
        const chunk_size = remaining_entries.len / (thread_contexts.len - 1);
        for (thread_contexts[1..]) |*tc| {
            const chunk = remaining_entries[0..chunk_size];
            for (chunk) |*e| try tc.work_queue.append(tc.arena.allocator(), e);
            remaining_entries = remaining_entries[chunk_size..];
            thread_pool.pool.spawnWg(&thread_pool.wait_group, create, .{ tc, vk_device });
        }
    }
    for (remaining_entries) |*e| try thread_contexts[0].work_queue.append(
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

const VK_VALIDATION_LAYERS_NAMES = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
const VK_ADDITIONAL_EXTENSIONS_NAMES = [_][*c]const u8{"VK_EXT_debug_utils"};

pub fn contains_all_extensions(
    log_prefix: ?[]const u8,
    extensions: []const vk.VkExtensionProperties,
    to_find: []const [*c]const u8,
) bool {
    var found_extensions: u32 = 0;
    for (extensions) |e| {
        var required = "--------";
        for (to_find) |tf| {
            const extension_name_span = std.mem.span(@as(
                [*c]const u8,
                @ptrCast(&e.extensionName),
            ));
            const tf_extension_name_span = std.mem.span(@as(
                [*c]const u8,
                tf,
            ));
            if (std.mem.eql(u8, extension_name_span, tf_extension_name_span)) {
                found_extensions += 1;
                required = "required";
            }
        }
        if (log_prefix) |lp|
            log.debug(@src(), "({s})({s}) Extension version: {d}.{d}.{d} Name: {s}", .{
                required,
                lp,
                vk.VK_API_VERSION_MAJOR(e.specVersion),
                vk.VK_API_VERSION_MINOR(e.specVersion),
                vk.VK_API_VERSION_PATCH(e.specVersion),
                e.extensionName,
            });
    }
    return found_extensions == to_find.len;
}

pub fn contains_all_layers(
    log_prefix: ?[]const u8,
    layers: []const vk.VkLayerProperties,
    to_find: []const [*c]const u8,
) bool {
    var found_layers: u32 = 0;
    for (layers) |l| {
        var required = "--------";
        for (to_find) |tf| {
            const layer_name_span = std.mem.span(@as([*c]const u8, @ptrCast(&l.layerName)));
            const tf_layer_name_span = std.mem.span(@as([*c]const u8, tf));
            if (std.mem.eql(u8, layer_name_span, tf_layer_name_span)) {
                found_layers += 1;
                required = "required";
            }
        }
        if (log_prefix) |lp|
            log.debug(@src(), "({s})({s}) Layer name: {s} Spec version: {d}.{d}.{d} Description: {s}", .{
                required,
                lp,
                l.layerName,
                vk.VK_API_VERSION_MAJOR(l.specVersion),
                vk.VK_API_VERSION_MINOR(l.specVersion),
                vk.VK_API_VERSION_PATCH(l.specVersion),
                l.description,
            });
    }
    return found_layers == to_find.len;
}

pub fn get_instance_extensions(arena_alloc: Allocator) ![]const vk.VkExtensionProperties {
    var extensions_count: u32 = 0;
    try vu.check_result(vk.vkEnumerateInstanceExtensionProperties.?(
        null,
        &extensions_count,
        null,
    ));
    const extensions = try arena_alloc.alloc(vk.VkExtensionProperties, extensions_count);
    try vu.check_result(vk.vkEnumerateInstanceExtensionProperties.?(
        null,
        &extensions_count,
        extensions.ptr,
    ));
    return extensions;
}

pub fn get_instance_layer_properties(arena_alloc: Allocator) ![]const vk.VkLayerProperties {
    var layer_property_count: u32 = 0;
    try vu.check_result(vk.vkEnumerateInstanceLayerProperties.?(&layer_property_count, null));
    const layers = try arena_alloc.alloc(vk.VkLayerProperties, layer_property_count);
    try vu.check_result(vk.vkEnumerateInstanceLayerProperties.?(
        &layer_property_count,
        layers.ptr,
    ));
    return layers;
}

pub const Instance = struct {
    instance: vk.VkInstance,
    api_version: u32,
    has_properties_2: bool,
};
pub fn create_vk_instance(
    arena_alloc: Allocator,
    requested_app_info: ?*const vk.VkApplicationInfo,
    enable_validation: bool,
) !Instance {
    const api_version = vk.volkGetInstanceVersion();
    log.info(
        @src(),
        "Supported vulkan version: {d}.{d}.{d}",
        .{
            vk.VK_API_VERSION_MAJOR(api_version),
            vk.VK_API_VERSION_MINOR(api_version),
            vk.VK_API_VERSION_PATCH(api_version),
        },
    );
    if (requested_app_info) |app_info| {
        log.info(
            @src(),
            "Requested app info vulkan version: {d}.{d}.{d}",
            .{
                vk.VK_API_VERSION_MAJOR(app_info.apiVersion),
                vk.VK_API_VERSION_MINOR(app_info.apiVersion),
                vk.VK_API_VERSION_PATCH(app_info.apiVersion),
            },
        );
        if (api_version < app_info.apiVersion) {
            log.err(@src(), "Requested vulkan api version is above the supported version", .{});
            return error.UnsupportedVulkanApiVersion;
        }
    }

    const extensions = try get_instance_extensions(arena_alloc);
    if (!contains_all_extensions("Instance", extensions, &VK_ADDITIONAL_EXTENSIONS_NAMES))
        return error.AdditionalExtensionsNotFound;

    const has_properties_2 = contains_all_extensions(
        null,
        extensions,
        &.{vk.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME},
    );

    const all_extension_names = try arena_alloc.alloc([*c]const u8, extensions.len);
    for (extensions, 0..) |*e, i|
        all_extension_names[i] = &e.extensionName;

    const enabled_layers = if (enable_validation) blk: {
        const layers = try get_instance_layer_properties(arena_alloc);
        if (!contains_all_layers("Instance", layers, &VK_VALIDATION_LAYERS_NAMES))
            return error.InstanceValidationLayersNotFound;
        break :blk &VK_VALIDATION_LAYERS_NAMES;
    } else &.{};

    const app_info = if (requested_app_info) |app_info|
        app_info
    else
        &vk.VkApplicationInfo{
            .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "glacier",
            .applicationVersion = vk.VK_MAKE_VERSION(0, 0, 1),
            .pEngineName = "glacier",
            .engineVersion = vk.VK_MAKE_VERSION(0, 0, 1),
            .apiVersion = api_version,
            .pNext = null,
        };
    log.info(@src(), "Creating instance with application name: {s} engine name: {s} api version: {d}.{d}.{d}", .{
        app_info.pApplicationName,
        app_info.pEngineName,
        vk.VK_API_VERSION_MAJOR(app_info.apiVersion),
        vk.VK_API_VERSION_MINOR(app_info.apiVersion),
        vk.VK_API_VERSION_PATCH(app_info.apiVersion),
    });
    const instance_create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = app_info,
        .ppEnabledExtensionNames = all_extension_names.ptr,
        .enabledExtensionCount = @as(u32, @intCast(all_extension_names.len)),
        .ppEnabledLayerNames = @ptrCast(enabled_layers.ptr),
        .enabledLayerCount = @as(u32, @intCast(enabled_layers.len)),
    };

    var vk_instance: vk.VkInstance = undefined;
    try vu.check_result(vk.vkCreateInstance.?(&instance_create_info, null, &vk_instance));
    log.debug(
        @src(),
        "Created instance api version: {d}.{d}.{d} has_properties_2: {}",
        .{
            vk.VK_API_VERSION_MAJOR(api_version),
            vk.VK_API_VERSION_MINOR(api_version),
            vk.VK_API_VERSION_PATCH(api_version),
            has_properties_2,
        },
    );
    return .{
        .instance = vk_instance,
        .api_version = api_version,
        .has_properties_2 = has_properties_2,
    };
}

pub fn init_debug_callback(instance: vk.VkInstance) !vk.VkDebugReportCallbackEXT {
    const create_info = vk.VkDebugReportCallbackCreateInfoEXT{
        .sType = vk.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
        .pfnCallback = debug_callback,
        .flags = vk.VK_DEBUG_REPORT_ERROR_BIT_EXT |
            vk.VK_DEBUG_REPORT_WARNING_BIT_EXT,
        .pUserData = null,
    };

    var callback: vk.VkDebugReportCallbackEXT = undefined;
    try vu.check_result(
        vk.vkCreateDebugReportCallbackEXT.?(
            instance,
            &create_info,
            null,
            &callback,
        ),
    );
    return callback;
}

pub fn debug_callback(
    flags: vk.VkDebugReportFlagsEXT,
    _: vk.VkDebugReportObjectTypeEXT,
    _: u64,
    _: usize,
    _: i32,
    layer: [*c]const u8,
    message: [*c]const u8,
    _: ?*anyopaque,
) callconv(.c) vk.VkBool32 {
    if (flags & vk.VK_DEBUG_REPORT_WARNING_BIT_EXT != 0)
        log.warn(@src(), "Layer: {s} Message: {s}", .{ layer, message });
    if (flags & vk.VK_DEBUG_REPORT_ERROR_BIT_EXT != 0)
        log.err(@src(), "Layer: {s} Message: {s}", .{ layer, message });

    return vk.VK_FALSE;
}

pub fn get_physical_devices(
    arena_alloc: Allocator,
    vk_instance: vk.VkInstance,
) ![]const vk.VkPhysicalDevice {
    var physical_device_count: u32 = 0;
    try vu.check_result(vk.vkEnumeratePhysicalDevices.?(
        vk_instance,
        &physical_device_count,
        null,
    ));
    const physical_devices = try arena_alloc.alloc(
        vk.VkPhysicalDevice,
        physical_device_count,
    );
    try vu.check_result(vk.vkEnumeratePhysicalDevices.?(
        vk_instance,
        &physical_device_count,
        physical_devices.ptr,
    ));
    return physical_devices;
}

pub fn get_physical_device_exensions(
    arena_alloc: Allocator,
    physical_device: vk.VkPhysicalDevice,
    extension_name: [*c]const u8,
) ![]const vk.VkExtensionProperties {
    var extensions_count: u32 = 0;
    try vu.check_result(vk.vkEnumerateDeviceExtensionProperties.?(
        physical_device,
        extension_name,
        &extensions_count,
        null,
    ));
    const extensions = try arena_alloc.alloc(vk.VkExtensionProperties, extensions_count);
    try vu.check_result(vk.vkEnumerateDeviceExtensionProperties.?(
        physical_device,
        extension_name,
        &extensions_count,
        extensions.ptr,
    ));
    return extensions;
}

pub fn get_physical_device_layers(
    arena_alloc: Allocator,
    physical_device: vk.VkPhysicalDevice,
) ![]const vk.VkLayerProperties {
    var layer_property_count: u32 = 0;
    try vu.check_result(vk.vkEnumerateDeviceLayerProperties.?(
        physical_device,
        &layer_property_count,
        null,
    ));
    const layers = try arena_alloc.alloc(vk.VkLayerProperties, layer_property_count);
    try vu.check_result(vk.vkEnumerateDeviceLayerProperties.?(
        physical_device,
        &layer_property_count,
        layers.ptr,
    ));
    return layers;
}

pub const PhysicalDevice = struct {
    device: vk.VkPhysicalDevice,
    graphics_queue_family: u32,
    has_validation_cache: bool,
};

pub fn select_physical_device(
    arena_alloc: Allocator,
    vk_instance: vk.VkInstance,
    enable_validation: bool,
) !PhysicalDevice {
    const physical_devices = try get_physical_devices(arena_alloc, vk_instance);

    for (physical_devices) |physical_device| {
        var properties: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties.?(physical_device, &properties);

        log.debug(@src(),
            \\ Physical device:
            \\    Name: {s}
            \\    API version: {d}.{d}.{d}
            \\    Driver version: {d}.{d}.{d}
            \\    Vendor ID: {d}
            \\    Device Id: {d}
            \\    Device type: {d}
        , .{
            properties.deviceName,
            vk.VK_API_VERSION_MAJOR(properties.apiVersion),
            vk.VK_API_VERSION_MINOR(properties.apiVersion),
            vk.VK_API_VERSION_PATCH(properties.apiVersion),
            vk.VK_API_VERSION_MAJOR(properties.driverVersion),
            vk.VK_API_VERSION_MINOR(properties.driverVersion),
            vk.VK_API_VERSION_PATCH(properties.driverVersion),
            properties.vendorID,
            properties.deviceID,
            properties.deviceType,
        });

        const has_validation_cache = if (enable_validation) blk: {
            const layers = try get_physical_device_layers(arena_alloc, physical_device);
            if (!contains_all_layers(&properties.deviceName, layers, &VK_VALIDATION_LAYERS_NAMES))
                return error.PhysicalDeviceValidationLayersNotFound;

            const validation_extensions = try get_physical_device_exensions(
                arena_alloc,
                physical_device,
                "VK_LAYER_KHRONOS_validation",
            );
            break :blk contains_all_extensions(
                null,
                validation_extensions,
                &.{vk.VK_EXT_VALIDATION_CACHE_EXTENSION_NAME},
            );
        } else false;

        // Because the exact queue does not matter much,
        // select the first queue with graphics capability.
        var queue_family_count: u32 = 0;
        vk.vkGetPhysicalDeviceQueueFamilyProperties.?(physical_device, &queue_family_count, null);
        const queue_families = try arena_alloc.alloc(
            vk.VkQueueFamilyProperties,
            queue_family_count,
        );
        vk.vkGetPhysicalDeviceQueueFamilyProperties.?(
            physical_device,
            &queue_family_count,
            queue_families.ptr,
        );
        var graphics_queue_family: ?u32 = null;
        for (queue_families, 0..) |qf, i| {
            if (qf.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
                graphics_queue_family = @intCast(i);
                break;
            }
        }

        if (graphics_queue_family != null) {
            log.debug(
                @src(),
                "Selected device: {s} Graphics queue family: {d} Has validation cache: {}",
                .{
                    properties.deviceName,
                    graphics_queue_family.?,
                    has_validation_cache,
                },
            );
            return .{
                .device = physical_device,
                .graphics_queue_family = graphics_queue_family.?,
                .has_validation_cache = has_validation_cache,
            };
        }
    }
    return error.PhysicalDeviceNotSelected;
}

pub fn usable_device_extension(
    ext: [*c]const u8,
    all_ext_props: []const vk.VkExtensionProperties,
    api_version: u32,
) bool {
    const e = std.mem.span(ext);
    if (std.mem.eql(u8, e, vk.VK_AMD_NEGATIVE_VIEWPORT_HEIGHT_EXTENSION_NAME))
        return false;
    if (std.mem.eql(u8, e, vk.VK_NV_RAY_TRACING_EXTENSION_NAME))
        return false;
    if (std.mem.eql(u8, e, vk.VK_AMD_SHADER_INFO_EXTENSION_NAME))
        return false;
    if (std.mem.eql(u8, e, vk.VK_EXT_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME))
        for (all_ext_props) |other_ext| {
            const other_e = std.mem.span(@as([*c]const u8, @ptrCast(&other_ext.extensionName)));
            if (std.mem.eql(u8, other_e, vk.VK_KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME))
                return false;
        };
    if (std.mem.eql(u8, e, vk.VK_AMD_SHADER_FRAGMENT_MASK_EXTENSION_NAME))
        for (all_ext_props) |other_ext| {
            const other_e = std.mem.span(@as([*c]const u8, @ptrCast(&other_ext.extensionName)));
            if (std.mem.eql(u8, other_e, vk.VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME))
                return false;
        };

    const VK_1_1_EXTS: []const []const u8 = &.{
        vk.VK_KHR_SHADER_SUBGROUP_EXTENDED_TYPES_EXTENSION_NAME,
        vk.VK_KHR_SPIRV_1_4_EXTENSION_NAME,
        vk.VK_KHR_SHARED_PRESENTABLE_IMAGE_EXTENSION_NAME,
        vk.VK_KHR_SHADER_FLOAT_CONTROLS_EXTENSION_NAME,
        vk.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME,
        vk.VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME,
        vk.VK_KHR_RAY_QUERY_EXTENSION_NAME,
        vk.VK_KHR_MAINTENANCE_4_EXTENSION_NAME,
        vk.VK_KHR_SHADER_SUBGROUP_UNIFORM_CONTROL_FLOW_EXTENSION_NAME,
        vk.VK_EXT_SUBGROUP_SIZE_CONTROL_EXTENSION_NAME,
        vk.VK_NV_SHADER_SM_BUILTINS_EXTENSION_NAME,
        vk.VK_NV_SHADER_SUBGROUP_PARTITIONED_EXTENSION_NAME,
        vk.VK_NV_DEVICE_GENERATED_COMMANDS_EXTENSION_NAME,
    };

    var is_vk_1_1_ext: bool = false;
    for (VK_1_1_EXTS) |vk_1_1_ext|
        if (std.mem.eql(u8, vk_1_1_ext, e)) {
            is_vk_1_1_ext = true;
            break;
        };

    if (api_version < vk.VK_API_VERSION_1_1 and is_vk_1_1_ext) {
        return false;
    }

    return true;
}

pub fn create_vk_device(
    arena_alloc: Allocator,
    instance: *const Instance,
    physical_device: *const PhysicalDevice,
    device_features2: ?*const vk.VkPhysicalDeviceFeatures2,
    enable_validation: bool,
) !vk.VkDevice {
    const queue_priority: f32 = 1.0;
    const queue_create_info = vk.VkDeviceQueueCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = physical_device.graphics_queue_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    };

    // All extensions will be activated for the device. If it
    // supports validation caching, enable it's extension as well.
    const extensions =
        try get_physical_device_exensions(arena_alloc, physical_device.device, null);
    var all_extensions_len = extensions.len;
    if (physical_device.has_validation_cache)
        all_extensions_len += 1;
    var all_extension_names = try arena_alloc.alloc([*c]const u8, all_extensions_len);
    all_extensions_len = 0;
    for (extensions) |*e| {
        var enabled: []const u8 = "enabled";
        if (usable_device_extension(&e.extensionName, extensions, instance.api_version)) {
            all_extension_names[all_extensions_len] = &e.extensionName;
            all_extensions_len += 1;
        } else enabled = "filtered";
        log.debug(@src(), "(PhysicalDevice)({s<8}) Extension version: {d}.{d}.{d} Name: {s}", .{
            enabled,
            vk.VK_API_VERSION_MAJOR(e.specVersion),
            vk.VK_API_VERSION_MINOR(e.specVersion),
            vk.VK_API_VERSION_PATCH(e.specVersion),
            e.extensionName,
        });
    }
    if (physical_device.has_validation_cache) {
        all_extension_names[all_extensions_len] = vk.VK_EXT_VALIDATION_CACHE_EXTENSION_NAME;
        all_extensions_len += 1;
    }
    all_extension_names = all_extension_names[0..all_extensions_len];

    var features_2 = vk.VkPhysicalDeviceFeatures2{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
    };
    var stats: vk.VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR = .{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PIPELINE_EXECUTABLE_PROPERTIES_FEATURES_KHR,
    };
    features_2.pNext = &stats;
    var physical_device_features: PDF = .{};
    if (instance.has_properties_2) {
        stats.pNext = physical_device_features.chain_supported(all_extension_names);
        vk.vkGetPhysicalDeviceFeatures2KHR.?(physical_device.device, &features_2);
    } else vk.vkGetPhysicalDeviceFeatures.?(physical_device.device, &features_2.features);

    // TODO add a robustness2 check for older dxvk/vkd3d databases.
    // TODO filter feateres_2 and extension_names based on the device_features2
    _ = device_features2;

    const enabled_layers = if (enable_validation) &VK_VALIDATION_LAYERS_NAMES else &.{};

    const create_info = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_info,
        .queueCreateInfoCount = 1,
        .ppEnabledLayerNames = @ptrCast(enabled_layers.ptr),
        .enabledLayerCount = @as(u32, @intCast(enabled_layers.len)),
        .ppEnabledExtensionNames = all_extension_names.ptr,
        .enabledExtensionCount = @as(u32, @intCast(all_extension_names.len)),
        .pEnabledFeatures = if (instance.has_properties_2) null else &features_2.features,
        .pNext = if (instance.has_properties_2) &features_2 else null,
    };

    var vk_device: vk.VkDevice = undefined;
    try vu.check_result(vk.vkCreateDevice.?(
        physical_device.device,
        &create_info,
        null,
        &vk_device,
    ));
    return vk_device;
}

pub fn create_vk_sampler(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkSamplerCreateInfo,
) !vk.VkSampler {
    var sampler: vk.VkSampler = undefined;
    try vu.check_result(vk.vkCreateSampler.?(
        vk_device,
        create_info,
        null,
        &sampler,
    ));
    return sampler;
}

pub fn destroy_vk_sampler(
    vk_device: vk.VkDevice,
    sampler: vk.VkSampler,
) void {
    vk.vkDestroySampler.?(vk_device, sampler, null);
}

pub fn create_descriptor_set_layout(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkDescriptorSetLayoutCreateInfo,
) !vk.VkDescriptorSetLayout {
    var descriptor_set_layout: vk.VkDescriptorSetLayout = undefined;
    try vu.check_result(vk.vkCreateDescriptorSetLayout.?(
        vk_device,
        create_info,
        null,
        &descriptor_set_layout,
    ));
    return descriptor_set_layout;
}

pub fn destroy_descriptor_set_layout(
    vk_device: vk.VkDevice,
    layout: vk.VkDescriptorSetLayout,
) void {
    vk.vkDestroyDescriptorSetLayout.?(vk_device, layout, null);
}

pub fn create_pipeline_layout(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkPipelineLayoutCreateInfo,
) !vk.VkPipelineLayout {
    var pipeline_layout: vk.VkPipelineLayout = undefined;
    try vu.check_result(vk.vkCreatePipelineLayout.?(
        vk_device,
        create_info,
        null,
        &pipeline_layout,
    ));
    return pipeline_layout;
}

pub fn destroy_pipeline_layout(
    vk_device: vk.VkDevice,
    layout: vk.VkPipelineLayout,
) void {
    vk.vkDestroyPipelineLayout.?(vk_device, layout, null);
}

pub fn create_shader_module(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkShaderModuleCreateInfo,
) !vk.VkShaderModule {
    var shader_module: vk.VkShaderModule = undefined;
    try vu.check_result(vk.vkCreateShaderModule.?(
        vk_device,
        create_info,
        null,
        &shader_module,
    ));
    return shader_module;
}

pub fn destroy_shader_module(
    vk_device: vk.VkDevice,
    shader_module: vk.VkShaderModule,
) void {
    vk.vkDestroyShaderModule.?(vk_device, shader_module, null);
}

pub fn create_render_pass(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkRenderPassCreateInfo,
) !vk.VkRenderPass {
    var render_pass: vk.VkRenderPass = undefined;
    try vu.check_result(vk.vkCreateRenderPass.?(
        vk_device,
        create_info,
        null,
        &render_pass,
    ));
    return render_pass;
}

pub fn destroy_render_pass(
    vk_device: vk.VkDevice,
    render_pass: vk.VkRenderPass,
) void {
    vk.vkDestroyRenderPass.?(vk_device, render_pass, null);
}

pub fn create_graphics_pipeline(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkGraphicsPipelineCreateInfo,
) !vk.VkPipeline {
    // vu.print_chain(create_info);
    var pipeline: vk.VkPipeline = undefined;
    try vu.check_result(vk.vkCreateGraphicsPipelines.?(
        vk_device,
        null,
        1,
        create_info,
        null,
        &pipeline,
    ));
    return pipeline;
}

pub fn create_compute_pipeline(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkComputePipelineCreateInfo,
) !vk.VkPipeline {
    var pipeline: vk.VkPipeline = undefined;
    try vu.check_result(vk.vkCreateComputePipelines.?(
        vk_device,
        null,
        1,
        create_info,
        null,
        &pipeline,
    ));
    return pipeline;
}

pub fn create_raytracing_pipeline(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkRayTracingPipelineCreateInfoKHR,
) !vk.VkPipeline {
    var pipeline: vk.VkPipeline = undefined;
    try vu.check_result(vk.vkCreateRayTracingPipelinesKHR.?(
        vk_device,
        null,
        null,
        1,
        create_info,
        null,
        &pipeline,
    ));
    return pipeline;
}

pub fn destroy_pipeline(
    vk_device: vk.VkDevice,
    pipeline: vk.VkPipeline,
) void {
    vk.vkDestroyPipeline.?(vk_device, pipeline, null);
}

comptime {
    _ = @import("parsing.zig");
}
