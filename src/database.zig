// Copyright (c) 2025 Egor Lazarchuk
//
// Based in part on Fossilize project which is:
// Copyright (c) 2025 Hans-Kristian Arntzen
//
// SPDX-License-Identifier: MIT

const std = @import("std");
const vk = @import("volk");
const miniz = @import("miniz");
const log = @import("log.zig");
const parsing = @import("parsing.zig");
const vulkan = @import("vulkan.zig");
const vv = @import("vulkan_validation.zig");
const profiler = @import("profiler.zig");
const crc32 = @import("crc32.zig");

const Validation = vv.Validation;
const Allocator = std.mem.Allocator;

pub const MEASUREMENTS = profiler.Measurements(
    "database",
    profiler.all_function_names_in_struct(@This()) ++
        profiler.all_function_names_in_struct(Entry),
);

file: std.fs.File,
entries: EntriesType,
arena: std.heap.ArenaAllocator,

pub const CrcError = error{CrcMissmatch};
pub const MinizError = error{ CannotUncompressPayload, DecompressedSizeMissmatch };
pub const GetPayloadError = std.fs.File.PReadError ||
    std.mem.Allocator.Error ||
    CrcError ||
    MinizError;

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
    payload_file_offset: u32,

    create_info: ?*align(8) const anyopaque = null,
    dependencies: []const Dependency = &.{},
    handle: ?*anyopaque = null,

    // atomicly updated
    dependent_by: std.atomic.Value(u32) = .init(0),
    status: std.atomic.Value(Status) = .init(.not_parsed),
    dependencies_destroyed: std.atomic.Value(bool) = .init(false),

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
        invalid,
    };

    pub const PayloadFlags = enum {
        not_compressed,
        compressed,
    };

    pub const Dependency = struct {
        entry: *Entry,
        ptr_to_handle: ?*?*anyopaque,
    };

    pub fn print_graph(self: *const Entry, db: *const Database) !void {
        const G = struct {
            var padding: u32 = 0;
        };
        for (0..G.padding) |_|
            log.output("    ", .{});
        log.output(
            "{t} hash: 0x{x:0>16} depended_by: {d}\n",
            .{ self.tag, self.hash, self.dependent_by.raw },
        );
        for (self.dependencies) |dep| {
            G.padding += 1;
            try dep.print_graph(db);
            G.padding -= 1;
        }
    }

    pub fn get_payload(
        self: *const Entry,
        alloc: Allocator,
        tmp_alloc: Allocator,
        db: *const Database,
    ) GetPayloadError![]const u8 {
        const prof_point = MEASUREMENTS.start(@src());
        defer MEASUREMENTS.end(prof_point);

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
                        return error.CrcMissmatch;
                }
                return payload;
            },
            .compressed => {
                const payload = try tmp_alloc.alignedAlloc(u8, .@"64", self.payload_stored_size);
                log.assert(
                    @src(),
                    try db.file.pread(payload, self.payload_file_offset) == payload.len,
                    "",
                    .{},
                );
                if (self.payload_crc != 0) {
                    const calculated_crc = crc32.crc32_simd(0, payload);
                    if (calculated_crc != self.payload_crc)
                        return error.CrcMissmatch;
                }

                const decompressed_payload = try alloc.alloc(u8, self.payload_decompressed_size);
                var decompressed_len: u64 = self.payload_decompressed_size;
                if (miniz.mz_uncompress(
                    decompressed_payload.ptr,
                    &decompressed_len,
                    payload.ptr,
                    payload.len,
                ) != miniz.MZ_OK)
                    return error.CannotUncompressPayload;
                if (decompressed_len != self.payload_decompressed_size)
                    return error.DecompressedSizeMissmatch;
                return decompressed_payload;
            },
        }
    }

    pub fn check_version_and_hash(self: *const Entry, v: anytype) !void {
        if (v.version != 6) {
            log.err(
                @src(),
                "Vertion of entry: {t} 0x{x:0>16} is invalid: {d} != {d}",
                .{ self.tag, self.hash, v.version, @as(u32, 6) },
            );
            return error.InvalidVerson;
        }
        if (v.hash != self.hash) {
            log.err(
                @src(),
                "Hash for entry: {t} 0x{x:0>16} is not equal to json value: 0x{x:0>16} != 0x{x:0>16}",
                .{ self.tag, self.hash, v.hash, self.hash },
            );
            return error.InvalidHash;
        }
    }

    pub const ParseResult = enum {
        parsed,
        deferred,
        invalid,
    };
    pub fn parse(
        self: *Entry,
        comptime PARSE: type,
        dependency_alloc: Allocator,
        entry_alloc: Allocator,
        tmp_alloc: Allocator,
        db: *Database,
        validation: *const Validation,
    ) ParseResult {
        const prof_point = MEASUREMENTS.start_named("parse");
        defer MEASUREMENTS.end(prof_point);

        if (self.status.cmpxchgStrong(.not_parsed, .parsing, .acq_rel, .acquire)) |old| {
            log.assert(
                @src(),
                old == .parsing or old == .parsed or old == .invalid,
                "Encountered strange entry state: {t}",
                .{old},
            );
            return switch (old) {
                .parsed => .parsed,
                .parsing => .deferred,
                .invalid => .invalid,
                else => unreachable,
            };
        }

        // Shader modules consume a lot of memory. Instead of storing them
        // in database memory, do the parsing and creation on one go since
        // we know they cannot have dependencies.
        if (self.tag != .shader_module) {
            const payload = self.get_payload(tmp_alloc, tmp_alloc, db) catch |err| {
                log.debug(
                    @src(),
                    "Cannot read the payload for {t} 0x{x:0>16}: {t}",
                    .{ self.tag, self.hash, err },
                );
                self.status.store(.invalid, .release);
                return .invalid;
            };
            self.parse_inner(
                PARSE,
                dependency_alloc,
                entry_alloc,
                tmp_alloc,
                db,
                validation,
                payload,
            ) catch |err| {
                log.debug(
                    @src(),
                    "Cannot parse object: {t} 0x{x:0>16}: {t}",
                    .{ self.tag, self.hash, err },
                );
                if (err == parsing.ScannerError.InvalidJson)
                    log.debug(@src(), "payload: {s}", .{payload});

                self.status.store(.invalid, .release);
                return .invalid;
            };
        }

        self.status.store(.parsed, .release);
        return .parsed;
    }

    pub fn process_result_with_dependencies(
        self: *Entry,
        alloc: Allocator,
        db: *Database,
        result: *const parsing.ResultWithDependencies,
    ) !void {
        const prof_point = MEASUREMENTS.start(@src());
        defer MEASUREMENTS.end(prof_point);

        try self.check_version_and_hash(result);
        self.create_info = result.create_info;
        const dependencies = try alloc.alloc(Dependency, result.dependencies.len);
        for (result.dependencies, 0..) |dep, i| {
            const dep_entry = db.entries.getPtr(dep.tag).getPtr(dep.hash).?;
            dependencies[i] = .{
                .entry = dep_entry,
                .ptr_to_handle = dep.ptr_to_handle,
            };
            _ = dep_entry.dependent_by.fetchAdd(1, .release);
        }
        self.dependencies = dependencies;
    }

    pub fn parse_inner(
        self: *Entry,
        comptime PARSE: type,
        dependency_alloc: Allocator,
        entry_alloc: Allocator,
        tmp_alloc: Allocator,
        db: *Database,
        validation: *const Validation,
        payload: []const u8,
    ) !void {
        const prof_point = MEASUREMENTS.start_named("parse_inner");
        defer MEASUREMENTS.end(prof_point);

        switch (self.tag) {
            .sampler => {
                const result = try PARSE.parse_sampler(entry_alloc, tmp_alloc, db, payload);
                try self.check_version_and_hash(result);
                self.create_info = result.create_info;
                if (!vv.validate_VkSamplerCreateInfo(
                    validation.extensions,
                    @ptrCast(result.create_info),
                    true,
                ))
                    return error.CheckFailedVkSamplerCreateInfo;
            },
            .descriptor_set_layout => {
                const result = try PARSE.parse_descriptor_set_layout(
                    entry_alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.process_result_with_dependencies(dependency_alloc, db, &result);
                if (!vv.validate_VkDescriptorSetLayoutCreateInfo(
                    validation.extensions,
                    @ptrCast(
                        result.create_info,
                    ),
                    true,
                ))
                    return error.CheckFailedVkDescriptorSetLayoutCreateInfo;
            },
            .pipeline_layout => {
                const result =
                    try PARSE.parse_pipeline_layout(entry_alloc, tmp_alloc, db, payload);
                try self.process_result_with_dependencies(dependency_alloc, db, &result);
                if (!vv.validate_VkPipelineLayoutCreateInfo(
                    validation.extensions,
                    @ptrCast(
                        result.create_info,
                    ),
                    true,
                ))
                    return error.CheckFailedVkPipelineLayoutCreateInfo;
            },
            .render_pass => {
                const result = try PARSE.parse_render_pass(
                    entry_alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.check_version_and_hash(result);
                self.create_info = result.create_info;
                if (!vv.validate_VkRenderPassCreateInfo(
                    validation.extensions,
                    @ptrCast(
                        result.create_info,
                    ),
                    true,
                ))
                    return error.CheckFailedVkRenderPassCreateInfo;
            },
            .graphics_pipeline => {
                const result = try PARSE.parse_graphics_pipeline(
                    entry_alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.process_result_with_dependencies(dependency_alloc, db, &result);
                if (!vv.validate_VkGraphicsPipelineCreateInfo(
                    validation.extensions,
                    @ptrCast(
                        result.create_info,
                    ),
                    true,
                ))
                    return error.CheckFailedVkGraphicsPipelineCreateInfo;
            },
            .compute_pipeline => {
                const result = try PARSE.parse_compute_pipeline(
                    entry_alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.process_result_with_dependencies(dependency_alloc, db, &result);
                if (!vv.validate_VkComputePipelineCreateInfo(
                    validation.extensions,
                    @ptrCast(
                        result.create_info,
                    ),
                    true,
                ))
                    return error.CheckFailedVkComputePipelineCreateInfo;
            },
            .raytracing_pipeline => {
                const result = try PARSE.parse_raytracing_pipeline(
                    entry_alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.process_result_with_dependencies(dependency_alloc, db, &result);
                if (!vv.validate_VkRayTracingPipelineCreateInfoKHR(
                    validation.extensions,
                    @ptrCast(
                        result.create_info,
                    ),
                    true,
                ))
                    return error.CheckFailedVkRayTracingPipelineCreateInfoKHR;
            },
            else => {},
        }
    }

    pub const CreateResult = enum {
        dependencies,
        creating,
        created,
        invalid,
    };
    pub fn create(
        self: *Entry,
        comptime PARSE: type,
        comptime CREATE: type,
        tmp_alloc: Allocator,
        db: *Database,
        validation: *const Validation,
        vk_device: vk.VkDevice,
    ) CreateResult {
        const prof_point = MEASUREMENTS.start_named("create");
        defer MEASUREMENTS.end(prof_point);

        for (self.dependencies) |dep| {
            const d_status = dep.entry.status.load(.acquire);
            if (d_status == .invalid) {
                self.status.store(.invalid, .release);
                return .invalid;
            }
            if (d_status != .created) return .dependencies;
        }

        if (self.status.cmpxchgStrong(.parsed, .creating, .acq_rel, .acquire)) |old| {
            log.assert(
                @src(),
                old == .creating or old == .created or old == .invalid,
                "Encountered strange entry state: {t}",
                .{old},
            );
            return switch (old) {
                .created => .created,
                .creating => .creating,
                .invalid => .invalid,
                else => unreachable,
            };
        }

        self.create_inner(PARSE, CREATE, tmp_alloc, db, validation, vk_device) catch |err| {
            log.debug(
                @src(),
                "Cannot create object: {t} 0x{x:0>16}: {t}",
                .{ self.tag, self.hash, err },
            );
            self.status.store(.invalid, .release);
            return .invalid;
        };
        self.status.store(.created, .release);
        return .created;
    }

    pub fn create_inner(
        self: *Entry,
        comptime PARSE: type,
        comptime CREATE: type,
        tmp_alloc: Allocator,
        db: *Database,
        validation: *const Validation,
        vk_device: vk.VkDevice,
    ) !void {
        const prof_point = MEASUREMENTS.start_named("create_inner");
        defer MEASUREMENTS.end(prof_point);

        for (self.dependencies, 0..) |dep, i| {
            log.assert(
                @src(),
                dep.entry.handle != null,
                "Trying to patch create_info with empty handle of dependency {d} for {t} 0x{x:0>16}",
                .{ i, self.tag, self.hash },
            );
            dep.ptr_to_handle.?.* = dep.entry.handle;
        }
        switch (self.tag) {
            .sampler => self.handle = try CREATE.create_vk_sampler(
                vk_device,
                @ptrCast(self.create_info),
            ),
            .descriptor_set_layout => self.handle = try CREATE.create_descriptor_set_layout(
                vk_device,
                @ptrCast(self.create_info),
            ),
            .pipeline_layout => self.handle = try CREATE.create_pipeline_layout(
                vk_device,
                @ptrCast(self.create_info),
            ),
            .shader_module => {
                const payload = try self.get_payload(tmp_alloc, tmp_alloc, db);
                const result = try PARSE.parse_shader_module(
                    tmp_alloc,
                    tmp_alloc,
                    db,
                    payload,
                );
                try self.check_version_and_hash(result);
                if (!vv.validate_shader_code(validation, @ptrCast(result.create_info)))
                    return error.InvalidShaderCode;

                self.handle = try CREATE.create_shader_module(
                    vk_device,
                    @ptrCast(result.create_info),
                );
            },
            .render_pass => self.handle = try CREATE.create_render_pass(
                vk_device,
                @ptrCast(self.create_info),
            ),
            .graphics_pipeline => self.handle = try CREATE.create_graphics_pipeline(
                vk_device,
                @ptrCast(self.create_info),
            ),
            .compute_pipeline => self.handle = try CREATE.create_compute_pipeline(
                vk_device,
                @ptrCast(self.create_info),
            ),
            .raytracing_pipeline => self.handle = try CREATE.create_raytracing_pipeline(
                vk_device,
                @ptrCast(self.create_info),
            ),
            else => {},
        }
    }

    pub fn decrement_dependencies(self: *Entry) void {
        const prof_point = MEASUREMENTS.start(@src());
        defer MEASUREMENTS.end(prof_point);

        if (self.dependencies_destroyed.cmpxchgStrong(false, true, .acq_rel, .acquire) == null) {
            for (self.dependencies) |dep| _ = dep.entry.dependent_by.fetchSub(1, .acq_rel);
        }
    }

    pub fn destroy_dependencies(
        self: *Entry,
        comptime DESTROY: type,
        vk_device: vk.VkDevice,
    ) void {
        const prof_point = MEASUREMENTS.start_named("destroy_dependencies");
        defer MEASUREMENTS.end(prof_point);

        if (self.dependencies_destroyed.cmpxchgStrong(false, true, .acq_rel, .acquire) == null) {
            for (self.dependencies) |dep| {
                _ = dep.entry.dependent_by.fetchSub(1, .acq_rel);
                dep.entry.destroy(DESTROY, vk_device);
            }
        }
    }

    pub fn destroy(self: *Entry, comptime DESTROY: type, vk_device: vk.VkDevice) void {
        const prof_point = MEASUREMENTS.start_named("destroy");
        defer MEASUREMENTS.end(prof_point);

        const status = self.status.load(.acquire);
        if (status != .created) return;

        const dependent_by = self.dependent_by.load(.acquire);
        if (dependent_by != 0) return;

        if (self.dependencies_destroyed.cmpxchgStrong(false, true, .acq_rel, .acquire) == null) {
            switch (self.tag) {
                .application_info => {},
                .sampler => DESTROY.destroy_vk_sampler(vk_device, @ptrCast(self.handle)),
                .descriptor_set_layout => DESTROY.destroy_descriptor_set_layout(
                    vk_device,
                    @ptrCast(self.handle),
                ),
                .pipeline_layout => DESTROY.destroy_pipeline_layout(
                    vk_device,
                    @ptrCast(self.handle),
                ),
                .shader_module,
                => DESTROY.destroy_shader_module(vk_device, @ptrCast(self.handle)),
                .render_pass,
                => DESTROY.destroy_render_pass(vk_device, @ptrCast(self.handle)),
                .graphics_pipeline,
                .compute_pipeline,
                .raytracing_pipeline,
                => DESTROY.destroy_pipeline(vk_device, @ptrCast(self.handle)),
                .application_blob_link => {},
            }
            for (self.dependencies) |dep| {
                _ = dep.entry.dependent_by.fetchSub(1, .acq_rel);
                dep.entry.destroy(DESTROY, vk_device);
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

pub fn init(tmp_alloc: Allocator, progress: *std.Progress.Node, path: []const u8) !Database {
    const prof_point = MEASUREMENTS.start(@src());
    defer MEASUREMENTS.end(prof_point);

    log.info(@src(), "Openning database as path: {s}", .{path});
    // const file = try std.fs.openFileAbsolute(path, .{});
    const file = try std.fs.cwd().openFile(path, .{});
    const file_stat = try file.stat();
    const file_size = file_stat.size;
    var file_offset: u64 = 0;

    // Initial parsing here and goes through the file sequentialy
    _ = std.os.linux.fadvise(
        file.handle,
        0,
        @intCast(file_size),
        std.os.linux.POSIX_FADV.SEQUENTIAL,
    );

    var header: Header = undefined;
    log.assert(@src(), try file.pread(@ptrCast(&header), file_offset) == @sizeOf(Header), "", .{});
    file_offset += @sizeOf(Header);

    if (!std.mem.eql(u8, &header.magic, MAGIC)) return error.InvalidMagicValue;

    log.info(@src(), "Stored header version: {d}", .{header.version});

    // All database related allocations will be in this arena.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena_alloc = arena.allocator();

    var entries: EntriesType = .initFill(.empty);

    const progress_node = progress.start("reading database", 0);
    defer progress_node.end();
    while (file_offset < file_stat.size) {
        progress_node.completeOne();
        // If entry is incomplete, stop
        if (file_size - file_offset < @sizeOf(FileEntry)) break;

        var entry: FileEntry = undefined;
        log.assert(
            @src(),
            try file.pread(@ptrCast(&entry), file_offset) == @sizeOf(FileEntry),
            "",
            .{},
        );
        file_offset += @sizeOf(FileEntry);

        // If payload for the entry is incomplete, stop
        if (file_size - file_offset < entry.stored_size) break;

        const payload_file_offset: u64 = file_offset;
        file_offset += entry.stored_size;
        const entry_tag = entry.get_tag() catch {
            log.debug(@src(), "Skipping corrupted FileEntry", .{});
            continue;
        };
        // There is no used for these blobs, so skip them.
        if (entry_tag == .application_blob_link) continue;

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
        log.info(@src(), "Found {s:<21} {d:>8}", .{ @tagName(e.key), map.count() });
        e.value.* = try map.clone(arena_alloc);
    }

    // Later file is accessed by multiple threads at random offsets
    _ = std.os.linux.fadvise(
        file.handle,
        0,
        @intCast(file_stat.size),
        std.os.linux.POSIX_FADV.RANDOM,
    );

    return .{
        .file = file,
        .entries = final_entries,
        .arena = arena,
    };
}
