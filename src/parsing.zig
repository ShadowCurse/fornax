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
        \\  "version": 6,
        \\  "applicationInfo": {
        \\    "applicationName": "citadel",
        \\    "engineName": "Source2",
        \\    "applicationVersion": 1,
        \\    "engineVersion": 1,
        \\    "apiVersion": 4202496
        \\  },
        \\  "physicalDeviceFeatures": {
        \\    "robustBufferAccess": 0,
        \\    "pNext": [
        \\      {
        \\        "sType": 1000328000,
        \\        "taskShader": 1,
        \\        "meshShader": 1,
        \\        "multiviewMeshShader": 1,
        \\        "primitiveFragmentShadingRateMeshShader": 0,
        \\        "meshShaderQueries": 1
        \\      },
        \\      {
        \\        "sType": 1000226003,
        \\        "pipelineFragmentShadingRate": 1,
        \\        "primitiveFragmentShadingRate": 1,
        \\        "attachmentFragmentShadingRate": 1
        \\      }
        \\    ]
        \\  }
        \\}
    ;
    var gpa = std.heap.DebugAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const alloc = arena.allocator();
    var scratch_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const tmp_alloc = scratch_arena.allocator();

    const db: Database = .{
        .file_mem = &.{},
        .entries = .initFill(.empty),
        .arena = arena,
    };

    const parsed_application_info = try parse_application_info(alloc, tmp_alloc, &db, json);
    vk_print.print_chain(parsed_application_info.application_info);
    vk_print.print_chain(parsed_application_info.device_features2);
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
        \\   "version": 6,
        \\   "samplers": {
        \\     "88201fb960ff6465": {
        \\       "flags": 0,
        \\       "minFilter": 0,
        \\       "magFilter": 0,
        \\       "maxAnisotropy": 0,
        \\       "compareOp": 0,
        \\       "anisotropyEnable": 0,
        \\       "mipmapMode": 0,
        \\       "addressModeU": 0,
        \\       "addressModeV": 0,
        \\       "addressModeW": 0,
        \\       "borderColor": 0,
        \\       "unnormalizedCoordinates": 0,
        \\       "compareEnable": 0,
        \\       "mipLodBias": 0,
        \\       "minLod": 0,
        \\       "maxLod": 0
        \\     }
        \\   }
        \\ }
    ;
    var gpa = std.heap.DebugAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const tmp_alloc = tmp_arena.allocator();

    const db: Database = .{
        .file_mem = &.{},
        .entries = .initFill(.empty),
        .arena = arena,
    };

    const parsed_sampler = try parse_sampler(alloc, tmp_alloc, &db, json);
    vk_print.print_struct(parsed_sampler.create_info);
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
        \\  "version": 6,
        \\  "setLayouts": {
        \\    "01fe45398ef51d72": {
        \\      "flags": 2,
        \\      "bindings": [
        \\        {
        \\          "descriptorType": 0,
        \\          "descriptorCount": 2048,
        \\          "stageFlags": 16185,
        \\          "binding": 29
        \\        },
        \\        {
        \\          "descriptorType": 2,
        \\          "descriptorCount": 65536,
        \\          "stageFlags": 16185,
        \\          "binding": 46,
        \\          "immutableSamplers": [
        \\            "8c0a0c8a78e29f7c"
        \\          ]
        \\        }
        \\      ],
        \\      "pNext": [
        \\        {
        \\          "sType": 1000161000,
        \\          "bindingFlags": [
        \\            5,
        \\            5
        \\          ]
        \\        }
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    var gpa = std.heap.DebugAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const tmp_alloc = tmp_arena.allocator();

    var db: Database = .{
        .file_mem = &.{},
        .entries = .initFill(.empty),
        .arena = arena,
    };
    try db.entries.getPtr(.SAMPLER).put(alloc, 0x8c0a0c8a78e29f7c, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });

    const parsed_descriptro_set_layout = try parse_descriptor_set_layout(
        alloc,
        tmp_alloc,
        &db,
        json,
    );
    vk_print.print_chain(parsed_descriptro_set_layout.create_info);
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
        \\  "version": 6,
        \\  "pipelineLayouts": {
        \\    "3dc5f23c21306af3": {
        \\      "flags": 0,
        \\      "pushConstantRanges": [
        \\        {
        \\          "stageFlags": 17,
        \\          "size": 16,
        \\          "offset": 0
        \\        }
        \\      ],
        \\      "setLayouts": [
        \\        "cb32b2cfac4b21ee"
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    var gpa = std.heap.DebugAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const tmp_alloc = tmp_arena.allocator();

    var db: Database = .{
        .file_mem = &.{},
        .entries = .initFill(.empty),
        .arena = arena,
    };
    try db.entries.getPtr(.DESCRIPTOR_SET_LAYOUT).put(alloc, 0xcb32b2cfac4b21ee, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });

    const parsed_pipeline_layout = try parse_pipeline_layout(
        alloc,
        tmp_alloc,
        &db,
        json,
    );
    vk_print.print_chain(parsed_pipeline_layout.create_info);
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
    const Inner = struct {
        fn parse_vk_shader_module_create_info(
            context: *const Context,
            item: *vk.VkShaderModuleCreateInfo,
            shader_code_payload: []const u8,
        ) !void {
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
            if (!decode_shader_payload(
                shader_code_payload[variant_offset..][0..variant_size],
                code,
            ))
                return error.InvalidShaderPayloadEncoding;
            item.pCode = @ptrCast(code.ptr);
        }

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
            try Inner.parse_vk_shader_module_create_info(
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
        \\  "version": 6,
        \\  "shaderModules": {
        \\    "959dfe0bd6073194": {
        \\      "varintOffset": 0,
        \\      "varintSize": 4,
        \\      "codeSize": 4,
        \\      "flags": 0
        \\    }
        \\  }
        \\}
    ++ "\x00\x81\x82\x83\x00";
    var gpa = std.heap.DebugAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const tmp_alloc = tmp_arena.allocator();

    const db: Database = .{
        .file_mem = &.{},
        .entries = .initFill(.empty),
        .arena = arena,
    };

    const parsed_shader_module = try parse_shader_module(alloc, tmp_alloc, &db, json);
    vk_print.print_struct(parsed_shader_module.create_info);
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
        \\  "version": 6,
        \\  "renderPasses": {
        \\    "016fdf9b69978eb6": {
        \\      "flags": 0,
        \\      "dependencies": [
        \\        {
        \\          "dependencyFlags": 0,
        \\          "dstAccessMask": 384,
        \\          "srcAccessMask": 0,
        \\          "dstStageMask": 1024,
        \\          "srcStageMask": 1024,
        \\          "dstSubpass": 0,
        \\          "srcSubpass": 4294967295
        \\        }
        \\      ],
        \\      "attachments": [
        \\        {
        \\          "flags": 0,
        \\          "format": 43,
        \\          "finalLayout": 1000001002,
        \\          "initialLayout": 1000001002,
        \\          "loadOp": 0,
        \\          "storeOp": 0,
        \\          "samples": 1,
        \\          "stencilLoadOp": 0,
        \\          "stencilStoreOp": 0
        \\        }
        \\      ],
        \\      "subpasses": [
        \\        {
        \\          "flags": 0,
        \\          "pipelineBindPoint": 0,
        \\          "inputAttachments": [
        \\            {
        \\              "attachment": 0,
        \\              "layout": 2
        \\            }
        \\          ],
        \\          "colorAttachments": [
        \\            {
        \\              "attachment": 0,
        \\              "layout": 2
        \\            }
        \\          ],
        \\          "resolveAttachments": [
        \\            {
        \\              "attachment": 0,
        \\              "layout": 2
        \\            }
        \\          ],
        \\          "depthStencilAttachment": {
        \\            "attachment": 0,
        \\            "layout": 2
        \\          },
        \\          "preserveAttachments": [
        \\            {
        \\              "attachment": 0,
        \\              "layout": 2
        \\            }
        \\          ]
        \\        }
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    var gpa = std.heap.DebugAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const tmp_alloc = tmp_arena.allocator();

    const db: Database = .{
        .file_mem = &.{},
        .entries = .initFill(.empty),
        .arena = arena,
    };

    const parsed_render_pass = try parse_render_pass(alloc, tmp_alloc, &db, json);
    vk_print.print_struct(parsed_render_pass.create_info);
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
        \\  "version": 6,
        \\  "computePipelines": {
        \\    "1111111111111111": {
        \\      "flags": 0,
        \\      "layout": "2222222222222222",
        \\      "basePipelineHandle": "0000000000000000",
        \\      "basePipelineIndex": -1,
        \\      "stage": {
        \\        "flags": 0,
        \\        "stage": 32,
        \\        "module": "3333333333333333",
        \\        "name": "MainCs",
        \\        "pNext": [
        \\          {
        \\            "sType": 1000225001,
        \\            "requiredSubgroupSize": 32
        \\          }
        \\        ]
        \\      }
        \\    }
        \\  }
        \\}
    ;
    var gpa = std.heap.DebugAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const tmp_alloc = tmp_arena.allocator();

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
    try db.entries.getPtr(.SHADER_MODULE).put(alloc, 0x3333333333333333, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });

    const parsed_compute_pipeline = try parse_compute_pipeline(alloc, tmp_alloc, &db, json);
    vk_print.print_struct(parsed_compute_pipeline.create_info);
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
        \\  "version": 6,
        \\  "raytracingPipelines": {
        \\    "1111111111111111": {
        \\      "flags": 0,
        \\      "layout": "2222222222222222",
        \\      "basePipelineHandle": "0000000000000000",
        \\      "basePipelineIndex": -1,
        \\      "maxPipelineRayRecursionDepth": 1,
        \\      "stages": [
        \\        {
        \\          "flags": 0,
        \\          "name": "RayGen",
        \\          "module": "3333333333333333",
        \\          "stage": 256
        \\        },
        \\        {
        \\          "flags": 0,
        \\          "name": "AnyHit1",
        \\          "module": "4444444444444444",
        \\          "stage": 512
        \\        }
        \\      ],
        \\      "groups": [
        \\        {
        \\          "anyHitShader": 4294967295,
        \\          "intersectionShader": 4294967295,
        \\          "generalShader": 0,
        \\          "closestHitShader": 4294967295,
        \\          "type": 0
        \\        },
        \\        {
        \\          "anyHitShader": 6,
        \\          "intersectionShader": 4294967295,
        \\          "generalShader": 4294967295,
        \\          "closestHitShader": 4294967295,
        \\          "type": 1
        \\        }
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    var gpa = std.heap.DebugAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const tmp_alloc = tmp_arena.allocator();

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
    try db.entries.getPtr(.SHADER_MODULE).put(alloc, 0x3333333333333333, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });
    try db.entries.getPtr(.SHADER_MODULE).put(alloc, 0x4444444444444444, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });

    const parsed_raytracing_pipeline = try parse_raytracing_pipeline(alloc, tmp_alloc, &db, json);
    vk_print.print_struct(parsed_raytracing_pipeline.create_info);
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

fn parse_number_array(
    comptime T: type,
    context: *const Context,
) ![]T {
    try scanner_array_begin(context.scanner);
    var tmp: std.ArrayListUnmanaged(T) = .empty;
    while (try scanner_array_next_number(context.scanner)) |v| {
        const number = try std.fmt.parseInt(T, v, 10);
        try tmp.append(context.tmp_alloc, number);
    }
    return try context.alloc.dupe(T, tmp.items);
}

fn parse_handle_array(
    comptime T: type,
    tag: Database.Entry.Tag,
    context: *const Context,
) ![]T {
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

fn parse_vk_physical_device_features2(
    context: *const Context,
    item: *vk.VkPhysicalDeviceFeatures2,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 };
    try parse_simple_type(context, item);
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

fn parse_vk_push_constant_range(
    context: *const Context,
    item: *vk.VkPushConstantRange,
) !void {
    try parse_simple_type(context, item);
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

fn parse_vk_subpass_dependency(
    context: *const Context,
    item: *vk.VkSubpassDependency,
) !void {
    try parse_simple_type(context, item);
}

fn parse_vk_attachment_description(
    context: *const Context,
    item: *vk.VkAttachmentDescription,
) !void {
    try parse_simple_type(context, item);
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

fn parse_vk_attachment_reference(
    context: *const Context,
    item: *vk.VkAttachmentReference,
) !void {
    try parse_simple_type(context, item);
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
        \\  "version": 6,
        \\  "graphicsPipelines": {
        \\    "ef491d980afbddf7": {
        \\      "flags": 0,
        \\      "basePipelineHandle": "0000000000000000",
        \\      "basePipelineIndex": -1,
        \\      "layout": "3dc5f23c21306af3",
        \\      "renderPass": "0000000000000000",
        \\      "subpass": 0,
        \\      "dynamicState": {
        \\        "flags": 0,
        \\        "dynamicState": [
        \\          0,
        \\          1
        \\        ]
        \\      },
        \\      "multisampleState": {
        \\        "flags": 0,
        \\        "rasterizationSamples": 1,
        \\        "sampleShadingEnable": 0,
        \\        "minSampleShading": 1,
        \\        "alphaToOneEnable": 0,
        \\        "alphaToCoverageEnable": 0
        \\      },
        \\      "vertexInputState": {
        \\        "flags": 0,
        \\        "attributes": [],
        \\        "bindings": []
        \\      },
        \\      "rasterizationState": {
        \\        "flags": 0,
        \\        "depthBiasConstantFactor": 0,
        \\        "depthBiasSlopeFactor": 0,
        \\        "depthBiasClamp": 0,
        \\        "depthBiasEnable": 0,
        \\        "depthClampEnable": 0,
        \\        "polygonMode": 0,
        \\        "rasterizerDiscardEnable": 0,
        \\        "frontFace": 1,
        \\        "lineWidth": 1,
        \\        "cullMode": 0
        \\      },
        \\      "inputAssemblyState": {
        \\        "flags": 0,
        \\        "topology": 3,
        \\        "primitiveRestartEnable": 0
        \\      },
        \\      "colorBlendState": {
        \\        "flags": 0,
        \\        "logicOp": 3,
        \\        "logicOpEnable": 0,
        \\        "blendConstants": [
        \\          0,
        \\          0,
        \\          0,
        \\          0
        \\        ],
        \\        "attachments": [
        \\          {
        \\            "dstAlphaBlendFactor": 0,
        \\            "srcAlphaBlendFactor": 1,
        \\            "dstColorBlendFactor": 7,
        \\            "srcColorBlendFactor": 6,
        \\            "colorWriteMask": 15,
        \\            "alphaBlendOp": 0,
        \\            "colorBlendOp": 0,
        \\            "blendEnable": 1
        \\          }
        \\        ]
        \\      },
        \\      "viewportState": {
        \\        "flags": 0,
        \\        "viewportCount": 1,
        \\        "scissorCount": 1
        \\      },
        \\      "depthStencilState": {
        \\        "flags": 0,
        \\        "stencilTestEnable": 0,
        \\        "maxDepthBounds": 1,
        \\        "minDepthBounds": 0,
        \\        "depthBoundsTestEnable": 0,
        \\        "depthWriteEnable": 1,
        \\        "depthTestEnable": 1,
        \\        "depthCompareOp": 6,
        \\        "front": {
        \\          "compareOp": 0,
        \\          "writeMask": 0,
        \\          "reference": 0,
        \\          "compareMask": 0,
        \\          "passOp": 0,
        \\          "failOp": 0,
        \\          "depthFailOp": 0
        \\        },
        \\        "back": {
        \\          "compareOp": 0,
        \\          "writeMask": 0,
        \\          "reference": 0,
        \\          "compareMask": 0,
        \\          "passOp": 0,
        \\          "failOp": 0,
        \\          "depthFailOp": 0
        \\        }
        \\      },
        \\      "stages": [
        \\        {
        \\          "flags": 0,
        \\          "name": "main",
        \\          "module": "959dfe0bd6073194",
        \\          "stage": 1
        \\        },
        \\        {
        \\          "flags": 0,
        \\          "name": "main",
        \\          "module": "0925def2d6ede3d9",
        \\          "stage": 16
        \\        }
        \\      ],
        \\      "pNext": [
        \\        {
        \\          "sType": 1000044002,
        \\          "depthAttachmentFormat": 126,
        \\          "stencilAttachmentFormat": 0,
        \\          "viewMask": 0,
        \\          "colorAttachmentFormats": [
        \\            44
        \\          ]
        \\        }
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    const json2 =
        \\{
        \\  "version": 6,
        \\  "graphicsPipelines": {
        \\    "b1aa504c3071b068": {
        \\      "flags": 0,
        \\      "basePipelineHandle": "0000000000000000",
        \\      "basePipelineIndex": -1,
        \\      "layout": "3dc5f23c21306af3",
        \\      "renderPass": "0000000000000000",
        \\      "subpass": 0,
        \\      "dynamicState": {
        \\        "flags": 0,
        \\        "dynamicState": [
        \\          1000267003,
        \\          1000267004,
        \\          3,
        \\          1000377002,
        \\          1000267000,
        \\          1000267001,
        \\          1000267005,
        \\          5,
        \\          1000267009,
        \\          1000267006,
        \\          1000267008,
        \\          1000267007,
        \\          1000267010,
        \\          1000267011,
        \\          6,
        \\          8,
        \\          7
        \\        ]
        \\      },
        \\      "multisampleState": {
        \\        "flags": 0,
        \\        "rasterizationSamples": 1,
        \\        "sampleShadingEnable": 0,
        \\        "minSampleShading": 0,
        \\        "alphaToOneEnable": 0,
        \\        "alphaToCoverageEnable": 0,
        \\        "sampleMask": [
        \\          1
        \\        ]
        \\      },
        \\      "vertexInputState": {
        \\        "flags": 0,
        \\        "attributes": [
        \\          {
        \\            "location": 0,
        \\            "binding": 0,
        \\            "offset": 0,
        \\            "format": 106
        \\          },
        \\          {
        \\            "location": 1,
        \\            "binding": 0,
        \\            "offset": 12,
        \\            "format": 103
        \\          }
        \\        ],
        \\        "bindings": [
        \\          {
        \\            "binding": 0,
        \\            "stride": 0,
        \\            "inputRate": 0
        \\          }
        \\        ]
        \\      },
        \\      "rasterizationState": {
        \\        "flags": 0,
        \\        "depthBiasConstantFactor": 0,
        \\        "depthBiasSlopeFactor": 0,
        \\        "depthBiasClamp": 0,
        \\        "depthBiasEnable": 0,
        \\        "depthClampEnable": 1,
        \\        "polygonMode": 0,
        \\        "rasterizerDiscardEnable": 0,
        \\        "frontFace": 0,
        \\        "lineWidth": 1,
        \\        "cullMode": 0,
        \\        "pNext": [
        \\          {
        \\            "sType": 1000102001,
        \\            "flags": 0,
        \\            "depthClipEnable": 1
        \\          }
        \\        ]
        \\      },
        \\      "inputAssemblyState": {
        \\        "flags": 0,
        \\        "topology": 3,
        \\        "primitiveRestartEnable": 0
        \\      },
        \\      "colorBlendState": {
        \\        "flags": 0,
        \\        "logicOp": 5,
        \\        "logicOpEnable": 0,
        \\        "blendConstants": [
        \\          0,
        \\          0,
        \\          0,
        \\          0
        \\        ],
        \\        "attachments": [
        \\          {
        \\            "dstAlphaBlendFactor": 0,
        \\            "srcAlphaBlendFactor": 0,
        \\            "dstColorBlendFactor": 0,
        \\            "srcColorBlendFactor": 0,
        \\            "colorWriteMask": 15,
        \\            "alphaBlendOp": 0,
        \\            "colorBlendOp": 0,
        \\            "blendEnable": 0
        \\          }
        \\        ]
        \\      },
        \\      "viewportState": {
        \\        "flags": 0,
        \\        "viewportCount": 0,
        \\        "scissorCount": 0
        \\      },
        \\      "depthStencilState": {
        \\        "flags": 0,
        \\        "stencilTestEnable": 0,
        \\        "maxDepthBounds": 0,
        \\        "minDepthBounds": 0,
        \\        "depthBoundsTestEnable": 0,
        \\        "depthWriteEnable": 0,
        \\        "depthTestEnable": 0,
        \\        "depthCompareOp": 0,
        \\        "front": {
        \\          "compareOp": 0,
        \\          "writeMask": 0,
        \\          "reference": 0,
        \\          "compareMask": 0,
        \\          "passOp": 0,
        \\          "failOp": 0,
        \\          "depthFailOp": 0
        \\        },
        \\        "back": {
        \\          "compareOp": 0,
        \\          "writeMask": 0,
        \\          "reference": 0,
        \\          "compareMask": 0,
        \\          "passOp": 0,
        \\          "failOp": 0,
        \\          "depthFailOp": 0
        \\        }
        \\      },
        \\      "stages": [
        \\        {
        \\          "flags": 0,
        \\          "name": "main",
        \\          "module": "959dfe0bd6073194",
        \\          "stage": 1,
        \\          "specializationInfo": {
        \\            "dataSize": 0,
        \\            "data": "",
        \\            "mapEntries": []
        \\          },
        \\          "pNext": []
        \\        },
        \\        {
        \\          "flags": 0,
        \\          "name": "main",
        \\          "module": "0925def2d6ede3d9",
        \\          "stage": 16,
        \\          "specializationInfo": {
        \\            "dataSize": 0,
        \\            "data": "",
        \\            "mapEntries": []
        \\          },
        \\          "pNext": []
        \\        }
        \\      ],
        \\      "pNext": [
        \\        {
        \\          "sType": 1000470005,
        \\          "flags": 536870912
        \\        },
        \\        {
        \\          "sType": 1000044002,
        \\          "depthAttachmentFormat": 130,
        \\          "stencilAttachmentFormat": 130,
        \\          "viewMask": 0,
        \\          "colorAttachmentFormats": [
        \\            44
        \\          ]
        \\        }
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    const json3 =
        \\{
        \\  "version": 6,
        \\  "graphicsPipelines": {
        \\    "f788d44a6e5f90b4": {
        \\      "flags": 0,
        \\      "basePipelineHandle": "0000000000000000",
        \\      "basePipelineIndex": -1,
        \\      "layout": "3dc5f23c21306af3",
        \\      "renderPass": "0000000000000000",
        \\      "subpass": 0,
        \\      "stages": [],
        \\      "pNext": [
        \\        {
        \\          "libraries": [
        \\            "e40eadc1c688bcd1",
        \\            "7e6f6e93e12a347a",
        \\            "783d1bfbdea0a5e5",
        \\            "d9a809bf95365f4e"
        \\          ],
        \\          "sType": 1000290000
        \\        },
        \\        {
        \\          "sType": 1000470005,
        \\          "flags": 536870912
        \\        }
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    const json4 =
        \\{
        \\  "version": 6,
        \\  "graphicsPipelines": {
        \\    "4c9ce69365646b90": {
        \\      "flags": 0,
        \\      "basePipelineHandle": "0000000000000000",
        \\      "basePipelineIndex": -1,
        \\      "layout": "3dc5f23c21306af3",
        \\      "renderPass": "3729eda857eaa8ec",
        \\      "subpass": 0,
        \\      "multisampleState": {
        \\        "flags": 0,
        \\        "rasterizationSamples": 1,
        \\        "sampleShadingEnable": 0,
        \\        "minSampleShading": 0,
        \\        "alphaToOneEnable": 0,
        \\        "alphaToCoverageEnable": 0
        \\      },
        \\      "vertexInputState": {
        \\        "flags": 0,
        \\        "attributes": [
        \\          {
        \\            "location": 0,
        \\            "binding": 0,
        \\            "offset": 0,
        \\            "format": 106
        \\          },
        \\          {
        \\            "location": 1,
        \\            "binding": 0,
        \\            "offset": 12,
        \\            "format": 103
        \\          },
        \\          {
        \\            "location": 2,
        \\            "binding": 0,
        \\            "offset": 20,
        \\            "format": 109
        \\          }
        \\        ],
        \\        "bindings": [
        \\          {
        \\            "binding": 0,
        \\            "stride": 36,
        \\            "inputRate": 0
        \\          }
        \\        ]
        \\      },
        \\      "rasterizationState": {
        \\        "flags": 0,
        \\        "depthBiasConstantFactor": 0,
        \\        "depthBiasSlopeFactor": 0,
        \\        "depthBiasClamp": 0,
        \\        "depthBiasEnable": 0,
        \\        "depthClampEnable": 0,
        \\        "polygonMode": 0,
        \\        "rasterizerDiscardEnable": 0,
        \\        "frontFace": 0,
        \\        "lineWidth": 1,
        \\        "cullMode": 0
        \\      },
        \\      "inputAssemblyState": {
        \\        "flags": 0,
        \\        "topology": 3,
        \\        "primitiveRestartEnable": 0
        \\      },
        \\      "colorBlendState": {
        \\        "flags": 0,
        \\        "logicOp": 0,
        \\        "logicOpEnable": 0,
        \\        "blendConstants": [
        \\          0,
        \\          0,
        \\          0,
        \\          0
        \\        ],
        \\        "attachments": [
        \\          {
        \\            "dstAlphaBlendFactor": 1,
        \\            "srcAlphaBlendFactor": 1,
        \\            "dstColorBlendFactor": 7,
        \\            "srcColorBlendFactor": 6,
        \\            "colorWriteMask": 15,
        \\            "alphaBlendOp": 0,
        \\            "colorBlendOp": 0,
        \\            "blendEnable": 1
        \\          }
        \\        ]
        \\      },
        \\      "viewportState": {
        \\        "flags": 0,
        \\        "viewportCount": 1,
        \\        "scissorCount": 1,
        \\        "viewports": [
        \\          {
        \\            "x": 0,
        \\            "y": 0,
        \\            "width": 1834,
        \\            "height": 786,
        \\            "minDepth": 0,
        \\            "maxDepth": 1
        \\          }
        \\        ],
        \\        "scissors": [
        \\          {
        \\            "x": 0,
        \\            "y": 0,
        \\            "width": 1834,
        \\            "height": 786
        \\          }
        \\        ]
        \\      },
        \\      "stages": [
        \\        {
        \\          "flags": 0,
        \\          "name": "main",
        \\          "module": "959dfe0bd6073194",
        \\          "stage": 1
        \\        },
        \\        {
        \\          "flags": 0,
        \\          "name": "main",
        \\          "module": "0925def2d6ede3d9",
        \\          "stage": 16
        \\        }
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    const json5 =
        \\{
        \\  "version": 6,
        \\  "graphicsPipelines": {
        \\    "f79b7f77abaeb668": {
        \\      "flags": 0,
        \\      "basePipelineHandle": "0000000000000000",
        \\      "basePipelineIndex": -1,
        \\      "layout": "3dc5f23c21306af3",
        \\      "renderPass": "0000000000000000",
        \\      "subpass": 0,
        \\      "dynamicState": {
        \\        "flags": 0,
        \\        "dynamicState": [
        \\          1000267003,
        \\          1000267004,
        \\          3,
        \\          1000377002,
        \\          1000267000,
        \\          1000267001,
        \\          1000267005,
        \\          5,
        \\          1000267009,
        \\          1000267006,
        \\          1000267008,
        \\          1000267007
        \\        ]
        \\      },
        \\      "multisampleState": {
        \\        "flags": 0,
        \\        "rasterizationSamples": 1,
        \\        "sampleShadingEnable": 0,
        \\        "minSampleShading": 0,
        \\        "alphaToOneEnable": 0,
        \\        "alphaToCoverageEnable": 0,
        \\        "sampleMask": [
        \\          1
        \\        ]
        \\      },
        \\      "vertexInputState": {
        \\        "flags": 0,
        \\        "attributes": [
        \\          {
        \\            "location": 0,
        \\            "binding": 0,
        \\            "offset": 0,
        \\            "format": 106
        \\          },
        \\          {
        \\            "location": 1,
        \\            "binding": 1,
        \\            "offset": 0,
        \\            "format": 78
        \\          },
        \\          {
        \\            "location": 2,
        \\            "binding": 1,
        \\            "offset": 4,
        \\            "format": 78
        \\          },
        \\          {
        \\            "location": 3,
        \\            "binding": 1,
        \\            "offset": 8,
        \\            "format": 98
        \\          },
        \\          {
        \\            "location": 4,
        \\            "binding": 1,
        \\            "offset": 12,
        \\            "format": 37
        \\          },
        \\          {
        \\            "location": 7,
        \\            "binding": 2,
        \\            "offset": 0,
        \\            "format": 98
        \\          },
        \\          {
        \\            "location": 5,
        \\            "binding": 3,
        \\            "offset": 0,
        \\            "format": 109
        \\          },
        \\          {
        \\            "location": 6,
        \\            "binding": 3,
        \\            "offset": 16,
        \\            "format": 107
        \\          }
        \\        ],
        \\        "bindings": [
        \\          {
        \\            "binding": 0,
        \\            "stride": 0,
        \\            "inputRate": 0
        \\          },
        \\          {
        \\            "binding": 1,
        \\            "stride": 0,
        \\            "inputRate": 0
        \\          },
        \\          {
        \\            "binding": 2,
        \\            "stride": 0,
        \\            "inputRate": 1
        \\          },
        \\          {
        \\            "binding": 3,
        \\            "stride": 0,
        \\            "inputRate": 1
        \\          }
        \\        ],
        \\        "pNext": [
        \\          {
        \\            "sType": 1000190001,
        \\            "vertexBindingDivisorCount": 1,
        \\            "vertexBindingDivisors": [
        \\              {
        \\                "binding": 3,
        \\                "divisor": 0
        \\              }
        \\            ]
        \\          }
        \\        ]
        \\      },
        \\      "rasterizationState": {
        \\        "flags": 0,
        \\        "depthBiasConstantFactor": 0,
        \\        "depthBiasSlopeFactor": 0,
        \\        "depthBiasClamp": 0,
        \\        "depthBiasEnable": 0,
        \\        "depthClampEnable": 1,
        \\        "polygonMode": 0,
        \\        "rasterizerDiscardEnable": 0,
        \\        "frontFace": 0,
        \\        "lineWidth": 1,
        \\        "cullMode": 0,
        \\        "pNext": [
        \\          {
        \\            "sType": 1000102001,
        \\            "flags": 0,
        \\            "depthClipEnable": 1
        \\          }
        \\        ]
        \\      },
        \\      "inputAssemblyState": {
        \\        "flags": 0,
        \\        "topology": 3,
        \\        "primitiveRestartEnable": 0
        \\      },
        \\      "colorBlendState": {
        \\        "flags": 0,
        \\        "logicOp": 5,
        \\        "logicOpEnable": 0,
        \\        "blendConstants": [
        \\          0,
        \\          0,
        \\          0,
        \\          0
        \\        ],
        \\        "attachments": [
        \\          {
        \\            "dstAlphaBlendFactor": 0,
        \\            "srcAlphaBlendFactor": 0,
        \\            "dstColorBlendFactor": 0,
        \\            "srcColorBlendFactor": 0,
        \\            "colorWriteMask": 15,
        \\            "alphaBlendOp": 0,
        \\            "colorBlendOp": 0,
        \\            "blendEnable": 0
        \\          },
        \\          {
        \\            "dstAlphaBlendFactor": 0,
        \\            "srcAlphaBlendFactor": 0,
        \\            "dstColorBlendFactor": 0,
        \\            "srcColorBlendFactor": 0,
        \\            "colorWriteMask": 15,
        \\            "alphaBlendOp": 0,
        \\            "colorBlendOp": 0,
        \\            "blendEnable": 0
        \\          },
        \\          {
        \\            "dstAlphaBlendFactor": 0,
        \\            "srcAlphaBlendFactor": 0,
        \\            "dstColorBlendFactor": 0,
        \\            "srcColorBlendFactor": 0,
        \\            "colorWriteMask": 15,
        \\            "alphaBlendOp": 0,
        \\            "colorBlendOp": 0,
        \\            "blendEnable": 0
        \\          },
        \\          {
        \\            "dstAlphaBlendFactor": 0,
        \\            "srcAlphaBlendFactor": 0,
        \\            "dstColorBlendFactor": 0,
        \\            "srcColorBlendFactor": 0,
        \\            "colorWriteMask": 15,
        \\            "alphaBlendOp": 0,
        \\            "colorBlendOp": 0,
        \\            "blendEnable": 0
        \\          }
        \\        ]
        \\      },
        \\      "viewportState": {
        \\        "flags": 0,
        \\        "viewportCount": 0,
        \\        "scissorCount": 0
        \\      },
        \\      "depthStencilState": {
        \\        "flags": 0,
        \\        "stencilTestEnable": 0,
        \\        "maxDepthBounds": 0,
        \\        "minDepthBounds": 0,
        \\        "depthBoundsTestEnable": 0,
        \\        "depthWriteEnable": 0,
        \\        "depthTestEnable": 0,
        \\        "depthCompareOp": 0,
        \\        "front": {
        \\          "compareOp": 0,
        \\          "writeMask": 0,
        \\          "reference": 0,
        \\          "compareMask": 0,
        \\          "passOp": 0,
        \\          "failOp": 0,
        \\          "depthFailOp": 0
        \\        },
        \\        "back": {
        \\          "compareOp": 0,
        \\          "writeMask": 0,
        \\          "reference": 0,
        \\          "compareMask": 0,
        \\          "passOp": 0,
        \\          "failOp": 0,
        \\          "depthFailOp": 0
        \\        }
        \\      },
        \\      "stages": [
        \\        {
        \\          "flags": 0,
        \\          "name": "main",
        \\          "module": "0925def2d6ede3d9",
        \\          "stage": 1,
        \\          "specializationInfo": {
        \\            "dataSize": 0,
        \\            "data": "",
        \\            "mapEntries": []
        \\          },
        \\          "pNext": []
        \\        },
        \\        {
        \\          "flags": 0,
        \\          "name": "main",
        \\          "module": "959dfe0bd6073194",
        \\          "stage": 16,
        \\          "specializationInfo": {
        \\            "dataSize": 0,
        \\            "data": "",
        \\            "mapEntries": []
        \\          },
        \\          "pNext": []
        \\        }
        \\      ],
        \\      "pNext": [
        \\        {
        \\          "sType": 1000470005,
        \\          "flags": 0
        \\        },
        \\        {
        \\          "sType": 1000044002,
        \\          "depthAttachmentFormat": 126,
        \\          "stencilAttachmentFormat": 0,
        \\          "viewMask": 0,
        \\          "colorAttachmentFormats": [
        \\            64,
        \\            43,
        \\            37,
        \\            97
        \\          ]
        \\        }
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    var gpa = std.heap.DebugAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const alloc = arena.allocator();
    var tmp_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const tmp_alloc = tmp_arena.allocator();

    var db: Database = .{
        .file_mem = &.{},
        .entries = .initFill(.empty),
        .arena = arena,
    };
    try db.entries.getPtr(.PIPELINE_LAYOUT).put(alloc, 0x3dc5f23c21306af3, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });
    try db.entries.getPtr(.SHADER_MODULE).put(alloc, 0x959dfe0bd6073194, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });
    try db.entries.getPtr(.SHADER_MODULE).put(alloc, 0x0925def2d6ede3d9, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });
    try db.entries.getPtr(.RENDER_PASS).put(alloc, 0x3729eda857eaa8ec, .{
        .entry_ptr = undefined,
        .payload = undefined,
        .handle = @ptrFromInt(0x69),
    });
    for ([_]u64{
        0xe40eadc1c688bcd1,
        0x7e6f6e93e12a347a,
        0x783d1bfbdea0a5e5,
        0xd9a809bf95365f4e,
    }) |p| {
        try db.entries.getPtr(.GRAPHICS_PIPELINE).put(alloc, p, .{
            .entry_ptr = undefined,
            .payload = undefined,
            .handle = @ptrFromInt(0x69),
        });
    }

    _ = try parse_graphics_pipeline(alloc, tmp_alloc, &db, json);
    _ = try parse_graphics_pipeline(alloc, tmp_alloc, &db, json2);
    _ = try parse_graphics_pipeline(alloc, tmp_alloc, &db, json3);
    _ = try parse_graphics_pipeline(alloc, tmp_alloc, &db, json4);
    const parsed_graphics_pipeline = try parse_graphics_pipeline(alloc, tmp_alloc, &db, json5);
    vk_print.print_struct(parsed_graphics_pipeline.create_info);
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
                try parse_vk_pipeline_vertex_input_state_create_info(context);
            item.pVertexInputState = vertex_input_state;
        } else if (std.mem.eql(u8, s, "inputAssemblyState")) {
            const input_assembly_state =
                try parse_vk_pipeline_input_assembly_state_create_info(context);
            item.pInputAssemblyState = input_assembly_state;
        } else if (std.mem.eql(u8, s, "tessellationState")) {
            const tesselation_state =
                try parse_vk_pipeline_tessellation_state_create_info(context);
            item.pTessellationState = tesselation_state;
        } else if (std.mem.eql(u8, s, "viewportState")) {
            const viewport_state =
                try parse_vk_pipeline_viewport_state_create_info(context);
            item.pViewportState = viewport_state;
        } else if (std.mem.eql(u8, s, "rasterizationState")) {
            const raseterization_state =
                try parse_vk_pipeline_rasterization_state_create_info(context);
            item.pRasterizationState = raseterization_state;
        } else if (std.mem.eql(u8, s, "multisampleState")) {
            const multisample_state =
                try parse_vk_pipeline_multisample_state_create_info(context);
            item.pMultisampleState = multisample_state;
        } else if (std.mem.eql(u8, s, "depthStencilState")) {
            const depth_stencil_state =
                try parse_vk_pipeline_depth_stencil_state_create_info(context);
            item.pDepthStencilState = depth_stencil_state;
        } else if (std.mem.eql(u8, s, "colorBlendState")) {
            const color_blend_state =
                try parse_vk_pipeline_color_blend_state_create_info(context);
            item.pColorBlendState = color_blend_state;
        } else if (std.mem.eql(u8, s, "dynamicState")) {
            const dynamic_state =
                try parse_vk_pipeline_dynamic_state_create_info(context);
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

fn parse_vk_pipeline_vertex_input_state_create_info(
    context: *const Context,
) !*const vk.VkPipelineVertexInputStateCreateInfo {
    const item = try context.alloc.create(vk.VkPipelineVertexInputStateCreateInfo);
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
    return item;
}

fn parse_vk_pipeline_input_assembly_state_create_info(
    context: *const Context,
) !*const vk.VkPipelineInputAssemblyStateCreateInfo {
    const item = try context.alloc.create(vk.VkPipelineInputAssemblyStateCreateInfo);
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO };
    try parse_simple_type(context, item);
    return item;
}

fn parse_vk_pipeline_tessellation_state_create_info(
    context: *const Context,
) !*const vk.VkPipelineTessellationStateCreateInfo {
    const item = try context.alloc.create(vk.VkPipelineTessellationStateCreateInfo);
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO };
    try parse_simple_type(context, item);
    return item;
}

fn parse_vk_pipeline_viewport_state_create_info(
    context: *const Context,
) !*const vk.VkPipelineViewportStateCreateInfo {
    const item = try context.alloc.create(vk.VkPipelineViewportStateCreateInfo);
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
    return item;
}

fn parse_vk_pipeline_rasterization_state_create_info(
    context: *const Context,
) !*const vk.VkPipelineRasterizationStateCreateInfo {
    const item = try context.alloc.create(vk.VkPipelineRasterizationStateCreateInfo);
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO };
    try parse_simple_type(context, item);
    return item;
}

fn parse_vk_pipeline_multisample_state_create_info(
    context: *const Context,
) !*const vk.VkPipelineMultisampleStateCreateInfo {
    const item = try context.alloc.create(vk.VkPipelineMultisampleStateCreateInfo);
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
    return item;
}

fn parse_vk_pipeline_depth_stencil_state_create_info(
    context: *const Context,
) !*const vk.VkPipelineDepthStencilStateCreateInfo {
    const item = try context.alloc.create(vk.VkPipelineDepthStencilStateCreateInfo);
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
            try parse_simple_type(context, &item.front);
        } else if (std.mem.eql(u8, s, "back")) {
            try parse_simple_type(context, &item.back);
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
    return item;
}

fn parse_vk_pipeline_color_blend_state_create_info(
    context: *const Context,
) !*const vk.VkPipelineColorBlendStateCreateInfo {
    const item = try context.alloc.create(vk.VkPipelineColorBlendStateCreateInfo);
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
    return item;
}

fn parse_vk_pipeline_dynamic_state_create_info(
    context: *const Context,
) !*const vk.VkPipelineDynamicStateCreateInfo {
    const item = try context.alloc.create(vk.VkPipelineDynamicStateCreateInfo);
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
    return item;
}

fn parse_vk_vertex_input_attribute_description(
    context: *const Context,
    item: *vk.VkVertexInputAttributeDescription,
) !void {
    try parse_simple_type(context, item);
}

fn parse_vk_vertex_input_binding_description(
    context: *const Context,
    item: *vk.VkVertexInputBindingDescription,
) !void {
    try parse_simple_type(context, item);
}

fn parse_vk_pipeline_color_blend_attachment_state(
    context: *const Context,
    item: *vk.VkPipelineColorBlendAttachmentState,
) !void {
    try parse_simple_type(context, item);
}

fn parse_vk_viewport(
    context: *const Context,
    item: *vk.VkViewport,
) !void {
    try parse_simple_type(context, item);
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

fn parse_vk_specialization_map_entry(
    context: *const Context,
    item: *vk.VkSpecializationMapEntry,
) !void {
    try parse_simple_type(context, item);
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
            const library = try parse_vk_pipeline_library_create_info(context);
            item.pLibraryInfo = library;
        } else if (std.mem.eql(u8, s, "libraryInterface")) {
            const interface = try parse_vk_ray_tracing_pipeline_interface_create_info(
                context,
            );
            item.pLibraryInterface = interface;
        } else if (std.mem.eql(u8, s, "maxPipelineRayRecursionDepth")) {
            const v = try scanner_next_number(context.scanner);
            item.maxPipelineRayRecursionDepth = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "dynamicState")) {
            const dynamic_state =
                try parse_vk_pipeline_dynamic_state_create_info(context);
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

fn parse_vk_ray_tracing_shader_group_create_info(
    context: *const Context,
    item: *vk.VkRayTracingShaderGroupCreateInfoKHR,
) !void {
    item.* = .{ .sType = vk.VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR };
    try parse_simple_type(context, item);
}

fn parse_vk_pipeline_library_create_info(
    context: *const Context,
) !*const vk.VkPipelineLibraryCreateInfoKHR {
    const item = try context.alloc.create(vk.VkPipelineLibraryCreateInfoKHR);
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
    return item;
}

fn parse_vk_ray_tracing_pipeline_interface_create_info(
    context: *const Context,
) !*const vk.VkRayTracingPipelineInterfaceCreateInfoKHR {
    const item = try context.alloc.create(vk.VkRayTracingPipelineInterfaceCreateInfoKHR);
    item.* = .{
        .sType = vk.VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_INTERFACE_CREATE_INFO_KHR,
    };
    try parse_simple_type(context, item);
    return item;
}
