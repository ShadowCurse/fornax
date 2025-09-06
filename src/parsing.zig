// Copyright (c) 2025 Egor Lazarchuk
//
// Based in part on Fossilize project which is:
// Copyright (c) 2025 Hans-Kristian Arntzen
//
// SPDX-License-Identifier: MIT

const std = @import("std");
const vk = @import("volk.zig");
const log = @import("log.zig");
const root = @import("main.zig");
const vk_print = @import("vulkan_print.zig");

const Allocator = std.mem.Allocator;
const Database = root.Database;

pub const Context = struct {
    alloc: Allocator,
    tmp_alloc: Allocator,
    scanner: *std.json.Scanner,
    db: *const Database,
};

pub const ParsedApplicationInfo = struct {
    version: u32,
    application_info: *const vk.VkApplicationInfo,
    device_features2: *const vk.VkPhysicalDeviceFeatures2,
};
pub fn parse_application_info(
    alloc: Allocator,
    tmp_alloc: Allocator,
    database: *const Database,
    json_str: []const u8,
) !ParsedApplicationInfo {
    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_application_info = try alloc.create(vk.VkApplicationInfo);
    const vk_physical_device_features2 = try alloc.create(vk.VkPhysicalDeviceFeatures2);

    var result: ParsedApplicationInfo = .{
        .version = 0,
        .application_info = vk_application_info,
        .device_features2 = vk_physical_device_features2,
    };

    const context: Context = .{
        .alloc = alloc,
        .tmp_alloc = tmp_alloc,
        .scanner = &scanner,
        .db = database,
    };

    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(context.scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "applicationInfo")) {
            try parse_vk_application_info(&context, vk_application_info);
        } else if (std.mem.eql(u8, s, "physicalDeviceFeatures")) {
            try parse_vk_physical_device_features2(&context, vk_physical_device_features2);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
    return result;
}

test "parse_application_info" {
    const json =
        \\{
        \\  "version": 69,
        \\  "applicationInfo": {},
        \\  "physicalDeviceFeatures": {}
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };

    const result = try parse_application_info(alloc, alloc, &db, json);
    try std.testing.expectEqual(result.version, 69);
}

pub const ParsedSampler = struct {
    version: u32,
    hash: u64,
    create_info: *const vk.VkSamplerCreateInfo,
};
pub fn parse_sampler(
    alloc: Allocator,
    tmp_alloc: Allocator,
    database: *const Database,
    json_str: []const u8,
) !ParsedSampler {
    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_sampler_create_info = try alloc.create(vk.VkSamplerCreateInfo);
    vk_sampler_create_info.* = .{ .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO };

    var result: ParsedSampler = .{
        .version = 0,
        .hash = 0,
        .create_info = vk_sampler_create_info,
    };

    const context: Context = .{
        .alloc = alloc,
        .tmp_alloc = tmp_alloc,
        .scanner = &scanner,
        .db = database,
    };

    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(context.scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "samplers")) {
            try scanner_object_begin(context.scanner);
            const ss = try scanner_next_string(context.scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            try parse_simple_type(&context, vk_sampler_create_info);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
    return result;
}

test "parse_sampler" {
    const json =
        \\ {
        \\   "version": 69,
        \\   "samplers": {
        \\     "1111111111111111": {}
        \\   }
        \\ }
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };

    const result = try parse_sampler(alloc, alloc, &db, json);
    try std.testing.expectEqual(result.version, 69);
    try std.testing.expectEqual(result.hash, 0x1111111111111111);
}

pub const ParsedDescriptorSetLayout = struct {
    version: u32,
    hash: u64,
    create_info: *const vk.VkDescriptorSetLayoutCreateInfo,
};
pub fn parse_descriptor_set_layout(
    alloc: Allocator,
    tmp_alloc: Allocator,
    database: *const Database,
    json_str: []const u8,
) !ParsedDescriptorSetLayout {
    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_descriptor_set_layout_create_info =
        try alloc.create(vk.VkDescriptorSetLayoutCreateInfo);

    var result: ParsedDescriptorSetLayout = .{
        .version = 0,
        .hash = 0,
        .create_info = vk_descriptor_set_layout_create_info,
    };

    const context: Context = .{
        .alloc = alloc,
        .tmp_alloc = tmp_alloc,
        .scanner = &scanner,
        .db = database,
    };

    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(context.scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "setLayouts")) {
            try scanner_object_begin(context.scanner);
            const ss = try scanner_next_string(context.scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            try parse_vk_descriptor_set_layout_create_info(
                &context,
                vk_descriptor_set_layout_create_info,
            );
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
    return result;
}

test "parse_descriptor_set_layout" {
    const json =
        \\{
        \\  "version": 69,
        \\  "setLayouts": {
        \\    "1111111111111111": {}
        \\  }
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };

    const result = try parse_descriptor_set_layout(alloc, alloc, &db, json);
    try std.testing.expectEqual(result.version, 69);
    try std.testing.expectEqual(result.hash, 0x1111111111111111);
}

pub const ParsedPipelineLayout = struct {
    version: u32,
    hash: u64,
    create_info: *const vk.VkPipelineLayoutCreateInfo,
};
pub fn parse_pipeline_layout(
    alloc: Allocator,
    tmp_alloc: Allocator,
    database: *const Database,
    json_str: []const u8,
) !ParsedPipelineLayout {
    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_pipeline_layout_create_info = try alloc.create(vk.VkPipelineLayoutCreateInfo);

    var result: ParsedPipelineLayout = .{
        .version = 0,
        .hash = 0,
        .create_info = vk_pipeline_layout_create_info,
    };

    const context: Context = .{
        .alloc = alloc,
        .tmp_alloc = tmp_alloc,
        .scanner = &scanner,
        .db = database,
    };

    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(context.scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "pipelineLayouts")) {
            try scanner_object_begin(context.scanner);
            const ss = try scanner_next_string(context.scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            try parse_vk_pipeline_layout_create_info(
                &context,
                vk_pipeline_layout_create_info,
            );
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
    return result;
}

test "parse_pipeline_layout" {
    const json =
        \\{
        \\  "version": 69,
        \\  "pipelineLayouts": {
        \\    "1111111111111111": {}
        \\  }
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };

    const result = try parse_pipeline_layout(alloc, alloc, &db, json);
    try std.testing.expectEqual(result.version, 69);
    try std.testing.expectEqual(result.hash, 0x1111111111111111);
}

pub const ParsedShaderModule = struct {
    version: u32,
    hash: u64,
    create_info: *const vk.VkShaderModuleCreateInfo,
};
pub fn parse_shader_module(
    alloc: Allocator,
    tmp_alloc: Allocator,
    database: *const Database,
    payload: []const u8,
) !ParsedShaderModule {
    // For shader modules the payload is divided in to 2 parts: json and code.
    // json part is 0 teriminated.
    const json_str = std.mem.span(@as([*c]const u8, @ptrCast(payload.ptr)));
    if (json_str.len == payload.len)
        return error.NoShaderCodePayload;
    // The 0 byte is not included into the `json_str.len`, so add it manually.
    const shader_code_payload = payload[json_str.len + 1 ..];

    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_shader_module_create_info = try alloc.create(vk.VkShaderModuleCreateInfo);

    var result: ParsedShaderModule = .{
        .version = 0,
        .hash = 0,
        .create_info = vk_shader_module_create_info,
    };

    const context: Context = .{
        .alloc = alloc,
        .tmp_alloc = tmp_alloc,
        .scanner = &scanner,
        .db = database,
    };

    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(context.scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "shaderModules")) {
            try scanner_object_begin(context.scanner);
            const ss = try scanner_next_string(context.scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            try parse_vk_shader_module_create_info(
                &context,
                vk_shader_module_create_info,
                shader_code_payload,
            );
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
    return result;
}

test "parse_shader_module" {
    const json =
        \\{
        \\  "version": 69,
        \\  "shaderModules": {
        \\    "1111111111111111": {}
        \\  }
        \\}
    ++ "\x00\x81\x82\x83\x00";
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };

    const result = try parse_shader_module(alloc, alloc, &db, json);
    try std.testing.expectEqual(result.version, 69);
    try std.testing.expectEqual(result.hash, 0x1111111111111111);
}

pub const ParsedRenderPass = struct {
    version: u32,
    hash: u64,
    create_info: *const vk.VkRenderPassCreateInfo,
};
pub fn parse_render_pass(
    alloc: Allocator,
    tmp_alloc: Allocator,
    database: *const Database,
    json_str: []const u8,
) !ParsedRenderPass {
    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_render_pass_create_info = try alloc.create(vk.VkRenderPassCreateInfo);

    var result: ParsedRenderPass = .{
        .version = 0,
        .hash = 0,
        .create_info = vk_render_pass_create_info,
    };

    const context: Context = .{
        .alloc = alloc,
        .tmp_alloc = tmp_alloc,
        .scanner = &scanner,
        .db = database,
    };

    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(context.scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "renderPasses")) {
            try scanner_object_begin(context.scanner);
            const ss = try scanner_next_string(context.scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            try parse_vk_render_pass_create_info(&context, vk_render_pass_create_info);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
    return result;
}

test "parse_render_pass" {
    const json =
        \\{
        \\  "version": 69,
        \\  "renderPasses": {
        \\    "1111111111111111": {}
        \\  }
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };

    const result = try parse_render_pass(alloc, alloc, &db, json);
    try std.testing.expectEqual(result.version, 69);
    try std.testing.expectEqual(result.hash, 0x1111111111111111);
}

pub const ParsedComputePipeline = struct {
    version: u32,
    hash: u64,
    create_info: *const vk.VkComputePipelineCreateInfo,
};
pub fn parse_compute_pipeline(
    alloc: Allocator,
    tmp_alloc: Allocator,
    database: *const Database,
    json_str: []const u8,
) !ParsedComputePipeline {
    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const create_info = try alloc.create(vk.VkComputePipelineCreateInfo);

    var result: ParsedComputePipeline = .{
        .version = 0,
        .hash = 0,
        .create_info = create_info,
    };

    const context: Context = .{
        .alloc = alloc,
        .tmp_alloc = tmp_alloc,
        .scanner = &scanner,
        .db = database,
    };

    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(context.scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "computePipelines")) {
            try scanner_object_begin(context.scanner);
            const ss = try scanner_next_string(context.scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            try parse_vk_compute_pipeline_create_info(
                &context,
                create_info,
            );
        }
    }
    return result;
}

test "parse_compute_pipeline" {
    const json =
        \\{
        \\  "version": 69,
        \\  "computePipelines": {
        \\    "1111111111111111": {}
        \\  }
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var db: Database = .{
        .file_mem = &.{},
        .entries = .initFill(.empty),
        .arena = arena,
    };
    try db.entries.getPtr(.PIPELINE_LAYOUT).put(alloc, 0x2222222222222222, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });

    const result = try parse_compute_pipeline(alloc, alloc, &db, json);
    try std.testing.expectEqual(result.version, 69);
    try std.testing.expectEqual(result.hash, 0x1111111111111111);
}

pub const ParsedRaytracingPipeline = struct {
    version: u32,
    hash: u64,
    create_info: *const vk.VkRayTracingPipelineCreateInfoKHR,
};
pub fn parse_raytracing_pipeline(
    alloc: Allocator,
    tmp_alloc: Allocator,
    database: *const Database,
    json_str: []const u8,
) !ParsedRaytracingPipeline {
    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const create_info = try alloc.create(vk.VkRayTracingPipelineCreateInfoKHR);

    var result: ParsedRaytracingPipeline = .{
        .version = 0,
        .hash = 0,
        .create_info = create_info,
    };

    const context: Context = .{
        .alloc = alloc,
        .tmp_alloc = tmp_alloc,
        .scanner = &scanner,
        .db = database,
    };

    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(context.scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "raytracingPipelines")) {
            try scanner_object_begin(context.scanner);
            const ss = try scanner_next_string(context.scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            try parse_vk_raytracing_pipeline_create_info(&context, create_info);
        }
    }
    return result;
}

test "parse_raytracing_pipeline" {
    const json =
        \\{
        \\  "version": 69,
        \\  "raytracingPipelines": {
        \\    "1111111111111111": {}
        \\  }
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var db: Database = .{
        .file_mem = &.{},
        .entries = .initFill(.empty),
        .arena = arena,
    };
    try db.entries.getPtr(.PIPELINE_LAYOUT).put(alloc, 0x2222222222222222, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });

    const result = try parse_raytracing_pipeline(alloc, alloc, &db, json);
    try std.testing.expectEqual(result.version, 69);
    try std.testing.expectEqual(result.hash, 0x1111111111111111);
}

pub const ParsedGraphicsPipeline = struct {
    version: u32,
    hash: u64,
    create_info: *const vk.VkGraphicsPipelineCreateInfo,
};
pub fn parse_graphics_pipeline(
    alloc: Allocator,
    tmp_alloc: Allocator,
    database: *const Database,
    json_str: []const u8,
) !ParsedGraphicsPipeline {
    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_graphics_pipeline_create_info = try alloc.create(vk.VkGraphicsPipelineCreateInfo);

    var result: ParsedGraphicsPipeline = .{
        .version = 0,
        .hash = 0,
        .create_info = vk_graphics_pipeline_create_info,
    };

    const context: Context = .{
        .alloc = alloc,
        .tmp_alloc = tmp_alloc,
        .scanner = &scanner,
        .db = database,
    };

    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(context.scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "graphicsPipelines")) {
            try scanner_object_begin(context.scanner);
            const ss = try scanner_next_string(context.scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            try parse_vk_graphics_pipeline_create_info(
                &context,
                vk_graphics_pipeline_create_info,
            );
        }
    }
    return result;
}

test "parse_graphics_pipeline" {
    const json =
        \\{
        \\  "version": 69,
        \\  "graphicsPipelines": {
        \\    "1111111111111111": {}
        \\  }
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{
        .file_mem = &.{},
        .entries = .initFill(.empty),
        .arena = arena,
    };

    const result = try parse_graphics_pipeline(alloc, alloc, &db, json);
    try std.testing.expectEqual(result.version, 69);
    try std.testing.expectEqual(result.hash, 0x1111111111111111);
}

fn print_unexpected_token(token: std.json.Token) void {
    switch (token) {
        .object_begin => log.err(
            @src(),
            "Got unexpected token type {s}",
            .{@tagName(std.meta.activeTag(token))},
        ),
        .object_end => log.err(
            @src(),
            "Got unexpected token type {s}",
            .{@tagName(std.meta.activeTag(token))},
        ),
        .array_begin => log.err(
            @src(),
            "Got unexpected token type {s}",
            .{@tagName(std.meta.activeTag(token))},
        ),
        .array_end => log.err(
            @src(),
            "Got unexpected token type {s}",
            .{@tagName(std.meta.activeTag(token))},
        ),

        .true => log.err(
            @src(),
            "Got unexpected token type {s}",
            .{@tagName(std.meta.activeTag(token))},
        ),
        .false => log.err(
            @src(),
            "Got unexpected token type {s}",
            .{@tagName(std.meta.activeTag(token))},
        ),
        .null => log.err(
            @src(),
            "Got unexpected token type {s}",
            .{@tagName(std.meta.activeTag(token))},
        ),

        .number => |v| log.err(
            @src(),
            "Got unexpected token type {s} with value: {s}",
            .{ @tagName(std.meta.activeTag(token)), v },
        ),
        .partial_number => |v| log.err(
            @src(),
            "Got unexpected token type {s} with value: {s}",
            .{ @tagName(std.meta.activeTag(token)), v },
        ),
        .allocated_number => |v| log.err(
            @src(),
            "Got unexpected token type {s} with value: {s}",
            .{ @tagName(std.meta.activeTag(token)), v },
        ),

        .string => |v| log.err(
            @src(),
            "Got unexpected token type {s} with value: {s}",
            .{ @tagName(std.meta.activeTag(token)), v },
        ),
        .partial_string => |v| log.err(
            @src(),
            "Got unexpected token type {s} with value: {s}",
            .{ @tagName(std.meta.activeTag(token)), v },
        ),
        .partial_string_escaped_1 => |v| log.err(
            @src(),
            "Got unexpected token type {s} with value: {s}",
            .{ @tagName(std.meta.activeTag(token)), v },
        ),
        .partial_string_escaped_2 => |v| log.err(
            @src(),
            "Got unexpected token type {s} with value: {s}",
            .{ @tagName(std.meta.activeTag(token)), v },
        ),
        .partial_string_escaped_3 => |v| log.err(
            @src(),
            "Got unexpected token type {s} with value: {s}",
            .{ @tagName(std.meta.activeTag(token)), v },
        ),
        .partial_string_escaped_4 => |v| log.err(
            @src(),
            "Got unexpected token type {s} with value: {s}",
            .{ @tagName(std.meta.activeTag(token)), v },
        ),
        .allocated_string => |v| log.err(
            @src(),
            "Got unexpected token type {s} with value: {s}",
            .{ @tagName(std.meta.activeTag(token)), v },
        ),

        .end_of_document => log.err(
            @src(),
            "Got unexpected token type {s}",
            .{@tagName(std.meta.activeTag(token))},
        ),
    }
}

fn scanner_next_number(scanner: *std.json.Scanner) ![]const u8 {
    switch (try scanner.next()) {
        .number => |v| return v,
        else => |t| {
            print_unexpected_token(t);
            return error.InvalidJson;
        },
    }
}

fn scanner_next_string(scanner: *std.json.Scanner) ![]const u8 {
    switch (try scanner.next()) {
        .string => |s| return s,
        else => |t| {
            print_unexpected_token(t);
            return error.InvalidJson;
        },
    }
}

fn scanner_next_number_or_string(scanner: *std.json.Scanner) ![]const u8 {
    switch (try scanner.next()) {
        .string => |s| return s,
        .number => |v| return v,
        else => |t| {
            print_unexpected_token(t);
            return error.InvalidJson;
        },
    }
}

fn scanner_object_next_field(scanner: *std.json.Scanner) !?[]const u8 {
    loop: switch (try scanner.next()) {
        .string => |s| return s,
        .object_begin => continue :loop try scanner.next(),
        .end_of_document, .object_end => return null,
        else => |t| {
            print_unexpected_token(t);
            return error.InvalidJson;
        },
    }
}

fn scanner_array_next_object(scanner: *std.json.Scanner) !bool {
    loop: switch (try scanner.next()) {
        .array_begin => continue :loop try scanner.next(),
        .array_end => return false,
        .object_begin => return true,
        else => |t| {
            print_unexpected_token(t);
            return error.InvalidJson;
        },
    }
}

fn scanner_array_next_number(scanner: *std.json.Scanner) !?[]const u8 {
    loop: switch (try scanner.next()) {
        .array_begin => continue :loop try scanner.next(),
        .array_end => return null,
        .number => |v| return v,
        else => |t| {
            print_unexpected_token(t);
            return error.InvalidJson;
        },
    }
}

fn scanner_array_next_string(scanner: *std.json.Scanner) !?[]const u8 {
    loop: switch (try scanner.next()) {
        .array_begin => continue :loop try scanner.next(),
        .array_end => return null,
        .string => |s| return s,
        else => |t| {
            print_unexpected_token(t);
            return error.InvalidJson;
        },
    }
}

fn scanner_object_begin(scanner: *std.json.Scanner) !void {
    switch (try scanner.next()) {
        .object_begin => return,
        else => |t| {
            print_unexpected_token(t);
            return error.InvalidJson;
        },
    }
}

fn scanner_array_begin(scanner: *std.json.Scanner) !void {
    switch (try scanner.next()) {
        .array_begin => return,
        else => |t| {
            print_unexpected_token(t);
            return error.InvalidJson;
        },
    }
}

pub fn parse_simple_type(context: *const Context, output: anytype) anyerror!void {
    const output_type = @typeInfo(@TypeOf(output)).pointer.child;
    const output_fields = @typeInfo(output_type).@"struct".fields;
    var field_is_parsed: [output_fields.len]bool = .{false} ** output_fields.len;
    while (try scanner_object_next_field(context.scanner)) |s| {
        var consumed: bool = false;
        inline for (output_fields, 0..) |field, i| {
            if (!field_is_parsed[i] and std.mem.eql(u8, s, field.name)) {
                field_is_parsed[i] = true;
                switch (field.type) {
                    i16, i32, u32, u64, usize, c_uint => {
                        const v = try scanner_next_number(context.scanner);
                        @field(output, field.name) = try std.fmt.parseInt(field.type, v, 10);
                        consumed = true;
                    },
                    f32 => {
                        const v = try scanner_next_number(context.scanner);
                        @field(output, field.name) = try std.fmt.parseFloat(field.type, v);
                        consumed = true;
                    },
                    ?*anyopaque,
                    ?*const anyopaque,
                    => {
                        if (std.mem.eql(u8, "pNext", field.name)) {
                            @field(output, field.name) = try parse_pnext_chain(context);
                            consumed = true;
                        }
                    },
                    else => {},
                }
            }
        }
        if (!consumed) {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(
                @src(),
                "{s}: Skipping unknown field {s} with value {s}",
                .{ @typeName(output_type), s, v },
            );
        }
    }
}

fn parse_number_array(comptime T: type, context: *const Context) ![]T {
    try scanner_array_begin(context.scanner);
    var tmp: std.ArrayListUnmanaged(T) = .empty;
    while (try scanner_array_next_number(context.scanner)) |v| {
        const number = try std.fmt.parseInt(T, v, 10);
        try tmp.append(context.tmp_alloc, number);
    }
    return try context.alloc.dupe(T, tmp.items);
}

fn parse_handle_array(comptime T: type, tag: Database.Entry.Tag, context: *const Context) ![]T {
    try scanner_array_begin(context.scanner);
    var tmp: std.ArrayListUnmanaged(T) = .empty;
    while (try scanner_array_next_string(context.scanner)) |hash_str| {
        const hash = try std.fmt.parseInt(u64, hash_str, 16);
        // Must preserve the index in the array for non 0 hashes
        const handle: ?*anyopaque = if (hash == 0)
            null
        else
            try context.db.get_handle(tag, hash);
        try tmp.append(context.tmp_alloc, @ptrCast(handle));
    }
    return try context.alloc.dupe(T, tmp.items);
}

fn parse_object_array(
    comptime T: type,
    comptime PARSE_FN: fn (
        *const Context,
        *T,
    ) anyerror!void,
    context: *const Context,
) ![]T {
    try scanner_array_begin(context.scanner);
    var tmp: std.ArrayListUnmanaged(T) = .empty;
    while (try scanner_array_next_object(context.scanner)) {
        try tmp.append(context.tmp_alloc, .{});
        const item = &tmp.items[tmp.items.len - 1];
        try PARSE_FN(context, item);
    }
    return try context.alloc.dupe(T, tmp.items);
}

pub fn parse_vk_physical_device_mesh_shader_features_ext(
    context: *const Context,
    obj: *vk.VkPhysicalDeviceMeshShaderFeaturesEXT,
) !void {
    obj.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT };
    return parse_simple_type(context, obj);
}

pub fn parse_vk_physical_device_fragment_shading_rate_features_khr(
    context: *const Context,
    obj: *vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR,
) !void {
    obj.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR };
    return parse_simple_type(context, obj);
}

pub fn parse_vk_descriptor_set_layout_binding_flags_create_info_ext(
    context: *const Context,
    obj: *vk.VkDescriptorSetLayoutBindingFlagsCreateInfoEXT,
) !void {
    obj.* = .{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO_EXT,
    };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "bindingFlags")) {
            const flags = try parse_number_array(u32, context);
            obj.pBindingFlags = @ptrCast(flags.ptr);
            obj.bindingCount = @intCast(flags.len);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

pub fn parse_vk_pipeline_rendering_create_info_khr(
    context: *const Context,
    obj: *vk.VkPipelineRenderingCreateInfo,
) !void {
    obj.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "depthAttachmentFormat")) {
            const v = try scanner_next_number(context.scanner);
            obj.depthAttachmentFormat = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "stencilAttachmentFormat")) {
            const v = try scanner_next_number(context.scanner);
            obj.stencilAttachmentFormat = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "viewMask")) {
            const v = try scanner_next_number(context.scanner);
            obj.viewMask = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "colorAttachmentFormats")) {
            const formats = try parse_number_array(u32, context);
            obj.pColorAttachmentFormats = @ptrCast(formats.ptr);
            obj.colorAttachmentCount = @intCast(formats.len);
        } else if (std.mem.eql(u8, s, "depthAttachmentFormat")) {
            const v = try scanner_next_number(context.scanner);
            obj.depthAttachmentFormat = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "stencilAttachmentFormat")) {
            const v = try scanner_next_number(context.scanner);
            obj.stencilAttachmentFormat = try std.fmt.parseInt(u32, v, 10);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

pub fn parse_vk_physical_device_robustness_2_features_khr(
    context: *const Context,
    obj: *vk.VkPhysicalDeviceRobustness2FeaturesEXT,
) !void {
    obj.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_KHR };
    try parse_simple_type(context, obj);
}

pub fn parse_vk_physical_device_descriptor_buffer_features_ext(
    context: *const Context,
    obj: *vk.VkPhysicalDeviceDescriptorBufferFeaturesEXT,
) !void {
    obj.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT };
    try parse_simple_type(context, obj);
}

pub fn parse_vk_pipeline_rasterization_depth_clip_state_create_info_ext(
    context: *const Context,
    obj: *vk.VkPipelineRasterizationDepthClipStateCreateInfoEXT,
) !void {
    obj.* = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_DEPTH_CLIP_STATE_CREATE_INFO_EXT,
    };
    try parse_simple_type(context, obj);
}

pub fn parse_vk_pipeline_create_flags_2_create_info(
    context: *const Context,
    obj: *vk.VkPipelineCreateFlags2CreateInfo,
) !void {
    obj.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_CREATE_FLAGS_2_CREATE_INFO };
    try parse_simple_type(context, obj);
}

pub fn parse_vk_graphics_pipeline_library_create_info_ext(
    context: *const Context,
    obj: *vk.VkGraphicsPipelineLibraryCreateInfoEXT,
) !void {
    obj.* = .{ .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT };
    try parse_simple_type(context, obj);
}

pub fn parse_vk_pipeline_vertex_input_divisor_state_create_info(
    context: *const Context,
    obj: *vk.VkPipelineVertexInputDivisorStateCreateInfo,
) !void {
    obj.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_DIVISOR_STATE_CREATE_INFO };
    const Inner = struct {
        fn parse_vk_vertex_input_binding_divisor_description(
            c: *const Context,
            item: *vk.VkVertexInputBindingDivisorDescription,
        ) !void {
            try parse_simple_type(c, item);
        }
    };

    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "vertexBindingDivisorCount")) {
            const v = try scanner_next_number(context.scanner);
            obj.vertexBindingDivisorCount = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "vertexBindingDivisors")) {
            const divisors = try parse_object_array(
                vk.VkVertexInputBindingDivisorDescription,
                Inner.parse_vk_vertex_input_binding_divisor_description,
                context,
            );
            obj.pVertexBindingDivisors = @ptrCast(divisors.ptr);
            obj.vertexBindingDivisorCount = @intCast(divisors.len);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

pub fn parse_vk_pipeline_shader_stage_required_subgroup_size_create_info(
    context: *const Context,
    obj: *vk.VkPipelineShaderStageRequiredSubgroupSizeCreateInfo,
) !void {
    obj.* = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_REQUIRED_SUBGROUP_SIZE_CREATE_INFO,
    };
    try parse_simple_type(context, obj);
}

pub fn parse_pnext_chain(context: *const Context) !?*anyopaque {
    const Inner = struct {
        fn parse_next(
            c: *const Context,
            first_in_chain: *?*anyopaque,
            last_pnext_in_chain: *?**anyopaque,
        ) !void {
            const v = try scanner_next_number(c.scanner);
            const stype = try std.fmt.parseInt(u32, v, 10);
            switch (stype) {
                vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT => {
                    const obj = try c.alloc.create(vk.VkPhysicalDeviceMeshShaderFeaturesEXT);
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_physical_device_mesh_shader_features_ext(c, obj);
                },
                vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR => {
                    const obj =
                        try c.alloc.create(vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR);
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_physical_device_fragment_shading_rate_features_khr(c, obj);
                },
                vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO_EXT => {
                    const obj =
                        try c.alloc.create(vk.VkDescriptorSetLayoutBindingFlagsCreateInfoEXT);
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_descriptor_set_layout_binding_flags_create_info_ext(c, obj);
                },
                vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR => {
                    const obj = try c.alloc.create(vk.VkPipelineRenderingCreateInfo);
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_pipeline_rendering_create_info_khr(c, obj);
                },
                vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_KHR => {
                    const obj = try c.alloc.create(vk.VkPhysicalDeviceRobustness2FeaturesEXT);
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_physical_device_robustness_2_features_khr(c, obj);
                },
                vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT => {
                    const obj =
                        try c.alloc.create(vk.VkPhysicalDeviceDescriptorBufferFeaturesEXT);
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_physical_device_descriptor_buffer_features_ext(c, obj);
                },
                vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_DEPTH_CLIP_STATE_CREATE_INFO_EXT => {
                    const obj =
                        try c.alloc.create(vk.VkPipelineRasterizationDepthClipStateCreateInfoEXT);
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_pipeline_rasterization_depth_clip_state_create_info_ext(c, obj);
                },
                vk.VK_STRUCTURE_TYPE_PIPELINE_CREATE_FLAGS_2_CREATE_INFO => {
                    const obj = try c.alloc.create(vk.VkPipelineCreateFlags2CreateInfo);
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_pipeline_create_flags_2_create_info(c, obj);
                },
                vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT => {
                    const obj =
                        try c.alloc.create(vk.VkGraphicsPipelineLibraryCreateInfoEXT);
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_graphics_pipeline_library_create_info_ext(c, obj);
                },
                vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_DIVISOR_STATE_CREATE_INFO => {
                    const obj =
                        try c.alloc.create(vk.VkPipelineVertexInputDivisorStateCreateInfo);
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_pipeline_vertex_input_divisor_state_create_info(c, obj);
                },
                vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_REQUIRED_SUBGROUP_SIZE_CREATE_INFO => {
                    const obj = try c.alloc.create(
                        vk.VkPipelineShaderStageRequiredSubgroupSizeCreateInfo,
                    );
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_vk_pipeline_shader_stage_required_subgroup_size_create_info(c, obj);
                },
                else => {
                    log.err(@src(), "Unknown pnext chain type: {d}", .{stype});
                    return error.InvalidJson;
                },
            }
        }

        fn parse_pipeline_library(
            c: *const Context,
            first_in_chain: *?*anyopaque,
            last_pnext_in_chain: *?**anyopaque,
        ) !void {
            const obj = try c.alloc.create(vk.VkPipelineLibraryCreateInfoKHR);
            obj.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LIBRARY_CREATE_INFO_KHR };
            if (first_in_chain.* == null)
                first_in_chain.* = obj;
            if (last_pnext_in_chain.*) |lpic| {
                lpic.* = obj;
            }
            last_pnext_in_chain.* = @ptrCast(&obj.pNext);
            const libraries = try parse_handle_array(
                vk.VkPipeline,
                .GRAPHICS_PIPELINE,
                c,
            );
            obj.pLibraries = @ptrCast(libraries.ptr);
            obj.libraryCount = @intCast(libraries.len);

            while (try scanner_object_next_field(c.scanner)) |ss| {
                if (std.mem.eql(u8, ss, "sType")) {
                    const v = try scanner_next_number(c.scanner);
                    const stype = try std.fmt.parseInt(u32, v, 10);
                    if (stype != vk.VK_STRUCTURE_TYPE_PIPELINE_LIBRARY_CREATE_INFO_KHR)
                        return error.InvalidsTypeForLibraries;
                } else {
                    const v = try scanner_next_number_or_string(c.scanner);
                    log.warn(@src(), "Skipping unknown field {s}: {s}", .{ ss, v });
                }
            }
        }
    };

    var first_in_chain: ?*anyopaque = null;
    var last_pnext_in_chain: ?**anyopaque = null;
    while (try scanner_array_next_object(context.scanner)) {
        const s = try scanner_object_next_field(context.scanner) orelse return error.InvalidJson;
        if (std.mem.eql(u8, s, "sType")) {
            try Inner.parse_next(context, &first_in_chain, &last_pnext_in_chain);
        } else if (std.mem.eql(u8, s, "libraries")) {
            try Inner.parse_pipeline_library(context, &first_in_chain, &last_pnext_in_chain);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
    return first_in_chain;
}

fn parse_vk_application_info(
    context: *const Context,
    item: *vk.VkApplicationInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "applicationName")) {
            const name_str = try scanner_next_string(context.scanner);
            const name = try context.alloc.dupeZ(u8, name_str);
            item.pApplicationName = @ptrCast(name.ptr);
        } else if (std.mem.eql(u8, s, "engineName")) {
            const name_str = try scanner_next_string(context.scanner);
            const name = try context.alloc.dupeZ(u8, name_str);
            item.pEngineName = @ptrCast(name.ptr);
        } else if (std.mem.eql(u8, s, "applicationVersion")) {
            const v = try scanner_next_number(context.scanner);
            item.applicationVersion = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "engineVersion")) {
            const v = try scanner_next_number(context.scanner);
            item.engineVersion = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "apiVersion")) {
            const v = try scanner_next_number(context.scanner);
            item.apiVersion = try std.fmt.parseInt(u32, v, 10);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_application_info" {
    const json =
        \\{
        \\  "applicationName": "APP_NAME",
        \\  "engineName": "ENGINE_NAME",
        \\  "applicationVersion": 69,
        \\  "engineVersion": 69,
        \\  "apiVersion": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkApplicationInfo = undefined;
    try parse_vk_application_info(&context, &item);

    try std.testing.expectEqual(item.sType, vk.VK_STRUCTURE_TYPE_APPLICATION_INFO);
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqualSlices(u8, std.mem.span(item.pApplicationName), "APP_NAME");
    try std.testing.expectEqual(item.applicationVersion, 69);
    try std.testing.expectEqualSlices(u8, std.mem.span(item.pEngineName), "ENGINE_NAME");
    try std.testing.expectEqual(item.engineVersion, 69);
    try std.testing.expectEqual(item.apiVersion, 69);
}

fn parse_vk_physical_device_features2(
    context: *const Context,
    item: *vk.VkPhysicalDeviceFeatures2,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "robustBufferAccess")) {
            const v = try scanner_next_number(context.scanner);
            item.features.robustBufferAccess = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_physical_device_features2" {
    const json =
        \\{
        \\  "robustBufferAccess": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPhysicalDeviceFeatures2 = undefined;
    try parse_vk_physical_device_features2(&context, &item);

    try std.testing.expectEqual(item.sType, vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2);
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.features, vk.VkPhysicalDeviceFeatures{
        .robustBufferAccess = 69,
    });
}

fn parse_vk_sampler_create_info(
    context: *const Context,
    item: *vk.VkSamplerCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO };
    try parse_simple_type(context, item);
}

test "test_parse_vk_sampler_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "minFilter": 69,
        \\  "magFilter": 69,
        \\  "maxAnisotropy": 69,
        \\  "compareOp": 69,
        \\  "anisotropyEnable": 69,
        \\  "mipmapMode": 69,
        \\  "addressModeU": 69,
        \\  "addressModeV": 69,
        \\  "addressModeW": 69,
        \\  "borderColor": 69,
        \\  "unnormalizedCoordinates": 69,
        \\  "compareEnable": 69,
        \\  "mipLodBias": 69,
        \\  "minLod": 69,
        \\  "maxLod": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkSamplerCreateInfo = undefined;
    try parse_vk_sampler_create_info(&context, &item);

    try std.testing.expectEqual(item.sType, vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO);
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.magFilter, 69);
    try std.testing.expectEqual(item.minFilter, 69);
    try std.testing.expectEqual(item.mipmapMode, 69);
    try std.testing.expectEqual(item.addressModeU, 69);
    try std.testing.expectEqual(item.addressModeV, 69);
    try std.testing.expectEqual(item.addressModeW, 69);
    try std.testing.expectEqual(item.mipLodBias, 69);
    try std.testing.expectEqual(item.anisotropyEnable, 69);
    try std.testing.expectEqual(item.maxAnisotropy, 69);
    try std.testing.expectEqual(item.compareEnable, 69);
    try std.testing.expectEqual(item.compareOp, 69);
    try std.testing.expectEqual(item.minLod, 69);
    try std.testing.expectEqual(item.maxLod, 69);
    try std.testing.expectEqual(item.borderColor, 69);
    try std.testing.expectEqual(item.unnormalizedCoordinates, 69);
}

fn parse_vk_descriptor_set_layout_create_info(
    context: *const Context,
    item: *vk.VkDescriptorSetLayoutCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "bindings")) {
            const bindings = try parse_object_array(
                vk.VkDescriptorSetLayoutBinding,
                parse_vk_descriptor_set_layout_binding,
                context,
            );
            item.pBindings = @ptrCast(bindings.ptr);
            item.bindingCount = @intCast(bindings.len);
        } else if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_descriptor_set_layout_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "bindings": [{}]
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkDescriptorSetLayoutCreateInfo = undefined;
    try parse_vk_descriptor_set_layout_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.bindingCount, 1);
    try std.testing.expect(item.pBindings != null);
}

fn parse_vk_descriptor_set_layout_binding(
    context: *const Context,
    item: *vk.VkDescriptorSetLayoutBinding,
) !void {
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "descriptorType")) {
            const v = try scanner_next_number(context.scanner);
            item.descriptorType = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "descriptorCount")) {
            const v = try scanner_next_number(context.scanner);
            item.descriptorCount = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "stageFlags")) {
            const v = try scanner_next_number(context.scanner);
            item.stageFlags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "binding")) {
            const v = try scanner_next_number(context.scanner);
            item.binding = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "immutableSamplers")) {
            const samplers = try parse_handle_array(
                vk.VkSampler,
                .SAMPLER,
                context,
            );
            item.pImmutableSamplers = @ptrCast(samplers.ptr);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_descriptor_set_layout_binding" {
    const json =
        \\{
        \\  "descriptorType": 69,
        \\  "descriptorCount": 69,
        \\  "stageFlags": 69,
        \\  "binding": 69,
        \\  "immutableSamplers": [
        \\    "1111111111111111"
        \\  ]
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    try db.entries.getPtr(.SAMPLER).put(alloc, 0x1111111111111111, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });

    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkDescriptorSetLayoutBinding = undefined;
    try parse_vk_descriptor_set_layout_binding(&context, &item);

    try std.testing.expectEqual(item.binding, 69);
    try std.testing.expectEqual(item.descriptorType, 69);
    try std.testing.expectEqual(item.descriptorCount, 69);
    try std.testing.expectEqual(item.stageFlags, 69);
    try std.testing.expect(item.pImmutableSamplers != null);
}

fn parse_vk_pipeline_layout_create_info(
    context: *const Context,
    item: *vk.VkPipelineLayoutCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "pushConstantRanges")) {
            const constant_ranges = try parse_object_array(
                vk.VkPushConstantRange,
                parse_vk_push_constant_range,
                context,
            );
            item.pPushConstantRanges = @ptrCast(constant_ranges.ptr);
            item.pushConstantRangeCount = @intCast(constant_ranges.len);
        } else if (std.mem.eql(u8, s, "setLayouts")) {
            const set_layouts = try parse_handle_array(
                vk.VkDescriptorSetLayout,
                .DESCRIPTOR_SET_LAYOUT,
                context,
            );
            item.pSetLayouts = @ptrCast(set_layouts.ptr);
            item.setLayoutCount = @intCast(set_layouts.len);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_pipeline_layout_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "setLayouts": [
        \\    "1111111111111111"
        \\  ],
        \\  "pushConstantRanges": [{}]
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    try db.entries.getPtr(.DESCRIPTOR_SET_LAYOUT).put(alloc, 0x1111111111111111, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });

    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineLayoutCreateInfo = undefined;
    try parse_vk_pipeline_layout_create_info(&context, &item);

    try std.testing.expectEqual(item.sType, vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO);
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.setLayoutCount, 1);
    try std.testing.expect(item.pSetLayouts != null);
    try std.testing.expectEqual(item.pushConstantRangeCount, 1);
    try std.testing.expect(item.pPushConstantRanges != null);
}

fn parse_vk_push_constant_range(
    context: *const Context,
    item: *vk.VkPushConstantRange,
) !void {
    try parse_simple_type(context, item);
}

test "test_parse_vk_push_constant_range" {
    const json =
        \\{
        \\  "stageFlags": 69,
        \\  "size": 69,
        \\  "offset": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPushConstantRange = undefined;
    try parse_vk_push_constant_range(&context, &item);

    try std.testing.expectEqual(item.stageFlags, 69);
    try std.testing.expectEqual(item.offset, 69);
    try std.testing.expectEqual(item.size, 69);
}

fn parse_vk_shader_module_create_info(
    context: *const Context,
    item: *vk.VkShaderModuleCreateInfo,
    shader_code_payload: []const u8,
) !void {
    const Inner = struct {
        fn decode_shader_payload(input: []const u8, output: []u32) bool {
            var offset: u64 = 0;
            for (output) |*out| {
                out.* = 0;
                var shift: u32 = 0;
                while (true) : ({
                    offset += 1;
                    shift += 7;
                }) {
                    if (input.len < offset or 32 < shift)
                        return false;
                    out.* |= @as(u32, @intCast(input[offset] & 0x7f)) << @truncate(shift);
                    if (input[offset] & 0x80 == 0)
                        break;
                }
                offset += 1;
            }
            return offset == input.len;
        }
    };

    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO };
    // NOTE: there is a possibility that the json object does not have
    // `varintOffset` and `variantSize` fields. In such case the shader code
    // is inlined in the `code` string. Skip this case for now.
    var variant_offset: u64 = 0;
    var variant_size: u64 = 0;
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "varintOffset")) {
            const v = try scanner_next_number(context.scanner);
            variant_offset = try std.fmt.parseInt(u64, v, 10);
        } else if (std.mem.eql(u8, s, "varintSize")) {
            const v = try scanner_next_number(context.scanner);
            variant_size = try std.fmt.parseInt(u64, v, 10);
        } else if (std.mem.eql(u8, s, "codeSize")) {
            const v = try scanner_next_number(context.scanner);
            item.codeSize = try std.fmt.parseInt(u64, v, 10);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
    if (shader_code_payload.len < variant_offset + variant_size)
        return error.InvalidShaderPayload;
    const code = try context.alloc.alignedAlloc(u32, 64, item.codeSize / @sizeOf(u32));
    if (!Inner.decode_shader_payload(
        shader_code_payload[variant_offset..][0..variant_size],
        code,
    ))
        return error.InvalidShaderPayloadEncoding;
    item.pCode = @ptrCast(code.ptr);
}

test "test_parse_vk_shader_module_create_info" {
    const json =
        \\{
        \\  "varintOffset": 0,
        \\  "varintSize": 0,
        \\  "codeSize": 1,
        \\  "flags": 69
        \\}
    ;
    const code = "\x00\x81\x82\x83\x00";
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };

    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkShaderModuleCreateInfo = undefined;
    try parse_vk_shader_module_create_info(&context, &item, code);

    try std.testing.expectEqual(item.sType, vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO);
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.codeSize, 1);
    try std.testing.expect(item.pCode != null);
}

fn parse_vk_render_pass_create_info(
    context: *const Context,
    item: *vk.VkRenderPassCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "dependencies")) {
            const dependencies = try parse_object_array(
                vk.VkSubpassDependency,
                parse_vk_subpass_dependency,
                context,
            );
            item.pDependencies = @ptrCast(dependencies.ptr);
            item.dependencyCount = @intCast(dependencies.len);
        } else if (std.mem.eql(u8, s, "attachments")) {
            const attachments = try parse_object_array(
                vk.VkAttachmentDescription,
                parse_vk_attachment_description,
                context,
            );
            item.pAttachments = @ptrCast(attachments.ptr);
            item.attachmentCount = @intCast(attachments.len);
        } else if (std.mem.eql(u8, s, "subpasses")) {
            const subpasses = try parse_object_array(
                vk.VkSubpassDescription,
                parse_vk_subpass_description,
                context,
            );
            item.pSubpasses = @ptrCast(subpasses.ptr);
            item.subpassCount = @intCast(subpasses.len);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_render_pass_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "dependencies": [{}],
        \\  "attachments": [{}],
        \\  "subpasses": [{}]
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkRenderPassCreateInfo = undefined;
    try parse_vk_render_pass_create_info(&context, &item);

    try std.testing.expectEqual(item.sType, vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO);
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.attachmentCount, 1);
    try std.testing.expect(item.pAttachments != null);
    try std.testing.expectEqual(item.subpassCount, 1);
    try std.testing.expect(item.pSubpasses != null);
    try std.testing.expectEqual(item.dependencyCount, 1);
    try std.testing.expect(item.pDependencies != null);
}

fn parse_vk_subpass_dependency(
    context: *const Context,
    item: *vk.VkSubpassDependency,
) !void {
    try parse_simple_type(context, item);
}

test "test_parse_vk_subpass_dependency" {
    const json =
        \\{
        \\  "dependencyFlags": 69,
        \\  "dstAccessMask": 69,
        \\  "srcAccessMask": 69,
        \\  "dstStageMask": 69,
        \\  "srcStageMask": 69,
        \\  "dstSubpass": 69,
        \\  "srcSubpass": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkSubpassDependency = undefined;
    try parse_vk_subpass_dependency(&context, &item);

    try std.testing.expectEqual(item.srcSubpass, 69);
    try std.testing.expectEqual(item.dstSubpass, 69);
    try std.testing.expectEqual(item.srcStageMask, 69);
    try std.testing.expectEqual(item.dstStageMask, 69);
    try std.testing.expectEqual(item.srcAccessMask, 69);
    try std.testing.expectEqual(item.dstAccessMask, 69);
    try std.testing.expectEqual(item.dependencyFlags, 69);
}

fn parse_vk_attachment_description(
    context: *const Context,
    item: *vk.VkAttachmentDescription,
) !void {
    try parse_simple_type(context, item);
}

test "test_parse_vk_attachment_description" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "format": 69,
        \\  "finalLayout": 69,
        \\  "initialLayout": 69,
        \\  "loadOp": 69,
        \\  "storeOp": 69,
        \\  "samples": 69,
        \\  "stencilLoadOp": 69,
        \\  "stencilStoreOp": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkAttachmentDescription = undefined;
    try parse_vk_attachment_description(&context, &item);

    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.format, 69);
    try std.testing.expectEqual(item.samples, 69);
    try std.testing.expectEqual(item.loadOp, 69);
    try std.testing.expectEqual(item.storeOp, 69);
    try std.testing.expectEqual(item.stencilLoadOp, 69);
    try std.testing.expectEqual(item.stencilStoreOp, 69);
    try std.testing.expectEqual(item.initialLayout, 69);
    try std.testing.expectEqual(item.finalLayout, 69);
}

fn parse_vk_subpass_description(
    context: *const Context,
    item: *vk.VkSubpassDescription,
) !void {
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "pipelineBindPoint")) {
            const v = try scanner_next_number(context.scanner);
            item.pipelineBindPoint = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "inputAttachments")) {
            const attachments = try parse_object_array(
                vk.VkAttachmentReference,
                parse_vk_attachment_reference,
                context,
            );
            item.pInputAttachments = @ptrCast(attachments.ptr);
            item.inputAttachmentCount = @intCast(attachments.len);
        } else if (std.mem.eql(u8, s, "colorAttachments")) {
            const attachments = try parse_object_array(
                vk.VkAttachmentReference,
                parse_vk_attachment_reference,
                context,
            );
            item.pColorAttachments = @ptrCast(attachments.ptr);
            item.colorAttachmentCount = @intCast(attachments.len);
        } else if (std.mem.eql(u8, s, "resolveAttachments")) {
            const attachments = try parse_object_array(
                vk.VkAttachmentReference,
                parse_vk_attachment_reference,
                context,
            );
            item.pResolveAttachments = @ptrCast(attachments.ptr);
        } else if (std.mem.eql(u8, s, "depthStencilAttachment")) {
            const attachment = try context.alloc.create(vk.VkAttachmentReference);
            try parse_vk_attachment_reference(context, attachment);
            item.pDepthStencilAttachment = attachment;
        } else if (std.mem.eql(u8, s, "preserveAttachments")) {
            const attachments = try parse_object_array(
                vk.VkAttachmentReference,
                parse_vk_attachment_reference,
                context,
            );
            item.pPreserveAttachments = @ptrCast(attachments.ptr);
            item.preserveAttachmentCount = @intCast(attachments.len);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_subpass_description" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "pipelineBindPoint": 69,
        \\  "inputAttachments": [{}],
        \\  "colorAttachments": [{}],
        \\  "resolveAttachments": [{}],
        \\  "depthStencilAttachment": {},
        \\  "preserveAttachments": [{}]
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkSubpassDescription = undefined;
    try parse_vk_subpass_description(&context, &item);

    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.pipelineBindPoint, 69);
    try std.testing.expectEqual(item.inputAttachmentCount, 1);
    try std.testing.expect(item.pInputAttachments != null);
    try std.testing.expectEqual(item.colorAttachmentCount, 1);
    try std.testing.expect(item.pColorAttachments != null);
    try std.testing.expect(item.pResolveAttachments != null);
    try std.testing.expect(item.pDepthStencilAttachment != null);
    try std.testing.expectEqual(item.preserveAttachmentCount, 1);
    try std.testing.expect(item.pPreserveAttachments != null);
}

fn parse_vk_attachment_reference(
    context: *const Context,
    item: *vk.VkAttachmentReference,
) !void {
    try parse_simple_type(context, item);
}

test "test_parse_vk_attachment_reference" {
    const json =
        \\{
        \\  "attachment": 69,
        \\  "layout": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkAttachmentReference = undefined;
    try parse_vk_attachment_reference(&context, &item);

    try std.testing.expectEqual(item.attachment, 69);
    try std.testing.expectEqual(item.layout, 69);
}

fn parse_vk_graphics_pipeline_create_info(
    context: *const Context,
    item: *vk.VkGraphicsPipelineCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "stages")) {
            const stages = try parse_object_array(
                vk.VkPipelineShaderStageCreateInfo,
                parse_vk_pipeline_shader_stage_create_info,
                context,
            );
            item.pStages = @ptrCast(stages.ptr);
            item.stageCount = @intCast(stages.len);
        } else if (std.mem.eql(u8, s, "vertexInputState")) {
            const vertex_input_state =
                try context.alloc.create(vk.VkPipelineVertexInputStateCreateInfo);
            try parse_vk_pipeline_vertex_input_state_create_info(context, vertex_input_state);
            item.pVertexInputState = vertex_input_state;
        } else if (std.mem.eql(u8, s, "inputAssemblyState")) {
            const input_assembly_state =
                try context.alloc.create(vk.VkPipelineInputAssemblyStateCreateInfo);
            try parse_vk_pipeline_input_assembly_state_create_info(
                context,
                input_assembly_state,
            );
            item.pInputAssemblyState = input_assembly_state;
        } else if (std.mem.eql(u8, s, "tessellationState")) {
            const tesselation_state =
                try context.alloc.create(vk.VkPipelineTessellationStateCreateInfo);
            try parse_vk_pipeline_tessellation_state_create_info(context, tesselation_state);
            item.pTessellationState = tesselation_state;
        } else if (std.mem.eql(u8, s, "viewportState")) {
            const viewport_state =
                try context.alloc.create(vk.VkPipelineViewportStateCreateInfo);
            try parse_vk_pipeline_viewport_state_create_info(context, viewport_state);
            item.pViewportState = viewport_state;
        } else if (std.mem.eql(u8, s, "rasterizationState")) {
            const raseterization_state =
                try context.alloc.create(vk.VkPipelineRasterizationStateCreateInfo);
            try parse_vk_pipeline_rasterization_state_create_info(context, raseterization_state);
            item.pRasterizationState = raseterization_state;
        } else if (std.mem.eql(u8, s, "multisampleState")) {
            const multisample_state =
                try context.alloc.create(vk.VkPipelineMultisampleStateCreateInfo);
            try parse_vk_pipeline_multisample_state_create_info(context, multisample_state);
            item.pMultisampleState = multisample_state;
        } else if (std.mem.eql(u8, s, "depthStencilState")) {
            const depth_stencil_state =
                try context.alloc.create(vk.VkPipelineDepthStencilStateCreateInfo);
            try parse_vk_pipeline_depth_stencil_state_create_info(context, depth_stencil_state);
            item.pDepthStencilState = depth_stencil_state;
        } else if (std.mem.eql(u8, s, "colorBlendState")) {
            const color_blend_state =
                try context.alloc.create(vk.VkPipelineColorBlendStateCreateInfo);
            try parse_vk_pipeline_color_blend_state_create_info(context, color_blend_state);
            item.pColorBlendState = color_blend_state;
        } else if (std.mem.eql(u8, s, "dynamicState")) {
            const dynamic_state = try context.alloc.create(vk.VkPipelineDynamicStateCreateInfo);
            try parse_vk_pipeline_dynamic_state_create_info(context, dynamic_state);
            item.pDynamicState = dynamic_state;
        } else if (std.mem.eql(u8, s, "layout")) {
            const v = try scanner_next_string(context.scanner);
            const hash = try std.fmt.parseInt(u64, v, 16);
            if (hash != 0) {
                const handle = try context.db.get_handle(.PIPELINE_LAYOUT, hash);
                item.layout = @ptrCast(handle);
            }
        } else if (std.mem.eql(u8, s, "renderPass")) {
            const v = try scanner_next_string(context.scanner);
            const render_pass_hash = try std.fmt.parseInt(u64, v, 16);
            if (render_pass_hash != 0) {
                const handle = try context.db.get_handle(.RENDER_PASS, render_pass_hash);
                item.renderPass = @ptrCast(handle);
            }
        } else if (std.mem.eql(u8, s, "subpass")) {
            const v = try scanner_next_number(context.scanner);
            item.subpass = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "basePipelineHandle")) {
            const v = try scanner_next_string(context.scanner);
            const base_pipeline_hash = try std.fmt.parseInt(u64, v, 16);
            if (base_pipeline_hash != 0)
                return error.BasePipelinesNotSupported;
        } else if (std.mem.eql(u8, s, "basePipelineIndex")) {
            const v = try scanner_next_number(context.scanner);
            item.basePipelineIndex = try std.fmt.parseInt(i32, v, 10);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_graphics_pipeline_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "stages": [{}],
        \\  "vertexInputState": {},
        \\  "inputAssemblyState": {},
        \\  "tessellationState": {},
        \\  "viewportState": {},
        \\  "rasterizationState": {},
        \\  "multisampleState": {},
        \\  "depthStencilState": {},
        \\  "colorBlendState": {},
        \\  "dynamicState": {},
        \\  "layout": "2222222222222222",
        \\  "renderPass": "3333333333333333",
        \\  "subpass": 69,
        \\  "basePipelineHandle": "0000000000000000",
        \\  "basePipelineIndex": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    try db.entries.getPtr(.PIPELINE_LAYOUT).put(alloc, 0x2222222222222222, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });
    try db.entries.getPtr(.RENDER_PASS).put(alloc, 0x3333333333333333, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkGraphicsPipelineCreateInfo = undefined;
    try parse_vk_graphics_pipeline_create_info(&context, &item);

    try std.testing.expectEqual(item.sType, vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO);
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.stageCount, 1);
    try std.testing.expect(item.pStages != null);
    try std.testing.expect(item.pVertexInputState != null);
    try std.testing.expect(item.pInputAssemblyState != null);
    try std.testing.expect(item.pTessellationState != null);
    try std.testing.expect(item.pViewportState != null);
    try std.testing.expect(item.pRasterizationState != null);
    try std.testing.expect(item.pMultisampleState != null);
    try std.testing.expect(item.pDepthStencilState != null);
    try std.testing.expect(item.pColorBlendState != null);
    try std.testing.expect(item.pDynamicState != null);
    try std.testing.expectEqual(@intFromPtr(item.layout), 0x69);
    try std.testing.expectEqual(@intFromPtr(item.renderPass), 0x69);
    try std.testing.expectEqual(item.subpass, 69);
    try std.testing.expectEqual(item.basePipelineHandle, null);
    try std.testing.expectEqual(item.basePipelineIndex, 69);
}

fn parse_vk_pipeline_shader_stage_create_info(
    context: *const Context,
    item: *vk.VkPipelineShaderStageCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "stage")) {
            const v = try scanner_next_number(context.scanner);
            item.stage = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "module")) {
            const hash_str = try scanner_next_string(context.scanner);
            const hash = try std.fmt.parseInt(u64, hash_str, 16);
            const handle = try context.db.get_handle(.SHADER_MODULE, hash);
            item.module = @ptrCast(handle);
        } else if (std.mem.eql(u8, s, "name")) {
            const name_str = try scanner_next_string(context.scanner);
            const name = try context.alloc.dupeZ(u8, name_str);
            item.pName = @ptrCast(name.ptr);
        } else if (std.mem.eql(u8, s, "specializationInfo")) {
            const info = try context.alloc.create(vk.VkSpecializationInfo);
            try parse_vk_specialization_info(context, info);
            item.pSpecializationInfo = info;
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_pipeline_shader_stage_create_info" {
    const json =
        \\{
        \\   "flags": 69,
        \\   "stage": 69,
        \\   "module": "1111111111111111",
        \\   "name": "NAME",
        \\   "specializationInfo": {}
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    try db.entries.getPtr(.SHADER_MODULE).put(alloc, 0x1111111111111111, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineShaderStageCreateInfo = undefined;
    try parse_vk_pipeline_shader_stage_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.stage, 69);
    try std.testing.expectEqual(@intFromPtr(item.module), 0x69);
    try std.testing.expectEqualSlices(u8, std.mem.span(item.pName), "NAME");
    try std.testing.expect(item.pSpecializationInfo != null);
}

fn parse_vk_pipeline_vertex_input_state_create_info(
    context: *const Context,
    item: *vk.VkPipelineVertexInputStateCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "bindings")) {
            const bindings = try parse_object_array(
                vk.VkVertexInputBindingDescription,
                parse_vk_vertex_input_binding_description,
                context,
            );
            item.pVertexBindingDescriptions = @ptrCast(bindings.ptr);
            item.vertexBindingDescriptionCount = @intCast(bindings.len);
        } else if (std.mem.eql(u8, s, "attributes")) {
            const attributes = try parse_object_array(
                vk.VkVertexInputAttributeDescription,
                parse_vk_vertex_input_attribute_description,
                context,
            );
            item.pVertexAttributeDescriptions = @ptrCast(attributes.ptr);
            item.vertexAttributeDescriptionCount = @intCast(attributes.len);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_pipeline_vertex_input_state_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "attributes": [{}],
        \\  "bindings": [{}]
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineVertexInputStateCreateInfo = undefined;
    try parse_vk_pipeline_vertex_input_state_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.vertexBindingDescriptionCount, 1);
    try std.testing.expect(item.pVertexBindingDescriptions != null);
    try std.testing.expectEqual(item.vertexAttributeDescriptionCount, 1);
    try std.testing.expect(item.pVertexAttributeDescriptions != null);
}

fn parse_vk_pipeline_input_assembly_state_create_info(
    context: *const Context,
    item: *vk.VkPipelineInputAssemblyStateCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO };
    try parse_simple_type(context, item);
}

test "test_parse_vk_pipeline_input_assembly_state_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "topology": 69,
        \\  "primitiveRestartEnable": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineInputAssemblyStateCreateInfo = undefined;
    try parse_vk_pipeline_input_assembly_state_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.topology, 69);
    try std.testing.expectEqual(item.primitiveRestartEnable, 69);
}

fn parse_vk_pipeline_tessellation_state_create_info(
    context: *const Context,
    item: *vk.VkPipelineTessellationStateCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO };
    try parse_simple_type(context, item);
}

test "test_parse_vk_pipeline_tessellation_state_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "patchControlPoints": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineTessellationStateCreateInfo = undefined;
    try parse_vk_pipeline_tessellation_state_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.patchControlPoints, 69);
}

fn parse_vk_pipeline_viewport_state_create_info(
    context: *const Context,
    item: *vk.VkPipelineViewportStateCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "viewportCount")) {
            const v = try scanner_next_number(context.scanner);
            item.viewportCount = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "viewports")) {
            const viewports = try parse_object_array(
                vk.VkViewport,
                parse_vk_viewport,
                context,
            );
            item.pViewports = @ptrCast(viewports.ptr);
            item.viewportCount = @intCast(viewports.len);
        } else if (std.mem.eql(u8, s, "scissorCount")) {
            const v = try scanner_next_number(context.scanner);
            item.scissorCount = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "scissors")) {
            const scissors = try parse_object_array(
                vk.VkRect2D,
                parse_vk_rect_2d,
                context,
            );
            item.pScissors = @ptrCast(scissors.ptr);
            item.scissorCount = @intCast(scissors.len);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_pipeline_viewport_state_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "viewportCount": 1,
        \\  "scissorCount": 1,
        \\  "viewports": [{}],
        \\  "scissors": [{}]
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineViewportStateCreateInfo = undefined;
    try parse_vk_pipeline_viewport_state_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.viewportCount, 1);
    try std.testing.expect(item.pViewports != null);
    try std.testing.expectEqual(item.scissorCount, 1);
    try std.testing.expect(item.pScissors != null);
}

fn parse_vk_pipeline_rasterization_state_create_info(
    context: *const Context,
    item: *vk.VkPipelineRasterizationStateCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO };
    try parse_simple_type(context, item);
}

test "test_parse_vk_pipeline_rasterization_state_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "depthClampEnable": 69,
        \\  "rasterizerDiscardEnable": 69,
        \\  "polygonMode": 69,
        \\  "cullMode": 69,
        \\  "frontFace": 69,
        \\  "depthBiasEnable": 69,
        \\  "depthBiasConstantFactor": 69,
        \\  "depthBiasClamp": 69,
        \\  "depthBiasSlopeFactor": 69,
        \\  "lineWidth": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineRasterizationStateCreateInfo = undefined;
    try parse_vk_pipeline_rasterization_state_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.depthClampEnable, 69);
    try std.testing.expectEqual(item.rasterizerDiscardEnable, 69);
    try std.testing.expectEqual(item.polygonMode, 69);
    try std.testing.expectEqual(item.cullMode, 69);
    try std.testing.expectEqual(item.frontFace, 69);
    try std.testing.expectEqual(item.depthBiasEnable, 69);
    try std.testing.expectEqual(item.depthBiasConstantFactor, 69);
    try std.testing.expectEqual(item.depthBiasClamp, 69);
    try std.testing.expectEqual(item.depthBiasSlopeFactor, 69);
    try std.testing.expectEqual(item.lineWidth, 69);
}

fn parse_vk_pipeline_multisample_state_create_info(
    context: *const Context,
    item: *vk.VkPipelineMultisampleStateCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "rasterizationSamples")) {
            const v = try scanner_next_number(context.scanner);
            item.rasterizationSamples = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "sampleShadingEnable")) {
            const v = try scanner_next_number(context.scanner);
            item.sampleShadingEnable = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "minSampleShading")) {
            const v = try scanner_next_number(context.scanner);
            item.minSampleShading = try std.fmt.parseFloat(f32, v);
        } else if (std.mem.eql(u8, s, "sampleMask")) {
            const mask = try parse_number_array(u32, context);
            item.pSampleMask = @ptrCast(mask.ptr);
        } else if (std.mem.eql(u8, s, "alphaToCoverageEnable")) {
            const v = try scanner_next_number(context.scanner);
            item.alphaToCoverageEnable = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "alphaToOneEnable")) {
            const v = try scanner_next_number(context.scanner);
            item.alphaToOneEnable = try std.fmt.parseInt(u32, v, 10);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_pipeline_multisample_state_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "rasterizationSamples": 69,
        \\  "sampleShadingEnable": 69,
        \\  "minSampleShading": 69,
        \\  "sampleMask": [
        \\    69
        \\  ],
        \\  "alphaToCoverageEnable": 69,
        \\  "alphaToOneEnable": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineMultisampleStateCreateInfo = undefined;
    try parse_vk_pipeline_multisample_state_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.rasterizationSamples, 69);
    try std.testing.expectEqual(item.sampleShadingEnable, 69);
    try std.testing.expectEqual(item.minSampleShading, 69);
    try std.testing.expect(item.pSampleMask != null);
    try std.testing.expectEqual(item.alphaToCoverageEnable, 69);
    try std.testing.expectEqual(item.alphaToOneEnable, 69);
}

fn parse_vk_stencil_op_state(
    context: *const Context,
    item: *vk.VkStencilOpState,
) !void {
    try parse_simple_type(context, item);
}

test "test_parse_vk_stencil_op_state" {
    const json =
        \\{
        \\  "failOp": 69,
        \\  "passOp": 69,
        \\  "depthFailOp": 69,
        \\  "compareOp": 69,
        \\  "compareMask": 69,
        \\  "writeMask": 69,
        \\  "reference": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkStencilOpState = undefined;
    try parse_vk_stencil_op_state(&context, &item);

    try std.testing.expectEqual(item.failOp, 69);
    try std.testing.expectEqual(item.passOp, 69);
    try std.testing.expectEqual(item.depthFailOp, 69);
    try std.testing.expectEqual(item.compareOp, 69);
    try std.testing.expectEqual(item.compareMask, 69);
    try std.testing.expectEqual(item.writeMask, 69);
    try std.testing.expectEqual(item.reference, 69);
}

fn parse_vk_pipeline_depth_stencil_state_create_info(
    context: *const Context,
    item: *vk.VkPipelineDepthStencilStateCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "depthTestEnable")) {
            const v = try scanner_next_number(context.scanner);
            item.depthTestEnable = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "depthWriteEnable")) {
            const v = try scanner_next_number(context.scanner);
            item.depthWriteEnable = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "depthCompareOp")) {
            const v = try scanner_next_number(context.scanner);
            item.depthCompareOp = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "depthBoundsTestEnable")) {
            const v = try scanner_next_number(context.scanner);
            item.depthBoundsTestEnable = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "stencilTestEnable")) {
            const v = try scanner_next_number(context.scanner);
            item.stencilTestEnable = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "front")) {
            try parse_vk_stencil_op_state(context, &item.front);
        } else if (std.mem.eql(u8, s, "back")) {
            try parse_vk_stencil_op_state(context, &item.back);
        } else if (std.mem.eql(u8, s, "minDepthBounds")) {
            const v = try scanner_next_number(context.scanner);
            item.minDepthBounds = try std.fmt.parseFloat(f32, v);
        } else if (std.mem.eql(u8, s, "maxDepthBounds")) {
            const v = try scanner_next_number(context.scanner);
            item.maxDepthBounds = try std.fmt.parseFloat(f32, v);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_pipeline_depth_stencil_state_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "depthTestEnable": 69,
        \\  "depthWriteEnable": 69,
        \\  "depthCompareOp": 69,
        \\  "depthBoundsTestEnable": 69,
        \\  "stencilTestEnable": 69,
        \\  "front": {},
        \\  "back": {},
        \\  "minDepthBounds": 69,
        \\  "maxDepthBounds": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineDepthStencilStateCreateInfo = undefined;
    try parse_vk_pipeline_depth_stencil_state_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.depthTestEnable, 69);
    try std.testing.expectEqual(item.depthWriteEnable, 69);
    try std.testing.expectEqual(item.depthCompareOp, 69);
    try std.testing.expectEqual(item.depthBoundsTestEnable, 69);
    try std.testing.expectEqual(item.stencilTestEnable, 69);
    try std.testing.expectEqual(item.front, vk.VkStencilOpState{});
    try std.testing.expectEqual(item.back, vk.VkStencilOpState{});
    try std.testing.expectEqual(item.minDepthBounds, 69);
    try std.testing.expectEqual(item.maxDepthBounds, 69);
}

fn parse_vk_pipeline_color_blend_state_create_info(
    context: *const Context,
    item: *vk.VkPipelineColorBlendStateCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "logicOpEnable")) {
            const v = try scanner_next_number(context.scanner);
            item.logicOpEnable = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "logicOp")) {
            const v = try scanner_next_number(context.scanner);
            item.logicOp = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "attachments")) {
            const attachments = try parse_object_array(
                vk.VkPipelineColorBlendAttachmentState,
                parse_vk_pipeline_color_blend_attachment_state,
                context,
            );
            item.pAttachments = @ptrCast(attachments.ptr);
            item.attachmentCount = @intCast(attachments.len);
        } else if (std.mem.eql(u8, s, "blendConstants")) {
            try scanner_array_begin(context.scanner);
            var i: u32 = 0;
            while (try scanner_array_next_number(context.scanner)) |v| {
                item.blendConstants[i] = try std.fmt.parseFloat(f32, v);
                i += 1;
            }
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_pipeline_color_blend_state_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "logicOpEnable": 69,
        \\  "logicOp": 69,
        \\  "attachments": [{}],
        \\  "blendConstants": [
        \\    69.69,
        \\    69.69,
        \\    69.69,
        \\    69.69
        \\  ]
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineColorBlendStateCreateInfo = undefined;
    try parse_vk_pipeline_color_blend_state_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.logicOpEnable, 69);
    try std.testing.expectEqual(item.logicOp, 69);
    try std.testing.expectEqual(item.attachmentCount, 1);
    try std.testing.expect(item.pAttachments != null);
    try std.testing.expectEqual(item.blendConstants, [4]f32{ 69.69, 69.69, 69.69, 69.69 });
}

fn parse_vk_pipeline_dynamic_state_create_info(
    context: *const Context,
    item: *vk.VkPipelineDynamicStateCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "dynamicState")) {
            const states = try parse_number_array(u32, context);
            item.pDynamicStates = @ptrCast(states.ptr);
            item.dynamicStateCount = @intCast(states.len);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_pipeline_dynamic_state_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "dynamicState": [
        \\    69
        \\  ]
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineDynamicStateCreateInfo = undefined;
    try parse_vk_pipeline_dynamic_state_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.dynamicStateCount, 1);
    try std.testing.expect(item.pDynamicStates != null);
}

fn parse_vk_vertex_input_attribute_description(
    context: *const Context,
    item: *vk.VkVertexInputAttributeDescription,
) !void {
    try parse_simple_type(context, item);
}

test "test_parse_vk_vertex_input_attribute_description" {
    const json =
        \\{
        \\  "location": 69,
        \\  "binding": 69,
        \\  "format": 69,
        \\  "offset": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkVertexInputAttributeDescription = undefined;
    try parse_vk_vertex_input_attribute_description(&context, &item);

    try std.testing.expectEqual(item.location, 69);
    try std.testing.expectEqual(item.binding, 69);
    try std.testing.expectEqual(item.format, 69);
    try std.testing.expectEqual(item.offset, 69);
}

fn parse_vk_vertex_input_binding_description(
    context: *const Context,
    item: *vk.VkVertexInputBindingDescription,
) !void {
    try parse_simple_type(context, item);
}

test "test_parse_vk_vertex_input_binding_description" {
    const json =
        \\{
        \\  "binding": 69,
        \\  "stride": 69,
        \\  "inputRate": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkVertexInputBindingDescription = undefined;
    try parse_vk_vertex_input_binding_description(&context, &item);

    try std.testing.expectEqual(item.binding, 69);
    try std.testing.expectEqual(item.stride, 69);
    try std.testing.expectEqual(item.inputRate, 69);
}

fn parse_vk_pipeline_color_blend_attachment_state(
    context: *const Context,
    item: *vk.VkPipelineColorBlendAttachmentState,
) !void {
    try parse_simple_type(context, item);
}

test "test_parse_vk_pipeline_color_blend_attachment_state" {
    const json =
        \\{
        \\  "blendEnable": 69,
        \\  "srcColorBlendFactor": 69,
        \\  "dstColorBlendFactor": 69,
        \\  "colorBlendOp": 69,
        \\  "srcAlphaBlendFactor": 69,
        \\  "dstAlphaBlendFactor": 69,
        \\  "alphaBlendOp": 69,
        \\  "colorWriteMask": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineColorBlendAttachmentState = undefined;
    try parse_vk_pipeline_color_blend_attachment_state(&context, &item);

    try std.testing.expectEqual(item.blendEnable, 69);
    try std.testing.expectEqual(item.srcColorBlendFactor, 69);
    try std.testing.expectEqual(item.dstColorBlendFactor, 69);
    try std.testing.expectEqual(item.colorBlendOp, 69);
    try std.testing.expectEqual(item.srcAlphaBlendFactor, 69);
    try std.testing.expectEqual(item.dstAlphaBlendFactor, 69);
    try std.testing.expectEqual(item.alphaBlendOp, 69);
    try std.testing.expectEqual(item.colorWriteMask, 69);
}

fn parse_vk_viewport(
    context: *const Context,
    item: *vk.VkViewport,
) !void {
    try parse_simple_type(context, item);
}

test "test_parse_vk_viewport" {
    const json =
        \\{
        \\  "x": 69.69,
        \\  "y": 69.69,
        \\  "width": 69.69,
        \\  "height": 69.69,
        \\  "minDepth": 69.69,
        \\  "maxDepth": 69.69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkViewport = undefined;
    try parse_vk_viewport(&context, &item);

    try std.testing.expectEqual(item.x, 69.69);
    try std.testing.expectEqual(item.y, 69.69);
    try std.testing.expectEqual(item.width, 69.69);
    try std.testing.expectEqual(item.height, 69.69);
    try std.testing.expectEqual(item.minDepth, 69.69);
    try std.testing.expectEqual(item.maxDepth, 69.69);
}

fn parse_vk_rect_2d(
    context: *const Context,
    item: *vk.VkRect2D,
) !void {
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "x")) {
            const v = try scanner_next_number(context.scanner);
            item.offset.x = try std.fmt.parseInt(i32, v, 10);
        } else if (std.mem.eql(u8, s, "y")) {
            const v = try scanner_next_number(context.scanner);
            item.offset.y = try std.fmt.parseInt(i32, v, 10);
        } else if (std.mem.eql(u8, s, "width")) {
            const v = try scanner_next_number(context.scanner);
            item.extent.width = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "height")) {
            const v = try scanner_next_number(context.scanner);
            item.extent.height = try std.fmt.parseInt(u32, v, 10);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_rect_2d" {
    const json =
        \\{
        \\  "x": 69,
        \\  "y": 69,
        \\  "width": 69,
        \\  "height": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkRect2D = undefined;
    try parse_vk_rect_2d(&context, &item);

    try std.testing.expectEqual(item.offset.x, 69);
    try std.testing.expectEqual(item.offset.y, 69);
    try std.testing.expectEqual(item.extent.width, 69);
    try std.testing.expectEqual(item.extent.height, 69);
}

fn parse_vk_specialization_map_entry(
    context: *const Context,
    item: *vk.VkSpecializationMapEntry,
) !void {
    try parse_simple_type(context, item);
}

test "test_parse_vk_specialization_map_entry" {
    const json =
        \\{
        \\  "constantID": 69,
        \\  "offset": 69,
        \\  "size": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkSpecializationMapEntry = undefined;
    try parse_vk_specialization_map_entry(&context, &item);

    try std.testing.expectEqual(item.constantID, 69);
    try std.testing.expectEqual(item.offset, 69);
    try std.testing.expectEqual(item.size, 69);
}

fn parse_vk_specialization_info(
    context: *const Context,
    item: *vk.VkSpecializationInfo,
) !void {
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "dataSize")) {
            const v = try scanner_next_number(context.scanner);
            item.dataSize = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "data")) {
            const data_str = try scanner_next_string(context.scanner);
            var decoder = std.base64.standard.Decoder;
            const data_size = try decoder.calcSizeForSlice(data_str);
            const data = try context.alloc.alloc(u8, data_size);
            try decoder.decode(data, data_str);
            item.pData = @ptrCast(data.ptr);
        } else if (std.mem.eql(u8, s, "mapEntries")) {
            const entries = try parse_object_array(
                vk.VkSpecializationMapEntry,
                parse_vk_specialization_map_entry,
                context,
            );
            item.pMapEntries = @ptrCast(entries.ptr);
            item.mapEntryCount = @intCast(entries.len);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_specialization_info" {
    const json =
        \\{
        \\  "mapEntries": [{}],
        \\  "dataSize": 69,
        \\  "data": ""
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkSpecializationInfo = undefined;
    try parse_vk_specialization_info(&context, &item);

    try std.testing.expectEqual(item.mapEntryCount, 1);
    try std.testing.expect(item.pMapEntries != null);
    try std.testing.expectEqual(item.dataSize, 69);
    try std.testing.expect(item.pData != null);
}

fn parse_vk_compute_pipeline_create_info(
    context: *const Context,
    item: *vk.VkComputePipelineCreateInfo,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "stage")) {
            try parse_vk_pipeline_shader_stage_create_info(
                context,
                &item.stage,
            );
        } else if (std.mem.eql(u8, s, "layout")) {
            const v = try scanner_next_string(context.scanner);
            const hash = try std.fmt.parseInt(u64, v, 16);
            if (hash != 0) {
                const handle = try context.db.get_handle(.PIPELINE_LAYOUT, hash);
                item.layout = @ptrCast(handle);
            }
        } else if (std.mem.eql(u8, s, "basePipelineHandle")) {
            const v = try scanner_next_string(context.scanner);
            const base_pipeline_hash = try std.fmt.parseInt(u64, v, 16);
            if (base_pipeline_hash != 0)
                return error.BasePipelinesNotSupported;
        } else if (std.mem.eql(u8, s, "basePipelineIndex")) {
            const v = try scanner_next_number(context.scanner);
            item.basePipelineIndex = try std.fmt.parseInt(i32, v, 10);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_compute_pipeline_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "stage": {},
        \\  "layout": "1111111111111111",
        \\  "basePipelineHandle": "0000000000000000",
        \\  "basePipelineIndex": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    try db.entries.getPtr(.PIPELINE_LAYOUT).put(alloc, 0x1111111111111111, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });

    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkComputePipelineCreateInfo = undefined;
    try parse_vk_compute_pipeline_create_info(&context, &item);

    try std.testing.expectEqual(item.sType, vk.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO);
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.stage, vk.VkPipelineShaderStageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
    });
    try std.testing.expectEqual(@intFromPtr(item.layout), 0x69);
    try std.testing.expectEqual(item.basePipelineHandle, null);
    try std.testing.expectEqual(item.basePipelineIndex, 69);
}

fn parse_vk_raytracing_pipeline_create_info(
    context: *const Context,
    item: *vk.VkRayTracingPipelineCreateInfoKHR,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_CREATE_INFO_KHR };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "flags")) {
            const v = try scanner_next_number(context.scanner);
            item.flags = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "stages")) {
            const stages = try parse_object_array(
                vk.VkPipelineShaderStageCreateInfo,
                parse_vk_pipeline_shader_stage_create_info,
                context,
            );
            item.pStages = @ptrCast(stages.ptr);
            item.stageCount = @intCast(stages.len);
        } else if (std.mem.eql(u8, s, "groups")) {
            const groups = try parse_object_array(
                vk.VkRayTracingShaderGroupCreateInfoKHR,
                parse_vk_ray_tracing_shader_group_create_info,
                context,
            );
            item.pGroups = @ptrCast(groups.ptr);
            item.groupCount = @intCast(groups.len);
        } else if (std.mem.eql(u8, s, "libraryInfo")) {
            const library =
                try context.alloc.create(vk.VkPipelineLibraryCreateInfoKHR);
            try parse_vk_pipeline_library_create_info(context, library);
            item.pLibraryInfo = library;
        } else if (std.mem.eql(u8, s, "libraryInterface")) {
            const interface =
                try context.alloc.create(vk.VkRayTracingPipelineInterfaceCreateInfoKHR);
            try parse_vk_ray_tracing_pipeline_interface_create_info(context, interface);
            item.pLibraryInterface = interface;
        } else if (std.mem.eql(u8, s, "maxPipelineRayRecursionDepth")) {
            const v = try scanner_next_number(context.scanner);
            item.maxPipelineRayRecursionDepth = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "dynamicState")) {
            const dynamic_state = try context.alloc.create(vk.VkPipelineDynamicStateCreateInfo);
            try parse_vk_pipeline_dynamic_state_create_info(context, dynamic_state);
            item.pDynamicState = dynamic_state;
        } else if (std.mem.eql(u8, s, "layout")) {
            const v = try scanner_next_string(context.scanner);
            const hash = try std.fmt.parseInt(u64, v, 16);
            if (hash != 0) {
                const handle = try context.db.get_handle(.PIPELINE_LAYOUT, hash);
                item.layout = @ptrCast(handle);
            }
        } else if (std.mem.eql(u8, s, "basePipelineHandle")) {
            const v = try scanner_next_string(context.scanner);
            const base_pipeline_hash = try std.fmt.parseInt(u64, v, 16);
            if (base_pipeline_hash != 0)
                return error.BasePipelinesNotSupported;
        } else if (std.mem.eql(u8, s, "basePipelineIndex")) {
            const v = try scanner_next_number(context.scanner);
            item.basePipelineIndex = try std.fmt.parseInt(i32, v, 10);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_raytracing_pipeline_create_info" {
    const json =
        \\{
        \\  "flags": 69,
        \\  "stages": [{}],
        \\  "groups": [{}],
        \\  "maxPipelineRayRecursionDepth": 69,
        \\  "libraryInfo": {},
        \\  "libraryInterface": {},
        \\  "dynamicState": {},
        \\  "layout": "1111111111111111",
        \\  "basePipelineHandle": "0000000000000000",
        \\  "basePipelineIndex": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    try db.entries.getPtr(.PIPELINE_LAYOUT).put(alloc, 0x1111111111111111, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkRayTracingPipelineCreateInfoKHR = undefined;
    try parse_vk_raytracing_pipeline_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_CREATE_INFO_KHR,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.flags, 69);
    try std.testing.expectEqual(item.stageCount, 1);
    try std.testing.expect(item.pStages != null);
    try std.testing.expectEqual(item.groupCount, 1);
    try std.testing.expect(item.pGroups != null);
    try std.testing.expectEqual(item.maxPipelineRayRecursionDepth, 69);
    try std.testing.expect(item.pLibraryInfo != null);
    try std.testing.expect(item.pLibraryInterface != null);
    try std.testing.expect(item.pDynamicState != null);
    try std.testing.expectEqual(@intFromPtr(item.layout), 0x69);
    try std.testing.expectEqual(item.basePipelineHandle, null);
    try std.testing.expectEqual(item.basePipelineIndex, 69);
}

fn parse_vk_ray_tracing_shader_group_create_info(
    context: *const Context,
    item: *vk.VkRayTracingShaderGroupCreateInfoKHR,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR };
    try parse_simple_type(context, item);
}

test "test_parse_vk_ray_tracing_shader_group_create_info" {
    const json =
        \\{
        \\  "type": 69,
        \\  "generalShader": 69,
        \\  "closestHitShader": 69,
        \\  "anyHitShader": 69,
        \\  "intersectionShader": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkRayTracingShaderGroupCreateInfoKHR = undefined;
    try parse_vk_ray_tracing_shader_group_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.type, 69);
    try std.testing.expectEqual(item.generalShader, 69);
    try std.testing.expectEqual(item.closestHitShader, 69);
    try std.testing.expectEqual(item.anyHitShader, 69);
    try std.testing.expectEqual(item.intersectionShader, 69);
    try std.testing.expectEqual(item.pShaderGroupCaptureReplayHandle, null);
}

fn parse_vk_pipeline_library_create_info(
    context: *const Context,
    item: *vk.VkPipelineLibraryCreateInfoKHR,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LIBRARY_CREATE_INFO_KHR };
    while (try scanner_object_next_field(context.scanner)) |s| {
        if (std.mem.eql(u8, s, "pNext")) {
            item.pNext = try parse_pnext_chain(context);
        } else if (std.mem.eql(u8, s, "libraries")) {
            const libraries = try parse_handle_array(
                vk.VkPipeline,
                .RAYTRACING_PIPELINE,
                context,
            );
            item.pLibraries = @ptrCast(libraries.ptr);
            item.libraryCount = @intCast(libraries.len);
        } else {
            const v = try scanner_next_number_or_string(context.scanner);
            log.warn(@src(), "Skipping unknown field {s}: {s}", .{ s, v });
        }
    }
}

test "test_parse_vk_pipeline_library_create_info" {
    const json =
        \\{
        \\  "libraries": ["1111111111111111"]
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    try db.entries.getPtr(.RAYTRACING_PIPELINE).put(alloc, 0x1111111111111111, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkPipelineLibraryCreateInfoKHR = undefined;
    try parse_vk_pipeline_library_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_PIPELINE_LIBRARY_CREATE_INFO_KHR,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.libraryCount, 1);
    try std.testing.expect(item.pLibraries != null);
}

fn parse_vk_ray_tracing_pipeline_interface_create_info(
    context: *const Context,
    item: *vk.VkRayTracingPipelineInterfaceCreateInfoKHR,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_INTERFACE_CREATE_INFO_KHR };
    try parse_simple_type(context, item);
}

test "test_parse_vk_ray_tracing_pipeline_interface_create_info" {
    const json =
        \\{
        \\  "maxPipelineRayPayloadSize": 69,
        \\  "maxPipelineRayHitAttributeSize": 69
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const db: Database = .{ .file_mem = &.{}, .entries = .initFill(.empty), .arena = arena };
    var scanner = std.json.Scanner.initCompleteInput(alloc, json);
    const context = Context{
        .alloc = alloc,
        .tmp_alloc = alloc,
        .scanner = &scanner,
        .db = &db,
    };

    var item: vk.VkRayTracingPipelineInterfaceCreateInfoKHR = undefined;
    try parse_vk_ray_tracing_pipeline_interface_create_info(&context, &item);

    try std.testing.expectEqual(
        item.sType,
        vk.VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_INTERFACE_CREATE_INFO_KHR,
    );
    try std.testing.expectEqual(item.pNext, null);
    try std.testing.expectEqual(item.maxPipelineRayPayloadSize, 69);
    try std.testing.expectEqual(item.maxPipelineRayHitAttributeSize, 69);
}
