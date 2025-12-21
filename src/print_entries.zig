// Copyright (c) 2025 Egor Lazarchuk
// SPDX-License-Identifier: MIT

const std = @import("std");
const vk = @import("volk");
const log = @import("log.zig");
const args_parser = @import("args_parser.zig");
const parsing = @import("parsing.zig");
const vv = @import("vulkan_validation.zig");
const vulkan = @import("vulkan.zig");
const profiler = @import("profiler.zig");

const Database = @import("database.zig");

const Validation = vv.Validation;
const Allocator = std.mem.Allocator;

pub const log_options = log.Options{
    .level = .Info,
};

pub const profiler_options = profiler.Options{
    .enabled = false,
};

pub const MEASUREMENTS = profiler.Measurements("main", &.{
    "main",
    "process",
    "parse",
    "parse_threaded",
    "create",
    "create_threaded",
});

const ALL_MEASUREMENTS = &.{
    MEASUREMENTS,
    parsing.MEASUREMENTS,
    Database.MEASUREMENTS,
};

const Args = struct {
    output_path: ?[]const u8 = null,
    database_path: args_parser.RemainingArgs = .{},
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

    if (args.database_path.values.len != 1) {
        try args_parser.print_help(Args);
        return;
    }

    const thread_count: u32 = @intCast(std.Thread.getCpuCount() catch 1);
    log.info(@src(), "Using {d} threads", .{thread_count});

    var progress = std.Progress.start(.{});
    defer progress.end();

    var progress_root = progress.start("print_graph", 0);
    defer progress_root.end();

    const db_path = std.mem.span(args.database_path.values[0]);
    var db: Database = try .init(tmp_alloc, &progress_root, db_path);
    _ = tmp_arena.reset(.retain_capacity);

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

    try vv.check_result(vk.volkInitialize());
    const instance = try vulkan.create_vk_instance(
        tmp_alloc,
        parsed_application_info.application_info,
        false,
    );
    vk.volkLoadInstance(instance.instance);

    const physical_device = try vulkan.select_physical_device(
        tmp_alloc,
        instance.instance,
        false,
    );
    var pdf: vk.VkPhysicalDeviceFeatures2 = .{};
    var additional_pdf: vv.AdditionalPDF = .{};
    const device = try vulkan.create_vk_device(
        tmp_alloc,
        &instance,
        &physical_device,
        parsed_application_info.application_info,
        parsed_application_info.device_features2,
        &pdf,
        &additional_pdf,
        false,
    );
    const extensions: vv.Extensions = try .init(
        tmp_alloc,
        instance.api_version,
        instance.all_extension_names,
        device.all_extension_names,
    );
    _ = tmp_arena.reset(.retain_capacity);

    const validation: Validation = .{
        .api_version = instance.api_version,
        .extensions = &extensions,
        .pdf = &pdf,
        .additional_pdf = &additional_pdf,
    };

    const graphics_pipelines = db.entries.getPtrConst(.graphics_pipeline).values().len;
    const compute_pipelines = db.entries.getPtrConst(.compute_pipeline).values().len;
    const raytracing_pipelines = db.entries.getPtrConst(.raytracing_pipeline).values().len;
    const total_pipelines = graphics_pipelines + compute_pipelines + raytracing_pipelines;
    const root_entries: []RootEntry = try arena_alloc.alloc(RootEntry, total_pipelines);
    var re = root_entries;
    for (
        db.entries.getPtr(.graphics_pipeline).values(),
        re[0..graphics_pipelines],
    ) |*entry, *root|
        root.* = .{ .entry = entry, .arena = .init(std.heap.page_allocator) };
    re = re[graphics_pipelines..];
    for (
        db.entries.getPtr(.compute_pipeline).values(),
        re[0..compute_pipelines],
    ) |*entry, *root|
        root.* = .{ .entry = entry, .arena = .init(std.heap.page_allocator) };
    re = re[compute_pipelines..];
    for (
        db.entries.getPtr(.raytracing_pipeline).values(),
        re[0..raytracing_pipelines],
    ) |*entry, *root|
        root.* = .{ .entry = entry, .arena = .init(std.heap.page_allocator) };

    var work_queue: WorkQueue = .{ .entries = root_entries };

    var shared_arena: std.heap.ThreadSafeAllocator = .{ .child_allocator = db.arena.allocator() };
    const shared_alloc = shared_arena.allocator();
    const contexts = try init_contexts(
        arena_alloc,
        shared_alloc,
        &progress_root,
        &db,
        &work_queue,
        thread_count,
        &validation,
    );
    // Reuse already existing arena
    contexts[0].arena = tmp_arena;

    const secondary_threads = try spawn_secondary_threads(
        arena_alloc,
        secondary_thread_process,
        contexts[1..],
    );
    process(&contexts[0]);
    for (secondary_threads) |st| st.join();

    for (std.enums.values(Database.Entry.Tag)) |tag| {
        const entries = db.entries.getPtrConst(tag).values();
        log.output("#### {t} ####\n", .{tag});
        for (entries) |entry| try entry.print_graph(&db);
    }

    var total_used_bytes = arena.queryCapacity() + tmp_arena.queryCapacity() +
        db.arena.queryCapacity();
    for (contexts) |*c| total_used_bytes += c.arena.queryCapacity();
    log.info(@src(), "Total allocators memory: {d}MB", .{total_used_bytes / 1024 / 1024});
    const rusage = std.posix.getrusage(0);
    log.info(@src(), "Resource usage: max rss: {d}MB minor faults: {d} major faults: {d}", .{
        @as(usize, @intCast(rusage.maxrss)) / 1024,
        rusage.minflt,
        rusage.majflt,
    });
}

pub const Context = struct {
    arena: std.heap.ArenaAllocator,
    shared_alloc: Allocator,
    progress: *std.Progress.Node,
    db: *Database,
    work_queue: *WorkQueue,
    thread_count: u32,
    validation: *const Validation,
};

pub fn init_contexts(
    alloc: Allocator,
    shared_alloc: Allocator,
    progress: *std.Progress.Node,
    db: *Database,
    work_queue: *WorkQueue,
    thread_count: u32,
    validation: *const Validation,
) ![]align(64) Context {
    const contexts = try alloc.alignedAlloc(Context, .@"64", thread_count);
    for (contexts) |*c| {
        c.* = .{
            .arena = .init(std.heap.page_allocator),
            .shared_alloc = shared_alloc,
            .progress = progress,
            .db = db,
            .work_queue = work_queue,
            .thread_count = thread_count,
            .validation = validation,
        };
    }
    return contexts;
}

fn spawn_secondary_threads(
    alloc: Allocator,
    comptime function: fn (*Context) void,
    contexts: []Context,
) ![]std.Thread {
    const threads = try alloc.alloc(std.Thread, contexts.len);
    for (threads, contexts) |*t, *c| t.* = try std.Thread.spawn(.{}, function, .{c});
    return threads;
}

const RootEntry = struct {
    entry: *Database.Entry,
    arena: std.heap.ArenaAllocator,
};

const WorkQueue = struct {
    entries: []RootEntry,
    next_parse: std.atomic.Value(u32) = .init(0),

    const Self = @This();
    fn take_next_parse(self: *Self) ?*RootEntry {
        var result: ?*RootEntry = null;
        const next = self.next_parse.fetchAdd(1, .acq_rel);
        if (next < self.entries.len) result = &self.entries[next];
        return result;
    }
};

pub fn secondary_thread_process(context: *Context) void {
    profiler.start_measurement();
    defer profiler.end_measurement();

    process(context);
}

pub fn process(context: *Context) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    parse(context);
}

const Task = struct {
    root_entry: *RootEntry = undefined,
    in_progress: bool = false,
    queue: std.ArrayListUnmanaged(struct { *Database.Entry, u32 }) = .empty,
    arena: std.heap.ArenaAllocator = undefined,
};
const Tasks = struct {
    tasks: [MAX_TASKS]Task = .{Task{}} ** MAX_TASKS,
    current: u8 = 0,

    const MAX_TASKS = 8;
    const Self = @This();

    fn next(self: *Self) *Task {
        const task = &self.tasks[self.current];
        self.current += 1;
        self.current %= MAX_TASKS;
        return task;
    }
};

pub fn parse(context: *Context) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    parse_inner(parsing, vv, context) catch unreachable;
}
pub fn parse_inner(comptime P: type, comptime V: type, context: *Context) !void {
    var progress = context.progress.start("parsing", 0);
    defer progress.end();

    const work_queue = context.work_queue;
    const shared_alloc = context.shared_alloc;
    const thread_alloc = context.arena.allocator();
    defer _ = context.arena.reset(.retain_capacity);

    var gpa_allocator: std.heap.DebugAllocator(.{}) = .{ .backing_allocator = thread_alloc };
    const gpa_alloc = gpa_allocator.allocator();

    var in_progress: u8 = 0;
    var tasks: Tasks = .{};
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
                    in_progress -= 1;
                    task.in_progress = false;
                    break;
                },
            }
        } else {
            in_progress -= 1;
            task.in_progress = false;
        }
    }
}
