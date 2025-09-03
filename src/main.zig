// Copyright (c) 2025 Egor Lazarchuk
//
// Based in part on Fossilize project which is:
// Copyright (c) 2025 Hans-Kristian Arntzen
//
// SPDX-License-Identifier: MIT

const std = @import("std");
const vk = @import("volk.zig");
const log = @import("log.zig");
const miniz = @import("miniz.zig");
const args_parser = @import("args_parser.zig");
const parsing = @import("parsing.zig");
const PDF = @import("physical_device_features.zig");
const vulkan_print = @import("vulkan_print.zig");

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
    shmem_fd: ?u32 = null,
    control_fd: ?u32 = null,
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
    var gpa = std.heap.DebugAllocator(.{ .enable_memory_limit = true }).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const arena_alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const tmp_alloc = tmp_arena.allocator();

    const args = try args_parser.parse(Args, arena_alloc);
    if (args.help or
        args.database_paths.values.len == 0)
    {
        try args_parser.print_help(Args);
        return;
    }

    var progress = std.Progress.start(.{});
    defer progress.end();

    const db_path = std.mem.span(args.database_paths.values[0]);
    const db = try open_database(gpa_alloc, tmp_alloc, &progress, db_path);

    const app_infos = db.entries.getPtrConst(.APPLICATION_INFO).values();
    if (app_infos.len == 0)
        return error.NoApplicationInfoInTheDatabase;
    const app_info_json = app_infos[0].payload;
    const parsed_application_info = parsing.parse_application_info(
        tmp_alloc,
        tmp_alloc,
        app_info_json,
    ) catch |err| {
        log.err(
            @src(),
            "Encountered error {} while parsing application info json: {s}",
            .{ err, app_info_json },
        );
        return err;
    };
    if (parsed_application_info.version != 6)
        return error.ApllicationInfoVersionMissmatch;

    try vk.check_result(vk.volkInitialize());
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

    try replay_samplers(&tmp_arena, &progress, &db, vk_device);
    try replay_descriptor_sets(&tmp_arena, &progress, &db, vk_device);
    try replay_pipeline_layouts(&tmp_arena, &progress, &db, vk_device);
    try replay_render_passes(&tmp_arena, &progress, &db, vk_device);

    var wait_group: std.Thread.WaitGroup = .{};
    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{
        .allocator = tmp_alloc,
    });

    const host_threads = std.Thread.getCpuCount() catch 1;
    const n_threads = if (args.num_threads) |nt| blk: {
        if (nt == 0) {
            log.info(
                @src(),
                "Provided num_threads is 0. Setting to max host threads {d}",
                .{host_threads},
            );
            break :blk host_threads;
        } else {
            break :blk nt;
        }
    } else host_threads;
    const thread_arenas = try arena_alloc.alloc(std.heap.ArenaAllocator, n_threads);
    for (thread_arenas) |*ta|
        ta.* = .init(std.heap.page_allocator);

    try replay_shader_modules(
        &wait_group,
        &thread_pool,
        thread_arenas,
        &progress,
        &db,
        vk_device,
    );
    wait_group.reset();
    try replay_graphics_pipelines(
        &tmp_arena,
        &wait_group,
        &thread_pool,
        thread_arenas,
        &progress,
        &db,
        vk_device,
    );

    var total_used_bytes = gpa.total_requested_bytes;
    for (thread_arenas) |*ta|
        total_used_bytes += ta.queryCapacity();
    log.info(@src(), "Total memory usage: {d}MB", .{total_used_bytes / 1024 / 1024});
}

pub fn mmap_file(path: []const u8) ![]const u8 {
    const fd = try std.posix.open(path, .{ .ACCMODE = .RDONLY }, 0);
    defer std.posix.close(fd);

    const stat = try std.posix.fstat(fd);
    const mem = try std.posix.mmap(
        null,
        @intCast(stat.size),
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        fd,
        0,
    );
    return mem;
}

pub const Database = struct {
    file_mem: []const u8,
    entries: EntriesType,
    arena: std.heap.ArenaAllocator,

    pub const MAGIC = "\x81FOSSILIZEDB";
    pub const Header = extern struct {
        magic: [12]u8,
        unused_1: u8,
        unused_2: u8,
        unused_3: u8,
        version: u8,
    };

    pub const EntriesType = std.EnumArray(
        Database.Entry.Tag,
        std.AutoArrayHashMapUnmanaged(u64, Database.EntryMeta),
    );
    pub const EntryMeta = struct {
        entry_ptr: [*]const u8,
        payload: []const u8,
        handle: ?*anyopaque = null,
    };
    pub const Entry = extern struct {
        // 8 bytes: ???
        // 16 bytes: tag
        // 16 bytes: value
        tag_hash: [40]u8,
        stored_size: u32,
        flags: Flags,
        crc: u32,
        decompressed_size: u32,
        // payload of `stored_size` size

        pub const Tag = enum(u8) {
            APPLICATION_INFO = 0,
            SAMPLER = 1,
            DESCRIPTOR_SET_LAYOUT = 2,
            PIPELINE_LAYOUT = 3,
            SHADER_MODULE = 4,
            RENDER_PASS = 5,
            GRAPHICS_PIPELINE = 6,
            COMPUTE_PIPELINE = 7,
            APPLICATION_BLOB_LINK = 8,
            RAYTRACING_PIPELINE = 9,
        };

        pub const Flags = enum(u32) {
            NOT_COMPRESSED = 1,
            COMPRESSED = 2,
        };

        pub fn from_ptr(ptr: [*]const u8) Entry {
            var entry: Entry = undefined;
            const entry_bytes = std.mem.asBytes(&entry);
            var ptr_bytes: []const u8 = undefined;
            ptr_bytes.ptr = ptr;
            ptr_bytes.len = @sizeOf(Entry);
            @memcpy(entry_bytes, ptr_bytes);
            return entry;
        }

        pub fn get_tag(entry: *const Entry) !Tag {
            const tag_str = entry.tag_hash[8..24];
            const tag_value = try std.fmt.parseInt(u8, tag_str, 16);
            return @enumFromInt(tag_value);
        }

        pub fn get_value(entry: *const Entry) !u64 {
            const value_str = entry.tag_hash[24..];
            return std.fmt.parseInt(u64, value_str, 16);
        }

        pub fn format(
            value: *const Entry,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print(
                "tag: {s:<21} value: 0x{x:<16} stored_size: {d:<6} flags: {s:<14} crc: {d:<10} decompressed_size: {d}",
                .{
                    @tagName(try value.get_tag()),
                    try value.get_value(),
                    value.stored_size,
                    @tagName(value.flags),
                    value.crc,
                    value.decompressed_size,
                },
            );
        }
    };

    pub fn get_handle(self: *const Database, tag: Entry.Tag, hash: u64) !*anyopaque {
        const entries = self.entries.getPtrConst(tag);
        const entry = entries.getPtr(hash) orelse {
            log.debug(
                @src(),
                "Attempt to get handle for not existing object with tag: {s} hash: 0x{x}",
                .{ @tagName(tag), hash },
            );
            return error.NoObjectFound;
        };
        if (entry.handle) |handle|
            return handle
        else {
            log.debug(
                @src(),
                "Attempt to get handle for not yet build object with tag: {s} hash: 0x{x}",
                .{ @tagName(tag), hash },
            );
            return error.NoHandleFound;
        }
    }
};

pub fn open_database(
    gpa_alloc: Allocator,
    scratch_alloc: Allocator,
    progress: *std.Progress.Node,
    path: []const u8,
) !Database {
    log.info(@src(), "Openning database as path: {s}", .{path});
    const file_mem = try mmap_file(path);

    const header: *const Database.Header = @ptrCast(file_mem.ptr);
    if (!std.mem.eql(u8, &header.magic, Database.MAGIC))
        return error.InvalidMagicValue;

    log.info(@src(), "Stored header version: {d}", .{header.version});

    // All database related allocations will be in this arena.
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const arena_alloc = arena.allocator();

    var entries: Database.EntriesType = .initFill(.empty);
    var remaining_file_mem = file_mem[@sizeOf(Database.Header)..];

    const progress_node = progress.start("reading database", 0);
    defer progress_node.end();
    while (0 < remaining_file_mem.len) {
        progress_node.completeOne();
        // If entry is incomplete, stop
        if (remaining_file_mem.len < @sizeOf(Database.Entry))
            break;

        const entry_ptr = remaining_file_mem.ptr;
        const entry: Database.Entry = .from_ptr(entry_ptr);
        const total_entry_size = @sizeOf(Database.Entry) + entry.stored_size;

        // If payload for the entry is incomplete, stop
        if (remaining_file_mem.len < total_entry_size)
            break;

        remaining_file_mem = remaining_file_mem[total_entry_size..];
        const entry_tag = try entry.get_tag();
        // There is no used for these blobs, so skip them.
        if (entry_tag == .APPLICATION_BLOB_LINK)
            continue;

        const payload_start: [*]const u8 =
            @ptrFromInt(@as(usize, @intFromPtr(entry_ptr)) + @sizeOf(Database.Entry));
        // CRC validation
        if (entry.crc != 0) {
            const calculated_crc = miniz.mz_crc32(miniz.MZ_CRC32_INIT, payload_start, entry.stored_size);
            if (calculated_crc != entry.crc)
                return error.crc_missmatch;
        }
        const payload = switch (entry.flags) {
            .NOT_COMPRESSED => blk: {
                var payload: []const u8 = undefined;
                payload.ptr = payload_start;
                payload.len = entry.stored_size;
                break :blk payload;
            },
            .COMPRESSED => blk: {
                const decompressed_payload = try arena_alloc.alloc(u8, entry.decompressed_size);
                var decompressed_len: u64 = entry.decompressed_size;
                if (miniz.mz_uncompress(
                    decompressed_payload.ptr,
                    &decompressed_len,
                    payload_start,
                    entry.stored_size,
                ) != miniz.MZ_OK)
                    return error.cannot_uncompress_payload;
                if (decompressed_len != entry.decompressed_size)
                    return error.decompressed_size_missmatch;
                break :blk decompressed_payload;
            },
        };
        try entries.getPtr(entry_tag).put(scratch_alloc, try entry.get_value(), .{
            .entry_ptr = entry_ptr,
            .payload = payload,
        });
    }

    var final_entries: Database.EntriesType = undefined;
    var fe_iter = final_entries.iterator();
    while (fe_iter.next()) |e| {
        const map = entries.getPtrConst(e.key);
        log.info(@src(), "Found {d} entries for tag: {s}", .{ map.count(), @tagName(e.key) });
        e.value.* = try map.clone(arena_alloc);
    }
    return .{
        .file_mem = file_mem,
        .entries = final_entries,
        .arena = arena,
    };
}

pub fn print_dt(start: std.time.Instant) void {
    const now = std.time.Instant.now() catch unreachable;
    const dt = @as(f64, @floatFromInt(now.since(start))) / 1000_000.0;
    log.info(@src(), "dt: {d:.3}ms", .{dt});
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

pub fn replay_samplers(
    tmp_allocator: *std.heap.ArenaAllocator,
    progress: *std.Progress.Node,
    db: *const Database,
    vk_device: vk.VkDevice,
) !void {
    const t_start = try std.time.Instant.now();
    defer print_dt(t_start);

    const sub_progress = progress.start("replaying samplers", 0);
    defer sub_progress.end();

    const tmp_alloc = tmp_allocator.allocator();
    const samplers = db.entries.getPtrConst(.SAMPLER).values();
    for (samplers) |*entry| {
        defer sub_progress.completeOne();
        defer _ = tmp_allocator.reset(.retain_capacity);

        const e = Database.Entry.from_ptr(entry.entry_ptr);
        const result = parsing.parse_sampler(
            tmp_alloc,
            tmp_alloc,
            entry.payload,
        ) catch |err| {
            log.err(@src(), "Encountered error {} while parsing sampler", .{err});
            log.debug(@src(), "json: {s}", .{entry.payload});
            return err;
        };
        try check_version_and_hash(result, &e);
        entry.handle = try create_vk_sampler(vk_device, result.create_info);
    }
    log.info(@src(), "Replayed {d} samplers", .{samplers.len});
}

pub fn replay_descriptor_sets(
    tmp_allocator: *std.heap.ArenaAllocator,
    progress: *std.Progress.Node,
    db: *const Database,
    vk_device: vk.VkDevice,
) !void {
    const t_start = try std.time.Instant.now();
    defer print_dt(t_start);

    const sub_progress = progress.start("replaying descripot set layouts", 0);
    defer sub_progress.end();

    const tmp_alloc = tmp_allocator.allocator();
    const descriptor_set_layouts = db.entries.getPtrConst(.DESCRIPTOR_SET_LAYOUT).values();
    for (descriptor_set_layouts) |*entry| {
        defer sub_progress.completeOne();
        defer _ = tmp_allocator.reset(.retain_capacity);

        const e = Database.Entry.from_ptr(entry.entry_ptr);
        const result = parsing.parse_descriptor_set_layout(
            tmp_alloc,
            tmp_alloc,
            entry.payload,
            db,
        ) catch |err| {
            log.err(@src(), "Encountered error {} while parsing descriptor set layout", .{err});
            log.debug(@src(), "json: {s}", .{entry.payload});
            continue;
        };
        try check_version_and_hash(result, &e);
        entry.handle = try create_descriptor_set_layout(
            vk_device,
            result.create_info,
        );
    }
    log.info(@src(), "Replayed {d} descriptor sets", .{descriptor_set_layouts.len});
}

pub fn replay_pipeline_layouts(
    tmp_allocator: *std.heap.ArenaAllocator,
    progress: *std.Progress.Node,
    db: *const Database,
    vk_device: vk.VkDevice,
) !void {
    const t_start = try std.time.Instant.now();
    defer print_dt(t_start);

    const sub_progress = progress.start("replaying pipeline layouts", 0);
    defer sub_progress.end();

    const tmp_alloc = tmp_allocator.allocator();
    const pipeline_layouts = db.entries.getPtrConst(.PIPELINE_LAYOUT).values();
    for (pipeline_layouts) |*entry| {
        defer sub_progress.completeOne();
        defer _ = tmp_allocator.reset(.retain_capacity);

        const e = Database.Entry.from_ptr(entry.entry_ptr);
        const result = parsing.parse_pipeline_layout(
            tmp_alloc,
            tmp_alloc,
            entry.payload,
            db,
        ) catch |err| {
            log.err(@src(), "Encountered error {} while parsing pipeline layout", .{err});
            log.debug(@src(), "json: {s}", .{entry.payload});
            continue;
        };
        try check_version_and_hash(result, &e);
        entry.handle = try create_pipeline_layout(vk_device, result.create_info);
    }
    log.info(@src(), "Replayed {d} pipeline layouts", .{pipeline_layouts.len});
}

pub fn replay_shader_modules_chunk(
    thread_arena: *std.heap.ArenaAllocator,
    chunk: []Database.EntryMeta,
    vk_device: vk.VkDevice,
) void {
    const tmp_alloc = thread_arena.allocator();
    for (chunk) |*entry| {
        defer _ = thread_arena.reset(.retain_capacity);

        const e = Database.Entry.from_ptr(entry.entry_ptr);
        const result = parsing.parse_shader_module(
            tmp_alloc,
            tmp_alloc,
            entry.payload,
        ) catch |err| {
            const json_str = std.mem.span(@as([*c]const u8, @ptrCast(entry.payload.ptr)));
            log.err(@src(), "Encountered error {} while parsing shader module", .{err});
            log.debug(@src(), "json: {s}", .{json_str});
            break;
        };
        check_version_and_hash(result, &e) catch break;
        entry.handle = create_shader_module(vk_device, result.create_info) catch |err| {
            log.err(@src(), "Encountered error during shader module creation: {any}", .{err});
            vulkan_print.print_struct(result.create_info);
            break;
        };
    }
}

pub fn replay_shader_modules(
    wait_group: *std.Thread.WaitGroup,
    thread_pool: *std.Thread.Pool,
    thread_arenas: []std.heap.ArenaAllocator,
    progress: *std.Progress.Node,
    db: *const Database,
    vk_device: vk.VkDevice,
) !void {
    const t_start = try std.time.Instant.now();
    defer print_dt(t_start);

    const sub_progress = progress.start("replaying shader modules", 0);
    defer sub_progress.end();

    const shader_modules = db.entries.getPtrConst(.SHADER_MODULE).values();
    const chunk_size = shader_modules.len / (thread_arenas.len - 1);
    var remaining_shader_modules = shader_modules;
    for (thread_arenas[1..]) |*ta| {
        const chunk = remaining_shader_modules[0..chunk_size];
        remaining_shader_modules = remaining_shader_modules[chunk_size..];
        thread_pool.spawnWg(
            wait_group,
            replay_shader_modules_chunk,
            .{ ta, chunk, vk_device },
        );
    }
    thread_pool.spawnWg(
        wait_group,
        replay_shader_modules_chunk,
        .{ &thread_arenas[0], remaining_shader_modules, vk_device },
    );
    wait_group.wait();

    log.info(@src(), "Replayed {d} shader modules", .{shader_modules.len});
}

pub fn replay_render_passes(
    tmp_allocator: *std.heap.ArenaAllocator,
    progress: *std.Progress.Node,
    db: *const Database,
    vk_device: vk.VkDevice,
) !void {
    const t_start = try std.time.Instant.now();
    defer print_dt(t_start);

    const sub_progress = progress.start("replaying render passes", 0);
    defer sub_progress.end();

    const tmp_alloc = tmp_allocator.allocator();
    const render_passes = db.entries.getPtrConst(.RENDER_PASS).values();
    for (render_passes) |*entry| {
        defer sub_progress.completeOne();
        defer _ = tmp_allocator.reset(.retain_capacity);

        const e = Database.Entry.from_ptr(entry.entry_ptr);
        const result = parsing.parse_render_pass(
            tmp_alloc,
            tmp_alloc,
            entry.payload,
        ) catch |err| {
            log.err(@src(), "Encountered error {} while parsing render pass", .{err});
            log.debug(@src(), "json: {s}", .{entry.payload});
            return err;
        };
        try check_version_and_hash(result, &e);
        entry.handle = try create_render_pass(vk_device, result.create_info);
    }
    log.info(@src(), "Replayed {d} render passes", .{render_passes.len});
}

pub fn replay_graphics_pipeline(
    tmp_alloc: Allocator,
    entry: *Database.EntryMeta,
    db: *const Database,
    vk_device: vk.VkDevice,
) !bool {
    const e = Database.Entry.from_ptr(entry.entry_ptr);
    const result = parsing.parse_graphics_pipeline(
        tmp_alloc,
        tmp_alloc,
        entry.payload,
        db,
    ) catch |err| {
        if (err != error.NoHandleFound) {
            if (err == error.InvalidJson)
                log.err(@src(), "Encountered error {} while parsing graphics pipeline", .{err})
            else
                log.warn(@src(), "Encountered error {} while parsing graphics pipeline", .{err});
            log.debug(@src(), "json: {s}", .{entry.payload});
            return err;
        } else return true;
    };
    try check_version_and_hash(result, &e);
    entry.handle = create_graphics_pipeline(vk_device, result.create_info) catch |err| {
        vulkan_print.print_struct(result.create_info);
        return err;
    };
    return false;
}

pub fn replay_graphics_pipeline_chunk(
    thread_arena: *std.heap.ArenaAllocator,
    chunk: []Database.EntryMeta,
    vk_device: vk.VkDevice,
    db: *const Database,
    deferred_queue: *std.ArrayListUnmanaged(*Database.EntryMeta),
    progress: *std.Progress.Node,
) void {
    const thread_alloc = thread_arena.allocator();

    var sub_progress = progress.start("replaying graphics pipelines", chunk.len);
    defer sub_progress.end();

    const queue_buffer = thread_alloc.alloc(*Database.EntryMeta, chunk.len) catch unreachable;
    deferred_queue.* = .initBuffer(queue_buffer);

    var tmp_allocator = std.heap.ArenaAllocator.init(thread_alloc);
    const tmp_alloc = tmp_allocator.allocator();
    for (chunk) |*gp| {
        defer _ = tmp_allocator.reset(.retain_capacity);
        defer sub_progress.completeOne();

        const deferred = replay_graphics_pipeline(tmp_alloc, gp, db, vk_device) catch break;
        if (deferred)
            deferred_queue.appendAssumeCapacity(gp);
    }
}

pub fn replay_graphics_pipelines(
    tmp_allocator: *std.heap.ArenaAllocator,
    wait_group: *std.Thread.WaitGroup,
    thread_pool: *std.Thread.Pool,
    thread_arenas: []std.heap.ArenaAllocator,
    progress: *std.Progress.Node,
    db: *const Database,
    vk_device: vk.VkDevice,
) !void {
    const t_start = try std.time.Instant.now();
    defer print_dt(t_start);

    const tmp_alloc = tmp_allocator.allocator();
    const thread_deferred_queues = try tmp_alloc.alloc(
        std.ArrayListUnmanaged(*Database.EntryMeta),
        thread_arenas.len,
    );

    const graphics_pipelines = db.entries.getPtrConst(.GRAPHICS_PIPELINE).values();
    const chunk_size = graphics_pipelines.len / (thread_arenas.len - 1);
    var remaining_graphics_pipelines = graphics_pipelines;
    for (thread_arenas[1..], thread_deferred_queues[1..]) |*ta, *dq| {
        const chunk = remaining_graphics_pipelines[0..chunk_size];
        remaining_graphics_pipelines = remaining_graphics_pipelines[chunk_size..];
        thread_pool.spawnWg(
            wait_group,
            replay_graphics_pipeline_chunk,
            .{ ta, chunk, vk_device, db, dq, progress },
        );
    }
    thread_pool.spawnWg(
        wait_group,
        replay_graphics_pipeline_chunk,
        .{
            &thread_arenas[0],
            remaining_graphics_pipelines,
            vk_device,
            db,
            &thread_deferred_queues[0],
            progress,
        },
    );
    wait_group.wait();

    var deferred_queue: std.ArrayListUnmanaged(*Database.EntryMeta) = .empty;
    for (thread_deferred_queues) |*tdq|
        for (tdq.items) |i|
            try deferred_queue.append(tmp_alloc, i);

    log.info(@src(), "Processing deferred pipelines: {d}", .{deferred_queue.items.len});
    var sub_progress = progress.start(
        "replaying deferred graphics pipelines",
        deferred_queue.items.len,
    );
    defer sub_progress.end();
    while (deferred_queue.pop()) |gp| {
        defer sub_progress.completeOne();
        defer _ = tmp_allocator.reset(.retain_capacity);
        if (try replay_graphics_pipeline(tmp_alloc, gp, db, vk_device))
            try deferred_queue.append(tmp_alloc, gp);
    }
    log.info(@src(), "Replayed {d} graphics pipelines", .{graphics_pipelines.len});
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
    try vk.check_result(vk.vkEnumerateInstanceExtensionProperties.?(
        null,
        &extensions_count,
        null,
    ));
    const extensions = try arena_alloc.alloc(vk.VkExtensionProperties, extensions_count);
    try vk.check_result(vk.vkEnumerateInstanceExtensionProperties.?(
        null,
        &extensions_count,
        extensions.ptr,
    ));
    return extensions;
}

pub fn get_instance_layer_properties(arena_alloc: Allocator) ![]const vk.VkLayerProperties {
    var layer_property_count: u32 = 0;
    try vk.check_result(vk.vkEnumerateInstanceLayerProperties.?(&layer_property_count, null));
    const layers = try arena_alloc.alloc(vk.VkLayerProperties, layer_property_count);
    try vk.check_result(vk.vkEnumerateInstanceLayerProperties.?(
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
    const instance_create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = app_info,
        .ppEnabledExtensionNames = all_extension_names.ptr,
        .enabledExtensionCount = @as(u32, @intCast(all_extension_names.len)),
        .ppEnabledLayerNames = @ptrCast(enabled_layers.ptr),
        .enabledLayerCount = @as(u32, @intCast(enabled_layers.len)),
    };

    var vk_instance: vk.VkInstance = undefined;
    try vk.check_result(vk.vkCreateInstance.?(&instance_create_info, null, &vk_instance));
    log.debug(
        @src(),
        "Created instance api version: {}.{}.{} has_properties_2: {}",
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
    try vk.check_result(
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
    try vk.check_result(vk.vkEnumeratePhysicalDevices.?(
        vk_instance,
        &physical_device_count,
        null,
    ));
    const physical_devices = try arena_alloc.alloc(
        vk.VkPhysicalDevice,
        physical_device_count,
    );
    try vk.check_result(vk.vkEnumeratePhysicalDevices.?(
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
    try vk.check_result(vk.vkEnumerateDeviceExtensionProperties.?(
        physical_device,
        extension_name,
        &extensions_count,
        null,
    ));
    const extensions = try arena_alloc.alloc(vk.VkExtensionProperties, extensions_count);
    try vk.check_result(vk.vkEnumerateDeviceExtensionProperties.?(
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
    try vk.check_result(vk.vkEnumerateDeviceLayerProperties.?(
        physical_device,
        &layer_property_count,
        null,
    ));
    const layers = try arena_alloc.alloc(vk.VkLayerProperties, layer_property_count);
    try vk.check_result(vk.vkEnumerateDeviceLayerProperties.?(
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
    try vk.check_result(vk.vkCreateDevice.?(
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
    try vk.check_result(vk.vkCreateSampler.?(
        vk_device,
        create_info,
        null,
        &sampler,
    ));
    return sampler;
}

pub fn create_descriptor_set_layout(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkDescriptorSetLayoutCreateInfo,
) !vk.VkDescriptorSetLayout {
    var descriptor_set_layout: vk.VkDescriptorSetLayout = undefined;
    try vk.check_result(vk.vkCreateDescriptorSetLayout.?(
        vk_device,
        create_info,
        null,
        &descriptor_set_layout,
    ));
    return descriptor_set_layout;
}

pub fn create_pipeline_layout(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkPipelineLayoutCreateInfo,
) !vk.VkPipelineLayout {
    var pipeline_layout: vk.VkPipelineLayout = undefined;
    try vk.check_result(vk.vkCreatePipelineLayout.?(
        vk_device,
        create_info,
        null,
        &pipeline_layout,
    ));
    return pipeline_layout;
}

pub fn create_shader_module(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkShaderModuleCreateInfo,
) !vk.VkShaderModule {
    var shader_module: vk.VkShaderModule = undefined;
    try vk.check_result(vk.vkCreateShaderModule.?(
        vk_device,
        create_info,
        null,
        &shader_module,
    ));
    return shader_module;
}

pub fn create_render_pass(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkRenderPassCreateInfo,
) !vk.VkRenderPass {
    var render_pass: vk.VkRenderPass = undefined;
    try vk.check_result(vk.vkCreateRenderPass.?(
        vk_device,
        create_info,
        null,
        &render_pass,
    ));
    return render_pass;
}

pub fn create_graphics_pipeline(
    vk_device: vk.VkDevice,
    create_info: *const vk.VkGraphicsPipelineCreateInfo,
) !vk.VkPipeline {
    var pipeline: vk.VkPipeline = undefined;
    try vk.check_result(vk.vkCreateGraphicsPipelines.?(
        vk_device,
        null,
        1,
        create_info,
        null,
        &pipeline,
    ));
    return pipeline;
}

test "all" {
    _ = @import("parsing.zig");
}
