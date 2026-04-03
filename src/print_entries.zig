// Copyright (c) 2026 Egor Lazarchuk
// SPDX-License-Identifier: MIT

const std = @import("std");
const root = @import("root.zig");
const vk = @import("vk.zig");
const log = @import("log.zig");
const args_parser = @import("args_parser.zig");
const parsing = @import("parsing.zig");
const vv = @import("vk_validation.zig");
const vulkan = @import("vulkan.zig");

const Database = @import("database.zig");
const Allocator = std.mem.Allocator;

pub const log_options = log.Options{
    .level = .err,
};

const Args = struct {
    database_path: []const u8 = &.{},
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena_alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const tmp_alloc = tmp_arena.allocator();

    const args = try args_parser.parse(Args, arena_alloc);
    if (args.database_path.len == 0) {
        args_parser.print_help(Args);
        return;
    }

    const thread_count = root.actual_thread_count(null);
    log.info(@src(), "Using {d} threads", .{thread_count});

    var db: Database = try .init(args.database_path);

    var validation: vv.Validation = undefined;
    const vk_instance, const vk_device = try vulkan.init(
        arena_alloc,
        tmp_alloc,
        &db,
        false,
        &validation,
    );
    defer vulkan.deinit(vk_instance, vk_device);
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
    process(context);
}

pub fn process(context: *root.Context) void {
    root.parse(context) catch unreachable;
}
