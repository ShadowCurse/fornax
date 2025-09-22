// Copyright (c) 2025 Egor Lazarchuk
// SPDX-License-Identifier: MIT

const std = @import("std");
const vk = @import("volk");
const miniz = @import("miniz");
const log = @import("log.zig");
const vu = @import("vulkan_utils.zig");
const parsing = @import("parsing.zig");
const root = @import("root");

const Allocator = std.mem.Allocator;

file: std.fs.File,
entries: EntriesType,
arena: std.heap.ArenaAllocator,

const Database = @This();

pub const MAGIC = "\x81FOSSILIZEDB";
pub const Header = extern struct {
    magic: [12]u8,
    unused_1: u8,
    unused_2: u8,
    unused_3: u8,
    version: u8,
};

pub const EntriesType = std.EnumArray(
    Entry.Tag,
    std.AutoArrayHashMapUnmanaged(u64, EntryMeta),
);
pub const EntryMeta = struct {
    entry: Entry = undefined,
    payload_file_offset: u32 = undefined,

    dependent_by: u32 = 0,
    status: Status = .not_parsed,
    dependencies: []const Dependency = &.{},
    dependencies_destroyed: u32 = 0,

    create_info: ?*const anyopaque = null,
    handle: ?*anyopaque = null,

    pub const Status = enum(u8) {
        not_parsed,
        parsing,
        parsed,
        creating,
        created,
    };

    pub const Dependency = struct {
        tag: Entry.Tag,
        hash: u64,
        ptr_to_handle: ?*?*anyopaque = null,
    };

    pub fn print_graph(self: *const EntryMeta, db: *const Database) !void {
        const G = struct {
            var padding: u32 = 0;
        };
        const tag = try self.entry.get_tag();
        const hash = try self.entry.get_value();
        for (0..G.padding) |_|
            log.output("    ", .{});
        log.output("{t} hash: 0x{x} depended_by: {d}\n", .{ tag, hash, self.dependent_by });
        for (self.dependencies) |dep| {
            const d = db.entries.getPtrConst(dep.tag).getPtr(dep.hash).?;
            G.padding += 1;
            try d.print_graph(db);
            G.padding -= 1;
        }
    }

    pub fn get_payload(
        self: *const EntryMeta,
        alloc: Allocator,
        tmp_alloc: Allocator,
        db: *const Database,
    ) ![]const u8 {
        switch (self.entry.flags) {
            .NOT_COMPRESSED => {
                const payload = try alloc.alloc(u8, self.entry.stored_size);
                log.assert(
                    @src(),
                    try db.file.pread(payload, self.payload_file_offset) == payload.len,
                    "",
                    .{},
                );
                if (self.entry.crc != 0) {
                    const calculated_crc = miniz.mz_crc32(
                        miniz.MZ_CRC32_INIT,
                        payload.ptr,
                        payload.len,
                    );
                    if (calculated_crc != self.entry.crc)
                        return error.crc_missmatch;
                }
                return payload;
            },
            .COMPRESSED => {
                const payload = try tmp_alloc.alloc(u8, self.entry.stored_size);
                log.assert(
                    @src(),
                    try db.file.pread(payload, self.payload_file_offset) == payload.len,
                    "",
                    .{},
                );
                if (self.entry.crc != 0) {
                    const calculated_crc = miniz.mz_crc32(
                        miniz.MZ_CRC32_INIT,
                        payload.ptr,
                        payload.len,
                    );
                    if (calculated_crc != self.entry.crc)
                        return error.crc_missmatch;
                }

                const decompressed_payload = try alloc.alloc(u8, self.entry.decompressed_size);
                var decompressed_len: u64 = self.entry.decompressed_size;
                if (miniz.mz_uncompress(
                    decompressed_payload.ptr,
                    &decompressed_len,
                    payload.ptr,
                    payload.len,
                ) != miniz.MZ_OK)
                    return error.cannot_uncompress_payload;
                if (decompressed_len != self.entry.decompressed_size)
                    return error.decompressed_size_missmatch;
                return decompressed_payload;
            },
        }
    }

    pub fn parse(
        self: *EntryMeta,
        alloc: Allocator,
        tmp_alloc: Allocator,
        db: *Database,
    ) !bool {
        if (@cmpxchgWeak(Status, &self.status, .not_parsed, .parsing, .seq_cst, .seq_cst)) |old| {
            log.assert(
                @src(),
                old == .parsing or old == .parsed,
                "Encountered strange entry state: {t}",
                .{old},
            );
            const parsed = old == .parsed;
            return parsed;
        }
        // TODO figure out what to do on parsing failure
        defer @atomicStore(Status, &self.status, .parsed, .seq_cst);

        const payload = try self.get_payload(tmp_alloc, tmp_alloc, db);
        const tag = try self.entry.get_tag();
        switch (tag) {
            .APPLICATION_INFO => {},
            .SAMPLER => {
                const result = try parsing.parse_sampler(alloc, tmp_alloc, db, payload);
                self.create_info = @ptrCast(result.create_info);
            },
            .DESCRIPTOR_SET_LAYOUT => {
                const result = try parsing.parse_descriptor_set_layout(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                self.create_info = @ptrCast(result.create_info);
                self.dependencies = result.dependencies;
                for (self.dependencies) |dep| {
                    const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    _ = @atomicRmw(u32, &dep_entry.dependent_by, .Add, 1, .seq_cst);
                }
            },
            .PIPELINE_LAYOUT => {
                const result = try parsing.parse_pipeline_layout(alloc, tmp_alloc, db, payload);
                self.create_info = @ptrCast(result.create_info);
                self.dependencies = result.dependencies;
                for (self.dependencies) |dep| {
                    const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    _ = @atomicRmw(u32, &dep_entry.dependent_by, .Add, 1, .seq_cst);
                }
            },
            .SHADER_MODULE => {
                const result = try parsing.parse_shader_module(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                self.create_info = @ptrCast(result.create_info);
            },
            .RENDER_PASS => {
                const result = try parsing.parse_render_pass(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                self.create_info = @ptrCast(result.create_info);
            },
            .GRAPHICS_PIPELINE => {
                const result = try parsing.parse_graphics_pipeline(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                self.create_info = @ptrCast(result.create_info);
                self.dependencies = result.dependencies;
                for (self.dependencies) |dep| {
                    const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    _ = @atomicRmw(u32, &dep_entry.dependent_by, .Add, 1, .seq_cst);
                }
            },
            .COMPUTE_PIPELINE => {
                const result = try parsing.parse_compute_pipeline(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                self.create_info = @ptrCast(result.create_info);
                self.dependencies = result.dependencies;
                for (self.dependencies) |dep| {
                    const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    _ = @atomicRmw(u32, &dep_entry.dependent_by, .Add, 1, .seq_cst);
                }
            },
            .RAYTRACING_PIPELINE => {
                const result = try parsing.parse_raytracing_pipeline(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                self.create_info = @ptrCast(result.create_info);
                self.dependencies = result.dependencies;
                for (self.dependencies) |dep| {
                    const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    _ = @atomicRmw(u32, &dep_entry.dependent_by, .Add, 1, .seq_cst);
                }
            },
            .APPLICATION_BLOB_LINK => {},
        }
        return true;
    }

    pub const CreateResult = enum {
        dependencies,
        creating,
        created,
    };
    pub fn create(self: *EntryMeta, vk_device: vk.VkDevice, db: *Database) !CreateResult {
        for (self.dependencies) |dep| {
            const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
            const d_status = @atomicLoad(Status, &dep_entry.status, .seq_cst);
            if (d_status != .created) return .dependencies;
        }

        if (@cmpxchgWeak(Status, &self.status, .parsed, .creating, .seq_cst, .seq_cst)) |old| {
            log.assert(
                @src(),
                old == .creating or old == .created,
                "Encountered strange entry state: {t}",
                .{old},
            );
            if (old == .created)
                return .created
            else
                return .creating;
        }
        defer @atomicStore(Status, &self.status, .created, .seq_cst);

        for (self.dependencies) |dep| {
            const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
            dep.ptr_to_handle.?.* = dep_entry.handle;
        }

        const tag = try self.entry.get_tag();
        switch (tag) {
            .APPLICATION_INFO => {},
            .SAMPLER => self.handle = try root.create_vk_sampler(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .DESCRIPTOR_SET_LAYOUT => self.handle = try root.create_descriptor_set_layout(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .PIPELINE_LAYOUT => self.handle = try root.create_pipeline_layout(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .SHADER_MODULE => self.handle = try root.create_shader_module(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .RENDER_PASS => self.handle = try root.create_render_pass(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .GRAPHICS_PIPELINE => self.handle = try root.create_graphics_pipeline(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .COMPUTE_PIPELINE => self.handle = try root.create_compute_pipeline(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .RAYTRACING_PIPELINE => self.handle = try root.create_raytracing_pipeline(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .APPLICATION_BLOB_LINK => {},
        }
        return .created;
    }

    pub fn destroy_dependencies(self: *EntryMeta, vk_device: vk.VkDevice, db: *Database) void {
        if (@cmpxchgWeak(u32, &self.dependencies_destroyed, 0, 1, .seq_cst, .seq_cst)) |_| {
            for (self.dependencies) |dep| {
                const d = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                const old_value = @atomicRmw(u32, &d.dependent_by, .Sub, 1, .seq_cst);
                log.assert(
                    @src(),
                    old_value != 0,
                    "Attempt to destroy object {t} hash: 0x{x} second time",
                    .{ dep.tag, dep.hash },
                );
                if (old_value == 1) {
                    switch (dep.tag) {
                        .APPLICATION_INFO => {},
                        .SAMPLER => root.destroy_vk_sampler(vk_device, @ptrCast(d.handle)),
                        .DESCRIPTOR_SET_LAYOUT => root.destroy_descriptor_set_layout(
                            vk_device,
                            @ptrCast(d.handle),
                        ),
                        .PIPELINE_LAYOUT => root.destroy_pipeline_layout(
                            vk_device,
                            @ptrCast(d.handle),
                        ),
                        .SHADER_MODULE => root.destroy_shader_module(vk_device, @ptrCast(d.handle)),
                        .RENDER_PASS => root.destroy_render_pass(vk_device, @ptrCast(d.handle)),
                        .GRAPHICS_PIPELINE,
                        .COMPUTE_PIPELINE,
                        .RAYTRACING_PIPELINE,
                        => root.destroy_pipeline(vk_device, @ptrCast(d.handle)),
                        .APPLICATION_BLOB_LINK => {},
                    }
                }
            }
            @atomicStore(u32, &self.dependencies_destroyed, 1, .seq_cst);
        }
    }
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

pub const GetHandleResult = union(enum) {
    handle: *anyopaque,
    dependency: EntryMeta.Dependency,
};
pub fn get_handle(self: *const Database, tag: Entry.Tag, hash: u64) !GetHandleResult {
    const entries = self.entries.getPtrConst(tag);
    const entry = entries.getPtr(hash) orelse {
        log.debug(
            @src(),
            "Attempt to get handle for not existing object with tag: {s} hash: 0x{x}",
            .{ @tagName(tag), hash },
        );
        return error.NoObjectFound;
    };
    const handle = @atomicLoad(?*anyopaque, &entry.handle, .seq_cst);
    if (handle) |h|
        return .{ .handle = h }
    else {
        return .{
            .dependency = .{
                .tag = tag,
                .hash = hash,
            },
        };
    }
}

pub fn init(tmp_alloc: Allocator, progress: *std.Progress.Node, path: []const u8) !Database {
    log.info(@src(), "Openning database as path: {s}", .{path});
    // const file = try std.fs.openFileAbsolute(path, .{});
    const file = try std.fs.cwd().openFile(path, .{});
    const file_stat = try file.stat();

    var header: Header = undefined;
    log.assert(@src(), try file.read(@ptrCast(&header)) == @sizeOf(Header), "", .{});
    if (!std.mem.eql(u8, &header.magic, MAGIC))
        return error.InvalidMagicValue;

    log.info(@src(), "Stored header version: {d}", .{header.version});

    // All database related allocations will be in this arena.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena_alloc = arena.allocator();

    var entries: EntriesType = .initFill(.empty);
    var remaining_file_mem = file_stat.size - @sizeOf(Header);

    const progress_node = progress.start("reading database", 0);
    defer progress_node.end();
    while (0 < remaining_file_mem) {
        progress_node.completeOne();
        // If entry is incomplete, stop
        if (remaining_file_mem < @sizeOf(Entry)) break;

        var entry: Entry = undefined;
        log.assert(@src(), try file.read(@ptrCast(&entry)) == @sizeOf(Entry), "", .{});
        remaining_file_mem -= @sizeOf(Entry);

        // If payload for the entry is incomplete, stop
        if (remaining_file_mem < entry.stored_size) break;
        try file.seekBy(entry.stored_size);

        const payload_file_offset: u64 = file_stat.size - remaining_file_mem;
        remaining_file_mem -= entry.stored_size;
        const entry_tag = try entry.get_tag();
        // There is no used for these blobs, so skip them.
        if (entry_tag == .APPLICATION_BLOB_LINK)
            continue;

        try entries.getPtr(entry_tag).put(tmp_alloc, try entry.get_value(), .{
            .entry = entry,
            .payload_file_offset = @intCast(payload_file_offset),
        });
    }

    var final_entries: EntriesType = undefined;
    var fe_iter = final_entries.iterator();
    while (fe_iter.next()) |e| {
        const map = entries.getPtrConst(e.key);
        log.info(@src(), "Found {s:<21} {d:>5}", .{ @tagName(e.key), map.count() });
        e.value.* = try map.clone(arena_alloc);
    }
    return .{
        .file = file,
        .entries = final_entries,
        .arena = arena,
    };
}
