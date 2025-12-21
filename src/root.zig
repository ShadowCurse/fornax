const std = @import("std");
const volk = @import("volk");
const vv = @import("vulkan_validation.zig");

const Allocator = std.mem.Allocator;
const Validation = vv.Validation;
const Database = @import("database.zig");
const Barrier = @import("barrier.zig");

const RootEntry = struct {
    entry: *Database.Entry,
    arena: std.heap.ArenaAllocator,
};
pub fn init_root_entries(alloc: Allocator, db: *Database) ![]RootEntry {
    const graphics_pipelines = db.entries.getPtrConst(.graphics_pipeline).values().len;
    const compute_pipelines = db.entries.getPtrConst(.compute_pipeline).values().len;
    const raytracing_pipelines = db.entries.getPtrConst(.raytracing_pipeline).values().len;

    const total_pipelines = graphics_pipelines + compute_pipelines + raytracing_pipelines;
    const root_entries: []RootEntry = try alloc.alloc(RootEntry, total_pipelines);
    var re = root_entries;
    for (db.entries.getPtr(.graphics_pipeline).values(), re[0..graphics_pipelines]) |*e, *r|
        r.* = .{ .entry = e, .arena = .init(std.heap.page_allocator) };
    re = re[graphics_pipelines..];
    for (db.entries.getPtr(.compute_pipeline).values(), re[0..compute_pipelines]) |*e, *r|
        r.* = .{ .entry = e, .arena = .init(std.heap.page_allocator) };
    re = re[compute_pipelines..];
    for (db.entries.getPtr(.raytracing_pipeline).values(), re[0..raytracing_pipelines]) |*e, *r|
        r.* = .{ .entry = e, .arena = .init(std.heap.page_allocator) };
    return root_entries;
}

pub fn actual_thread_count(num_threads: ?u32) u32 {
    var thread_count: u32 = @truncate(std.Thread.getCpuCount() catch 1);
    if (num_threads) |nt| {
        if (nt != 0) thread_count = nt;
    }
    return thread_count;
}

pub const WorkQueue = struct {
    entries: []RootEntry,
    next_parse: std.atomic.Value(u32) = .init(0),
    next_create: std.atomic.Value(u32) = .init(0),

    const Self = @This();
    pub fn take_next_parse(self: *Self) ?*RootEntry {
        var result: ?*RootEntry = null;
        const next = self.next_parse.fetchAdd(1, .acq_rel);
        if (next < self.entries.len) result = &self.entries[next];
        return result;
    }
    pub fn take_next_create(self: *Self) ?*RootEntry {
        var result: ?*RootEntry = null;
        const next = self.next_create.fetchAdd(1, .acq_rel);
        if (next < self.entries.len) result = &self.entries[next];
        return result;
    }
};

pub const Task = struct {
    root_entry: *RootEntry = undefined,
    queue: std.ArrayListUnmanaged(struct { *Database.Entry, u32 }) = .empty,
    arena: std.heap.ArenaAllocator = undefined,
};
pub const Tasks = struct {
    tasks: [MAX_TASKS]Task = .{Task{}} ** MAX_TASKS,
    current: u8 = 0,

    const MAX_TASKS = 8;
    const Self = @This();

    pub fn next(self: *Self) *Task {
        const task = &self.tasks[self.current];
        self.current += 1;
        self.current %= MAX_TASKS;
        return task;
    }
};

pub const Context = struct {
    arena: std.heap.ArenaAllocator,
    shared_alloc: Allocator,
    progress: *std.Progress.Node,
    barrier: *Barrier,
    db: *Database,
    work_queue: *WorkQueue,
    thread_count: u32,
    validation: *const Validation,
    vk_device: volk.VkDevice,
};

pub fn init_contexts(
    alloc: Allocator,
    shared_alloc: Allocator,
    progress: *std.Progress.Node,
    barrier: *Barrier,
    db: *Database,
    work_queue: *WorkQueue,
    thread_count: u32,
    validation: *const Validation,
    vk_device: volk.VkDevice,
) ![]align(64) Context {
    const contexts = try alloc.alignedAlloc(Context, .@"64", thread_count);
    for (contexts) |*c| {
        c.* = .{
            .arena = .init(std.heap.page_allocator),
            .shared_alloc = shared_alloc,
            .progress = progress,
            .barrier = barrier,
            .db = db,
            .work_queue = work_queue,
            .thread_count = thread_count,
            .validation = validation,
            .vk_device = vk_device,
        };
    }
    return contexts;
}

pub fn spawn_threads(
    alloc: Allocator,
    comptime function: fn (*Context) void,
    contexts: []Context,
) ![]std.Thread {
    const threads = try alloc.alloc(std.Thread, contexts.len);
    for (threads, contexts) |*t, *c| t.* = try std.Thread.spawn(.{}, function, .{c});
    return threads;
}
