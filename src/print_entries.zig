// Copyright (c) 2025 Egor Lazarchuk
// SPDX-License-Identifier: MIT

const std = @import("std");
const root = @import("root.zig");
const vk = @import("volk");
const log = @import("log.zig");
const args_parser = @import("args_parser.zig");
const parsing = @import("parsing.zig");
const vv = @import("vulkan_validation.zig");
const vulkan = @import("vulkan.zig");
const profiler = @import("profiler.zig");

const Database = @import("database.zig");
const Allocator = std.mem.Allocator;

pub const log_options = log.Options{
    .level = .info,
};

pub const profiler_options = profiler.Options{
    .enabled = false,
};

pub const MEASUREMENTS = profiler.Measurements("main", &.{
    "main",
    "process",
    "parse",
});

const ALL_MEASUREMENTS = &.{
    MEASUREMENTS,
    parsing.MEASUREMENTS,
    vulkan.MEASUREMENTS,
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
        args_parser.print_help(Args);
        return;
    }

    const thread_count = root.actual_thread_count(null);
    log.info(@src(), "Using {d} threads", .{thread_count});

    const db_path = std.mem.span(args.database_path.values[0]);
    var db: Database = try .init(tmp_alloc, db_path);
    _ = tmp_arena.reset(.retain_capacity);

    var validation: vv.Validation = undefined;
    const vk_device = try vulkan.init(
        arena_alloc,
        tmp_alloc,
        &db,
        false,
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
    const contexts = try root.init_contexts(
        arena_alloc,
        shared_alloc,
        &progress_root,
        undefined,
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

pub fn secondary_thread_process(context: *root.Context) void {
    profiler.start_measurement();
    defer profiler.end_measurement();

    process(context);
}

pub fn process(context: *root.Context) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    parse(context);
}

pub fn parse(context: *root.Context) void {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    parse_inner(parsing, vv, context) catch unreachable;
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

    var tasks: root.Tasks = .{};
    for (&tasks.tasks) |*t| t.arena = .init(gpa_alloc);
    while (true) {
        defer progress.completeOne();

        const task = tasks.next();
        if (task.queue.items.len == 0) {
            if (work_queue.take_next_parse()) |root_entry| {
                log.debug(
                    @src(),
                    "Adding new parse task: {t} 0x{x:0>16}",
                    .{ root_entry.entry.tag, root_entry.entry.hash },
                );
                task.root_entry = root_entry;
                task.queue = .empty;
                _ = task.arena.reset(.retain_capacity);
                try task.queue.append(task.arena.allocator(), .{ root_entry.entry, 0 });
            }
        }
        for (&tasks.tasks) |*t| {
            if (t.queue.items.len != 0) break;
        } else {
            break;
        }

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
                    while (task.queue.pop()) |t| {
                        const e, _ = t;
                        log.debug(
                            @src(),
                            "Invalidating parent: {t} 0x{x:0>16}",
                            .{ e.tag, e.hash },
                        );
                        e.status.store(.invalid, .release);
                        e.decrement_dependencies();
                    }
                    break;
                },
            }
        } else {
        }
    }
}
