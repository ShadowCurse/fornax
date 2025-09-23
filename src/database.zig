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
    std.AutoArrayHashMapUnmanaged(u64, Entry),
);
pub const Entry = struct {
    tag: Tag,
    hash: u64,

    payload_flag: PayloadFlags,
    payload_crc: u32,
    payload_stored_size: u32,
    payload_decompressed_size: u32,
    payload_file_offset: u32 = undefined,

    create_info: ?*const anyopaque = null,
    dependencies: []const Dependency = &.{},
    handle: ?*anyopaque = null,

    // atomicly updated
    dependent_by: u32 = 0,
    status: Status = .not_parsed,
    dependencies_destroyed: bool = false,

    pub const Tag = enum(u8) {
        application_info = 0,
        sampler = 1,
        descriptor_set_layout = 2,
        pipeline_layout = 3,
        shader_module = 4,
        render_pass = 5,
        graphics_pipeline = 6,
        compute_pipeline = 7,
        application_blob_link = 8,
        raytracing_pipeline = 9,
    };

    pub const Status = enum(u8) {
        not_parsed,
        parsing,
        parsed,
        creating,
        created,
    };

    pub const PayloadFlags = enum {
        not_compressed,
        compressed,
    };

    pub const Dependency = struct {
        tag: Tag,
        hash: u64,
        ptr_to_handle: ?*?*anyopaque = null,
    };

    pub fn print_graph(self: *const Entry, db: *const Database) !void {
        const G = struct {
            var padding: u32 = 0;
        };
        for (0..G.padding) |_|
            log.output("    ", .{});
        log.output(
            "{t} hash: 0x{x} depended_by: {d}\n",
            .{ self.tag, self.hash, self.dependent_by },
        );
        for (self.dependencies) |dep| {
            const d = db.entries.getPtrConst(dep.tag).getPtr(dep.hash).?;
            G.padding += 1;
            try d.print_graph(db);
            G.padding -= 1;
        }
    }

    pub fn get_payload(
        self: *const Entry,
        alloc: Allocator,
        tmp_alloc: Allocator,
        db: *const Database,
    ) ![]const u8 {
        switch (self.payload_flag) {
            .not_compressed => {
                const payload = try alloc.alloc(u8, self.payload_stored_size);
                log.assert(
                    @src(),
                    try db.file.pread(payload, self.payload_file_offset) == payload.len,
                    "",
                    .{},
                );
                if (self.payload_crc != 0) {
                    const calculated_crc = miniz.mz_crc32(
                        miniz.MZ_CRC32_INIT,
                        payload.ptr,
                        payload.len,
                    );
                    if (calculated_crc != self.payload_crc)
                        return error.crc_missmatch;
                }
                return payload;
            },
            .compressed => {
                const payload = try tmp_alloc.alloc(u8, self.payload_stored_size);
                log.assert(
                    @src(),
                    try db.file.pread(payload, self.payload_file_offset) == payload.len,
                    "",
                    .{},
                );
                if (self.payload_crc != 0) {
                    const calculated_crc = miniz.mz_crc32(
                        miniz.MZ_CRC32_INIT,
                        payload.ptr,
                        payload.len,
                    );
                    if (calculated_crc != self.payload_crc)
                        return error.crc_missmatch;
                }

                const decompressed_payload = try alloc.alloc(u8, self.payload_decompressed_size);
                var decompressed_len: u64 = self.payload_decompressed_size;
                if (miniz.mz_uncompress(
                    decompressed_payload.ptr,
                    &decompressed_len,
                    payload.ptr,
                    payload.len,
                ) != miniz.MZ_OK)
                    return error.cannot_uncompress_payload;
                if (decompressed_len != self.payload_decompressed_size)
                    return error.decompressed_size_missmatch;
                return decompressed_payload;
            },
        }
    }

    pub fn check_version_and_hash(self: *const Entry, v: anytype) !void {
        if (v.version != 6) {
            log.err(
                @src(),
                "{t} has invalid version: {d} != {d}",
                .{ self.tag, v.version, @as(u32, 6) },
            );
            return error.InvalidVerson;
        }
        if (v.hash != self.hash) {
            log.err(
                @src(),
                "{t} hash not equal to json version: 0x{x} != 0x{x}",
                .{ self.tag, v.hash, self.hash },
            );
            return error.InvalidHash;
        }
    }
    pub fn parse(
        self: *Entry,
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
        switch (self.tag) {
            .application_info => {},
            .sampler => {
                const result = try parsing.parse_sampler(alloc, tmp_alloc, db, payload);
                try self.check_version_and_hash(result);
                self.create_info = @ptrCast(result.create_info);
            },
            .descriptor_set_layout => {
                const result = try parsing.parse_descriptor_set_layout(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.check_version_and_hash(result);
                self.create_info = @ptrCast(result.create_info);
                self.dependencies = result.dependencies;
                for (self.dependencies) |dep| {
                    const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    _ = @atomicRmw(u32, &dep_entry.dependent_by, .Add, 1, .seq_cst);
                }
            },
            .pipeline_layout => {
                const result = try parsing.parse_pipeline_layout(alloc, tmp_alloc, db, payload);
                try self.check_version_and_hash(result);
                self.create_info = @ptrCast(result.create_info);
                self.dependencies = result.dependencies;
                for (self.dependencies) |dep| {
                    const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    _ = @atomicRmw(u32, &dep_entry.dependent_by, .Add, 1, .seq_cst);
                }
            },
            .shader_module => {
                const result = try parsing.parse_shader_module(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.check_version_and_hash(result);
                self.create_info = @ptrCast(result.create_info);
            },
            .render_pass => {
                const result = try parsing.parse_render_pass(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.check_version_and_hash(result);
                self.create_info = @ptrCast(result.create_info);
            },
            .graphics_pipeline => {
                const result = try parsing.parse_graphics_pipeline(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.check_version_and_hash(result);
                self.create_info = @ptrCast(result.create_info);
                self.dependencies = result.dependencies;
                for (self.dependencies) |dep| {
                    const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    _ = @atomicRmw(u32, &dep_entry.dependent_by, .Add, 1, .seq_cst);
                }
            },
            .compute_pipeline => {
                const result = try parsing.parse_compute_pipeline(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.check_version_and_hash(result);
                self.create_info = @ptrCast(result.create_info);
                self.dependencies = result.dependencies;
                for (self.dependencies) |dep| {
                    const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    _ = @atomicRmw(u32, &dep_entry.dependent_by, .Add, 1, .seq_cst);
                }
            },
            .raytracing_pipeline => {
                const result = try parsing.parse_raytracing_pipeline(
                    alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.check_version_and_hash(result);
                self.create_info = @ptrCast(result.create_info);
                self.dependencies = result.dependencies;
                for (self.dependencies) |dep| {
                    const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
                    _ = @atomicRmw(u32, &dep_entry.dependent_by, .Add, 1, .seq_cst);
                }
            },
            .application_blob_link => {},
        }
        return true;
    }

    pub const CreateResult = enum {
        dependencies,
        creating,
        created,
    };
    pub fn create(self: *Entry, vk_device: vk.VkDevice, db: *Database) !CreateResult {
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

        switch (self.tag) {
            .application_info => {},
            .sampler => self.handle = try root.create_vk_sampler(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .descriptor_set_layout => self.handle = try root.create_descriptor_set_layout(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .pipeline_layout => self.handle = try root.create_pipeline_layout(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .shader_module => self.handle = try root.create_shader_module(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .render_pass => self.handle = try root.create_render_pass(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .graphics_pipeline => self.handle = try root.create_graphics_pipeline(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .compute_pipeline => self.handle = try root.create_compute_pipeline(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .raytracing_pipeline => self.handle = try root.create_raytracing_pipeline(
                vk_device,
                @ptrCast(@alignCast(self.create_info)),
            ),
            .application_blob_link => {},
        }
        return .created;
    }

    pub fn destroy_dependencies(self: *Entry, vk_device: vk.VkDevice, db: *Database) void {
        if (@cmpxchgWeak(
            bool,
            &self.dependencies_destroyed,
            false,
            true,
            .seq_cst,
            .seq_cst,
        ) != null)
            return;

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
                    .application_info => {},
                    .sampler => root.destroy_vk_sampler(vk_device, @ptrCast(d.handle)),
                    .descriptor_set_layout => root.destroy_descriptor_set_layout(
                        vk_device,
                        @ptrCast(d.handle),
                    ),
                    .pipeline_layout => root.destroy_pipeline_layout(
                        vk_device,
                        @ptrCast(d.handle),
                    ),
                    .shader_module,
                    => root.destroy_shader_module(vk_device, @ptrCast(d.handle)),
                    .render_pass => root.destroy_render_pass(vk_device, @ptrCast(d.handle)),
                    .graphics_pipeline,
                    .compute_pipeline,
                    .raytracing_pipeline,
                    => root.destroy_pipeline(vk_device, @ptrCast(d.handle)),
                    .application_blob_link => {},
                }
            }
        }
    }
};
pub const FileEntry = extern struct {
    // 8 bytes: ???
    // 16 bytes: tag
    // 16 bytes: value
    tag_hash: [40]u8,
    stored_size: u32,
    flags: Flags,
    crc: u32,
    decompressed_size: u32,
    // payload of `stored_size` size

    pub const Flags = enum(u32) {
        NOT_COMPRESSED = 1,
        COMPRESSED = 2,
    };

    pub fn from_ptr(ptr: [*]const u8) FileEntry {
        var entry: FileEntry = undefined;
        const entry_bytes = std.mem.asBytes(&entry);
        var ptr_bytes: []const u8 = undefined;
        ptr_bytes.ptr = ptr;
        ptr_bytes.len = @sizeOf(FileEntry);
        @memcpy(entry_bytes, ptr_bytes);
        return entry;
    }

    pub fn get_tag(entry: *const FileEntry) !Entry.Tag {
        const tag_str = entry.tag_hash[8..24];
        const tag_value = try std.fmt.parseInt(u8, tag_str, 16);
        return @enumFromInt(tag_value);
    }

    pub fn get_hash(entry: *const FileEntry) !u64 {
        const value_str = entry.tag_hash[24..];
        return std.fmt.parseInt(u64, value_str, 16);
    }

    pub fn format(
        value: *const FileEntry,
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
                try value.get_hash(),
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
    dependency: Entry.Dependency,
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
        if (remaining_file_mem < @sizeOf(FileEntry)) break;

        var entry: FileEntry = undefined;
        log.assert(@src(), try file.read(@ptrCast(&entry)) == @sizeOf(FileEntry), "", .{});
        remaining_file_mem -= @sizeOf(FileEntry);

        // If payload for the entry is incomplete, stop
        if (remaining_file_mem < entry.stored_size) break;
        try file.seekBy(entry.stored_size);

        const payload_file_offset: u64 = file_stat.size - remaining_file_mem;
        remaining_file_mem -= entry.stored_size;
        const entry_tag = try entry.get_tag();
        // There is no used for these blobs, so skip them.
        if (entry_tag == .application_blob_link)
            continue;

        const entry_hash = try entry.get_hash();
        try entries.getPtr(entry_tag).put(tmp_alloc, entry_hash, .{
            .tag = entry_tag,
            .hash = entry_hash,
            .payload_flag = if (entry.flags == .COMPRESSED) .compressed else .not_compressed,
            .payload_crc = entry.crc,
            .payload_stored_size = entry.stored_size,
            .payload_decompressed_size = entry.decompressed_size,
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
