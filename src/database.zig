// Copyright (c) 2025 Egor Lazarchuk
//
// Based in part on Fossilize project which is:
// Copyright (c) 2025 Hans-Kristian Arntzen
//
// SPDX-License-Identifier: MIT

const std = @import("std");
const miniz = @import("miniz");
const log = @import("log.zig");

const Allocator = std.mem.Allocator;

file_mem: []const u8,
entries: EntriesType,
arena: std.heap.ArenaAllocator,

const Self = @This();

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

pub fn get_handle(self: *const Self, tag: Entry.Tag, hash: u64) !*anyopaque {
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
        return h
    else {
        log.debug(
            @src(),
            "Attempt to get handle for not yet build object with tag: {s} hash: 0x{x}",
            .{ @tagName(tag), hash },
        );
        return error.NoHandleFound;
    }
}

fn mmap_file(path: []const u8) ![]const u8 {
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

pub fn init(
    tmp_alloc: Allocator,
    progress: *std.Progress.Node,
    path: []const u8,
) !Self {
    log.info(@src(), "Openning database as path: {s}", .{path});
    const file_mem = try mmap_file(path);

    const header: *const Header = @ptrCast(file_mem.ptr);
    if (!std.mem.eql(u8, &header.magic, MAGIC))
        return error.InvalidMagicValue;

    log.info(@src(), "Stored header version: {d}", .{header.version});

    // All database related allocations will be in this arena.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena_alloc = arena.allocator();

    var entries: EntriesType = .initFill(.empty);
    var remaining_file_mem = file_mem[@sizeOf(Header)..];

    const progress_node = progress.start("reading database", 0);
    defer progress_node.end();
    while (0 < remaining_file_mem.len) {
        progress_node.completeOne();
        // If entry is incomplete, stop
        if (remaining_file_mem.len < @sizeOf(Entry))
            break;

        const entry_ptr = remaining_file_mem.ptr;
        const entry: Entry = .from_ptr(entry_ptr);
        const total_entry_size = @sizeOf(Entry) + entry.stored_size;

        // If payload for the entry is incomplete, stop
        if (remaining_file_mem.len < total_entry_size)
            break;

        remaining_file_mem = remaining_file_mem[total_entry_size..];
        const entry_tag = try entry.get_tag();
        // There is no used for these blobs, so skip them.
        if (entry_tag == .APPLICATION_BLOB_LINK)
            continue;

        const payload_start: [*]const u8 =
            @ptrFromInt(@as(usize, @intFromPtr(entry_ptr)) + @sizeOf(Entry));
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
        try entries.getPtr(entry_tag).put(tmp_alloc, try entry.get_value(), .{
            .entry_ptr = entry_ptr,
            .payload = payload,
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
        .file_mem = file_mem,
        .entries = final_entries,
        .arena = arena,
    };
}
