const std = @import("std");
const vk = @import("volk.zig");
const log = @import("log.zig");
const root = @import("main.zig");

const Allocator = std.mem.Allocator;
const Database = root.Database;

pub fn print_vk_struct(@"struct": anytype) void {
    const t = @typeInfo(@TypeOf(@"struct")).pointer.child;
    const fields = @typeInfo(t).@"struct".fields;
    log.info(@src(), "Type: {s}", .{@typeName(t)});
    inline for (fields) |field| {
        switch (field.type) {
            u32, u64, vk.VkStructureType => {
                log.info(@src(), "\t{s}: {d}", .{ field.name, @field(@"struct", field.name) });
            },
            f32, f64 => {
                log.info(@src(), "\t{s}: {d}", .{ field.name, @field(@"struct", field.name) });
            },
            [*c]const u8 => {
                log.info(@src(), "\t{s}: {s}", .{ field.name, @field(@"struct", field.name) });
            },
            [*c]const u32 => {
                if (@hasField(t, "codeSize")) {
                    const len = @field(@"struct", "codeSize");
                    var code: []const u32 = undefined;
                    code.ptr = @field(@"struct", field.name);
                    code.len = len / @sizeOf(u32);
                    log.info(@src(), "\t{s}: {any}", .{ field.name, code });
                }
            },
            ?*anyopaque, ?*const anyopaque => {
                log.info(@src(), "\t{s}: {?}", .{ field.name, @field(@"struct", field.name) });
            },
            [*c]const vk.VkDescriptorSetLayoutBinding => {
                const len = @field(@"struct", "bindingCount");
                var elements: []const vk.VkDescriptorSetLayoutBinding = undefined;
                elements.ptr = @field(@"struct", field.name);
                elements.len = len;
                for (elements) |*binding|
                    print_vk_struct(binding);
            },
            [*c]const vk.VkDescriptorSetLayout => {
                const len = @field(@"struct", "setLayoutCount");
                var elements: []const *anyopaque = undefined;
                elements.ptr = @ptrCast(@field(@"struct", field.name));
                elements.len = len;
                log.info(@src(), "\t{s}: {any}", .{ field.name, elements });
            },
            [*c]const vk.VkPushConstantRange => {
                const len = @field(@"struct", "pushConstantRangeCount");
                var elements: []const vk.VkPushConstantRange = undefined;
                elements.ptr = @field(@"struct", field.name);
                elements.len = len;
                for (elements) |*binding|
                    print_vk_struct(binding);
            },
            [*c]const vk.VkAttachmentDescription => {
                const len = @field(@"struct", "attachmentCount");
                var elements: []const vk.VkAttachmentDescription = undefined;
                elements.ptr = @field(@"struct", field.name);
                elements.len = len;
                for (elements) |*binding|
                    print_vk_struct(binding);
            },
            [*c]const vk.VkSubpassDescription => {
                const len = @field(@"struct", "subpassCount");
                var elements: []const vk.VkSubpassDescription = undefined;
                elements.ptr = @field(@"struct", field.name);
                elements.len = len;
                for (elements) |*binding|
                    print_vk_struct(binding);
            },
            [*c]const vk.VkAttachmentReference => {
                const len = if (std.mem.eql(u8, field.name, "pInputAttachments"))
                    @field(@"struct", "inputAttachmentCount")
                else if (std.mem.eql(u8, field.name, "pColorAttachments"))
                    @field(@"struct", "colorAttachmentCount")
                else if (std.mem.eql(u8, field.name, "pResolveAttachments")) blk: {
                    if (@field(@"struct", field.name) != null)
                        break :blk @field(@"struct", "colorAttachmentCount")
                    else
                        break :blk 0;
                } else if (std.mem.eql(u8, field.name, "pDepthStencilAttachment"))
                    @intFromBool(@field(@"struct", field.name) != null)
                else if (std.mem.eql(u8, field.name, "pPreserveAttachments"))
                    @field(@"struct", "preserveAttachmentCount")
                else
                    @panic("Cannot find length for the VkAttachmentReference array");

                log.info(@src(), "{s} {d}", .{ field.name, len });
                if (len != 0) {
                    var elements: []const vk.VkAttachmentReference = undefined;
                    elements.ptr = @field(@"struct", field.name);
                    elements.len = len;
                    for (elements) |*binding|
                        print_vk_struct(binding);
                }
            },
            [*c]const vk.VkSubpassDependency => {
                const len = @field(@"struct", "dependencyCount");
                var elements: []const vk.VkSubpassDependency = undefined;
                elements.ptr = @field(@"struct", field.name);
                elements.len = len;
                for (elements) |*binding|
                    print_vk_struct(binding);
            },
            else => log.info(
                @src(),
                "\tCannot format field {s} of type {s}",
                .{ field.name, @typeName(field.type) },
            ),
        }
    }
}

pub fn print_vk_chain(chain: anytype) void {
    var current: ?*const anyopaque = chain;
    while (current) |c| {
        const struct_type: *const vk.VkStructureType = @alignCast(@ptrCast(c));
        switch (struct_type.*) {
            vk.VK_STRUCTURE_TYPE_APPLICATION_INFO => {
                const nn: *const vk.VkApplicationInfo = @alignCast(@ptrCast(c));
                print_vk_struct(nn);
                current = nn.pNext;
            },
            vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO => {
                const nn: *const vk.VkDescriptorSetLayoutCreateInfo = @alignCast(@ptrCast(c));
                print_vk_struct(nn);
                current = nn.pNext;
            },
            vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO => {
                const nn: *const vk.VkPipelineLayoutCreateInfo = @alignCast(@ptrCast(c));
                print_vk_struct(nn);
                current = nn.pNext;
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 => {
                const nn: *const vk.VkPhysicalDeviceFeatures2 = @alignCast(@ptrCast(c));
                print_vk_struct(nn);
                current = nn.pNext;
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT => {
                const nn: *const vk.VkPhysicalDeviceMeshShaderFeaturesEXT =
                    @alignCast(@ptrCast(c));
                print_vk_struct(nn);
                current = nn.pNext;
            },
            vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR => {
                const nn: *const vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR =
                    @alignCast(@ptrCast(c));
                print_vk_struct(nn);
                current = nn.pNext;
            },
            vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO_EXT => {
                const nn: *const vk.VkDescriptorSetLayoutBindingFlagsCreateInfoEXT =
                    @alignCast(@ptrCast(c));
                print_vk_struct(nn);
                current = nn.pNext;
            },
            else => {
                log.info(@src(), "unknown struct type: {d}", .{struct_type.*});
                break;
            },
        }
    }
}

fn scanner_next_number(scanner: *std.json.Scanner) ![]const u8 {
    switch (try scanner.next()) {
        .number => |v| return v,
        else => return error.InvalidJson,
    }
}

fn scanner_next_string(scanner: *std.json.Scanner) ![]const u8 {
    switch (try scanner.next()) {
        .string => |s| return s,
        else => return error.InvalidJson,
    }
}

fn scanner_object_next_field(scanner: *std.json.Scanner) !?[]const u8 {
    loop: switch (try scanner.next()) {
        .string => |s| return s,
        .object_begin => continue :loop try scanner.next(),
        .end_of_document, .object_end => return null,
        else => return error.InvalidJson,
    }
}

fn scanner_array_next(scanner: *std.json.Scanner) !bool {
    loop: switch (try scanner.next()) {
        .array_begin => continue :loop try scanner.next(),
        .array_end => return false,
        .object_begin => return true,
        else => return error.InvalidJson,
    }
}

pub const NameMap = struct { json_name: []const u8, field_name: []const u8, type: type };
pub fn parse_type(
    comptime name_map: []const NameMap,
    alloc: ?Allocator,
    scanner: *std.json.Scanner,
    output: anytype,
) !void {
    var field_is_parsed: [name_map.len]bool = .{false} ** name_map.len;
    while (try scanner_object_next_field(scanner)) |s| {
        inline for (name_map, 0..) |nm, i| {
            if (!field_is_parsed[i] and std.mem.eql(u8, s, nm.json_name)) {
                field_is_parsed[i] = true;
                switch (nm.type) {
                    u8, u32 => {
                        const v = try scanner_next_number(scanner);
                        @field(output, nm.field_name) = try std.fmt.parseInt(nm.type, v, 10);
                    },
                    f32 => {
                        const v = try scanner_next_number(scanner);
                        @field(output, nm.field_name) = try std.fmt.parseFloat(nm.type, v);
                    },
                    []const u8 => {
                        const name = try scanner_next_string(scanner);
                        if (alloc) |aa| {
                            const n = try aa.dupeZ(u8, name);
                            @field(output, nm.field_name) = @ptrCast(n.ptr);
                        } else {
                            log.panic(
                                @src(),
                                "Trying to parse field with type string, but there is no allocator provided to copy the string",
                                .{},
                            );
                        }
                    },
                    else => log.comptime_err(
                        @src(),
                        "Cannot parse field with type: {any}",
                        .{nm[2]},
                    ),
                }
            }
        }
    }
}

fn parse_object_array(
    comptime T: type,
    comptime TAG: Database.Entry.Tag,
    aa: Allocator,
    sa: Allocator,
    scanner: *std.json.Scanner,
    db: *const Database,
) ![]T {
    if (try scanner.next() != .array_begin) return error.InvalidJson;
    var tmp: std.ArrayListUnmanaged(T) = .empty;
    while (true) {
        switch (try scanner.next()) {
            .string => |hash_str| {
                const hash = try std.fmt.parseInt(u64, hash_str, 16);
                const entries = db.entries.getPtrConst(TAG);
                const entry = entries.getPtr(hash).?;
                try tmp.append(sa, @ptrCast(entry.object));
            },
            .array_end => break,
            else => return error.InvalidJson,
        }
    }
    return try aa.dupe(T, tmp.items);
}

pub fn parse_physical_device_mesh_shader_features_ext(
    scanner: *std.json.Scanner,
    obj: *vk.VkPhysicalDeviceMeshShaderFeaturesEXT,
) !void {
    return parse_type(
        &.{
            .{
                .json_name = "taskShader",
                .field_name = "taskShader",
                .type = u8,
            },
            .{
                .json_name = "meshShader",
                .field_name = "meshShader",
                .type = u8,
            },
            .{
                .json_name = "multiviewMeshShader",
                .field_name = "multiviewMeshShader",
                .type = u8,
            },
            .{
                .json_name = "primitiveFragmentShadingRateMeshShader",
                .field_name = "primitiveFragmentShadingRateMeshShader",
                .type = u8,
            },
            .{
                .json_name = "meshShaderQueries",
                .field_name = "meshShaderQueries",
                .type = u8,
            },
        },
        null,
        scanner,
        obj,
    );
}

pub fn parse_physical_device_fragment_shading_rate_features_khr(
    scanner: *std.json.Scanner,
    obj: *vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR,
) !void {
    return parse_type(
        &.{
            .{
                .json_name = "pipelineFragmentShadingRate",
                .field_name = "pipelineFragmentShadingRate",
                .type = u8,
            },
            .{
                .json_name = "primitiveFragmentShadingRate",
                .field_name = "primitiveFragmentShadingRate",
                .type = u8,
            },
            .{
                .json_name = "attachmentFragmentShadingRate",
                .field_name = "attachmentFragmentShadingRate",
                .type = u8,
            },
        },
        null,
        scanner,
        obj,
    );
}

pub fn parse_descriptor_set_layout_binding_flags_create_info_ext(
    alloc: Allocator,
    tmp_alloc: Allocator,
    scanner: *std.json.Scanner,
    obj: *vk.VkDescriptorSetLayoutBindingFlagsCreateInfoEXT,
) !void {
    const Inner = struct {
        fn parse_flags(
            al: Allocator,
            tal: Allocator,
            s: *std.json.Scanner,
        ) ![]vk.VkDescriptorBindingFlags {
            if (try s.next() != .array_begin) return error.InvalidJson;
            switch (try s.peekNextTokenType()) {
                .array_end => return &.{},
                .number => {},
                else => return error.InvalidJson,
            }
            var tmp_flags: std.ArrayListUnmanaged(vk.VkDescriptorBindingFlags) = .empty;
            while (true) {
                switch (try s.next()) {
                    .number => |n| {
                        const flag = try std.fmt.parseInt(u32, n, 10);
                        try tmp_flags.append(tal, flag);
                    },
                    .array_end => break,
                    else => return error.InvalidJson,
                }
            }
            return al.dupe(vk.VkDescriptorBindingFlags, tmp_flags.items);
        }
    };
    while (try scanner_object_next_field(scanner)) |s| {
        if (std.mem.eql(u8, s, "bindingFlags")) {
            const flags = try Inner.parse_flags(alloc, tmp_alloc, scanner);
            obj.pBindingFlags = @ptrCast(flags.ptr);
            obj.bindingCount = @intCast(flags.len);
        } else {
            return error.InvalidJson;
        }
    }
}

pub fn parse_pnext_chain(
    alloc: Allocator,
    tmp_alloc: Allocator,
    scanner: *std.json.Scanner,
) !?*anyopaque {
    const Inner = struct {
        fn parse_next(
            aa: Allocator,
            sa: Allocator,
            s: *std.json.Scanner,
            first_in_chain: *?*anyopaque,
            last_pnext_in_chain: *?**anyopaque,
        ) !void {
            const v = try scanner_next_number(s);
            const stype = try std.fmt.parseInt(u32, v, 10);
            switch (stype) {
                vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT => {
                    const obj = try aa.create(vk.VkPhysicalDeviceMeshShaderFeaturesEXT);
                    obj.* = .{ .sType = stype };
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_physical_device_mesh_shader_features_ext(s, obj);
                },
                vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADING_RATE_FEATURES_KHR => {
                    const obj = try aa.create(vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR);
                    obj.* = .{ .sType = stype };
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_physical_device_fragment_shading_rate_features_khr(s, obj);
                },
                vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO_EXT => {
                    const obj = try aa.create(vk.VkDescriptorSetLayoutBindingFlagsCreateInfoEXT);
                    obj.* = .{ .sType = stype };
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_descriptor_set_layout_binding_flags_create_info_ext(
                        aa,
                        sa,
                        s,
                        obj,
                    );
                },
                else => return error.InvalidJson,
            }
        }
    };

    var first_in_chain: ?*anyopaque = null;
    var last_pnext_in_chain: ?**anyopaque = null;
    while (try scanner_array_next(scanner)) {
        const s = try scanner_object_next_field(scanner) orelse return error.InvalidJson;
        if (std.mem.eql(u8, s, "sType")) {
            try Inner.parse_next(
                alloc,
                tmp_alloc,
                scanner,
                &first_in_chain,
                &last_pnext_in_chain,
            );
        } else return error.InvalidJson;
    }
    return first_in_chain;
}

pub const ParsedApplicationInfo = struct {
    version: u32,
    application_info: *const vk.VkApplicationInfo,
    device_features2: *const vk.VkPhysicalDeviceFeatures2,
};
pub fn parse_application_info(
    alloc: Allocator,
    tmp_alloc: Allocator,
    json_str: []const u8,
) !ParsedApplicationInfo {
    const Inner = struct {
        fn parse_app_info(
            aa: Allocator,
            scanner: *std.json.Scanner,
            vk_application_info: *vk.VkApplicationInfo,
        ) !void {
            return parse_type(
                &.{
                    .{
                        .json_name = "applicationName",
                        .field_name = "pApplicationName",
                        .type = []const u8,
                    },
                    .{
                        .json_name = "engineName",
                        .field_name = "pEngineName",
                        .type = []const u8,
                    },
                    .{
                        .json_name = "applicationVersion",
                        .field_name = "applicationVersion",
                        .type = u32,
                    },
                    .{
                        .json_name = "engineVersion",
                        .field_name = "engineVersion",
                        .type = u32,
                    },
                    .{
                        .json_name = "apiVersion",
                        .field_name = "apiVersion",
                        .type = u32,
                    },
                },
                aa,
                scanner,
                vk_application_info,
            );
        }
        fn parse_device_features(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            vk_physical_device_features2: *vk.VkPhysicalDeviceFeatures2,
        ) !void {
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "robustBufferAccess")) {
                    switch (try scanner.next()) {
                        .number => |v| {
                            vk_physical_device_features2.features.robustBufferAccess =
                                try std.fmt.parseInt(u32, v, 10);
                        },
                        else => return error.InvalidJson,
                    }
                } else if (std.mem.eql(u8, s, "pNext")) {
                    vk_physical_device_features2.pNext = try parse_pnext_chain(
                        aa,
                        sa,
                        scanner,
                    );
                } else {
                    return error.InvalidJson;
                }
            }
        }
    };

    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_application_info = try alloc.create(vk.VkApplicationInfo);
    vk_application_info.* = .{ .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO };
    const vk_physical_device_features2 = try alloc.create(vk.VkPhysicalDeviceFeatures2);
    vk_physical_device_features2.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 };

    var result: ParsedApplicationInfo = .{
        .version = 0,
        .application_info = vk_application_info,
        .device_features2 = vk_physical_device_features2,
    };

    while (try scanner_object_next_field(&scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(&scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "applicationInfo")) {
            try Inner.parse_app_info(alloc, &scanner, vk_application_info);
        } else if (std.mem.eql(u8, s, "physicalDeviceFeatures")) {
            try Inner.parse_device_features(
                alloc,
                tmp_alloc,
                &scanner,
                vk_physical_device_features2,
            );
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

    const parsed_application_info = try parse_application_info(alloc, tmp_alloc, json);
    print_vk_chain(parsed_application_info.application_info);
    print_vk_chain(parsed_application_info.device_features2);
}

pub const ParsedSampler = struct {
    version: u32,
    hash: u64,
    sampler_create_info: *const vk.VkSamplerCreateInfo,
};
pub fn parse_sampler(
    alloc: Allocator,
    tmp_alloc: Allocator,
    json_str: []const u8,
) !ParsedSampler {
    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_sampler_create_info = try alloc.create(vk.VkSamplerCreateInfo);
    vk_sampler_create_info.* = .{ .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO };

    var result: ParsedSampler = .{
        .version = 0,
        .hash = 0,
        .sampler_create_info = vk_sampler_create_info,
    };

    while (try scanner_object_next_field(&scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(&scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "samplers")) {
            if (try scanner.next() != .object_begin) return error.InvalidJson;
            const ss = try scanner_next_string(&scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            if (try scanner.next() != .object_begin) return error.InvalidJson;
            try parse_type(
                &.{
                    .{
                        .json_name = "flags",
                        .field_name = "flags",
                        .type = u32,
                    },
                    .{
                        .json_name = "minFilter",
                        .field_name = "minFilter",
                        .type = u32,
                    },
                    .{
                        .json_name = "magFilter",
                        .field_name = "magFilter",
                        .type = u32,
                    },
                    .{
                        .json_name = "maxAnisotropy",
                        .field_name = "maxAnisotropy",
                        .type = f32,
                    },
                    .{
                        .json_name = "compareOp",
                        .field_name = "compareOp",
                        .type = u32,
                    },
                    .{
                        .json_name = "anisotropyEnable",
                        .field_name = "anisotropyEnable",
                        .type = u32,
                    },
                    .{
                        .json_name = "mipmapMode",
                        .field_name = "mipmapMode",
                        .type = u32,
                    },
                    .{
                        .json_name = "addressModeU",
                        .field_name = "addressModeU",
                        .type = u32,
                    },
                    .{
                        .json_name = "addressModeV",
                        .field_name = "addressModeV",
                        .type = u32,
                    },
                    .{
                        .json_name = "addressModeW",
                        .field_name = "addressModeW",
                        .type = u32,
                    },
                    .{
                        .json_name = "borderColor",
                        .field_name = "borderColor",
                        .type = u32,
                    },
                    .{
                        .json_name = "unnormalizedCoordinates",
                        .field_name = "unnormalizedCoordinates",
                        .type = u32,
                    },
                    .{
                        .json_name = "compareEnable",
                        .field_name = "compareEnable",
                        .type = u32,
                    },
                    .{
                        .json_name = "mipLodBias",
                        .field_name = "mipLodBias",
                        .type = f32,
                    },
                    .{
                        .json_name = "minLod",
                        .field_name = "minLod",
                        .type = f32,
                    },
                    .{
                        .json_name = "maxLod",
                        .field_name = "maxLod",
                        .type = f32,
                    },
                },
                alloc,
                &scanner,
                vk_sampler_create_info,
            );
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

    const parsed_sampler = try parse_sampler(alloc, tmp_alloc, json);
    print_vk_struct(parsed_sampler.sampler_create_info);
}

pub const ParsedDescriptorSetLayout = struct {
    version: u32,
    hash: u64,
    descriptor_set_layout_create_info: *const vk.VkDescriptorSetLayoutCreateInfo,
};
pub fn parse_descriptor_set_layout(
    alloc: Allocator,
    tmp_alloc: Allocator,
    json_str: []const u8,
    database: *const Database,
) !ParsedDescriptorSetLayout {
    const Inner = struct {
        fn parse_layout(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            vk_descriptor_set_layout_create_info: *vk.VkDescriptorSetLayoutCreateInfo,
            db: *const Database,
        ) !void {
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    vk_descriptor_set_layout_create_info.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "bindings")) {
                    const bindings = try parse_bindings(aa, sa, scanner, db);
                    vk_descriptor_set_layout_create_info.pBindings =
                        @ptrCast(bindings.ptr);
                    vk_descriptor_set_layout_create_info.bindingCount =
                        @intCast(bindings.len);
                } else if (std.mem.eql(u8, s, "pNext")) {
                    vk_descriptor_set_layout_create_info.pNext =
                        try parse_pnext_chain(aa, sa, scanner);
                } else {
                    return error.InvalidJson;
                }
            }
        }

        fn parse_bindings(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: *const Database,
        ) ![]vk.VkDescriptorSetLayoutBinding {
            var tmp_bindings: std.ArrayListUnmanaged(vk.VkDescriptorSetLayoutBinding) = .empty;
            while (try scanner_array_next(scanner)) {
                try tmp_bindings.append(sa, .{});
                const binding = &tmp_bindings.items[tmp_bindings.items.len - 1];
                while (try scanner_object_next_field(scanner)) |s| {
                    if (std.mem.eql(u8, s, "descriptorType")) {
                        const v = try scanner_next_number(scanner);
                        binding.descriptorType = try std.fmt.parseInt(u32, v, 10);
                    } else if (std.mem.eql(u8, s, "descriptorCount")) {
                        const v = try scanner_next_number(scanner);
                        binding.descriptorCount = try std.fmt.parseInt(u32, v, 10);
                    } else if (std.mem.eql(u8, s, "stageFlags")) {
                        const v = try scanner_next_number(scanner);
                        binding.stageFlags = try std.fmt.parseInt(u32, v, 10);
                    } else if (std.mem.eql(u8, s, "binding")) {
                        const v = try scanner_next_number(scanner);
                        binding.binding = try std.fmt.parseInt(u32, v, 10);
                    } else if (std.mem.eql(u8, s, "immutableSamplers")) {
                        const samplers = try parse_object_array(
                            vk.VkSampler,
                            .SAMPLER,
                            aa,
                            sa,
                            scanner,
                            db,
                        );
                        binding.pImmutableSamplers = @ptrCast(samplers.ptr);
                    }
                }
            }
            return aa.dupe(vk.VkDescriptorSetLayoutBinding, tmp_bindings.items);
        }
    };

    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_descriptor_set_layout_create_info =
        try alloc.create(vk.VkDescriptorSetLayoutCreateInfo);
    vk_descriptor_set_layout_create_info.* =
        .{ .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO };

    var result: ParsedDescriptorSetLayout = .{
        .version = 0,
        .hash = 0,
        .descriptor_set_layout_create_info = vk_descriptor_set_layout_create_info,
    };

    while (true) {
        switch (try scanner.next()) {
            .string => |s| {
                if (std.mem.eql(u8, s, "version")) {
                    const v = try scanner_next_number(&scanner);
                    result.version = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "setLayouts")) {
                    if (try scanner.next() != .object_begin) return error.InvalidJson;
                    const ss = try scanner_next_string(&scanner);
                    result.hash = try std.fmt.parseInt(u64, ss, 16);
                    if (try scanner.next() != .object_begin) return error.InvalidJson;
                    try Inner.parse_layout(
                        alloc,
                        tmp_alloc,
                        &scanner,
                        vk_descriptor_set_layout_create_info,
                        database,
                    );
                } else {
                    return error.InvalidJson;
                }
            },
            .end_of_document => break,
            else => {},
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
        .object = @ptrFromInt(0x69),
    });

    const parsed_descriptro_set_layout = try parse_descriptor_set_layout(
        alloc,
        tmp_alloc,
        json,
        &db,
    );
    print_vk_chain(parsed_descriptro_set_layout.descriptor_set_layout_create_info);
}

pub const ParsedPipelineLayout = struct {
    version: u32,
    hash: u64,
    pipeline_layout_create_info: *const vk.VkPipelineLayoutCreateInfo,
};
pub fn parse_pipeline_layout(
    alloc: Allocator,
    tmp_alloc: Allocator,
    json_str: []const u8,
    database: *const Database,
) !ParsedPipelineLayout {
    const Inner = struct {
        fn parse_layout(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            vk_pipeline_layout_create_info: *vk.VkPipelineLayoutCreateInfo,
            db: *const Database,
        ) !void {
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    vk_pipeline_layout_create_info.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "pushConstantRanges")) {
                    const constant_ranges = try parse_push_constant_ranges(aa, sa, scanner);
                    vk_pipeline_layout_create_info.pPushConstantRanges =
                        @ptrCast(constant_ranges.ptr);
                    vk_pipeline_layout_create_info.pushConstantRangeCount =
                        @intCast(constant_ranges.len);
                } else if (std.mem.eql(u8, s, "setLayouts")) {
                    const set_layouts = try parse_object_array(
                        vk.VkDescriptorSetLayout,
                        .DESCRIPTOR_SET_LAYOUT,
                        aa,
                        sa,
                        scanner,
                        db,
                    );
                    vk_pipeline_layout_create_info.pSetLayouts = @ptrCast(set_layouts.ptr);
                    vk_pipeline_layout_create_info.setLayoutCount = @intCast(set_layouts.len);
                } else {
                    return error.InvalidJson;
                }
            }
        }

        fn parse_push_constant_ranges(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
        ) ![]vk.VkPushConstantRange {
            var tmp_ranges: std.ArrayListUnmanaged(vk.VkPushConstantRange) = .empty;
            while (try scanner_array_next(scanner)) {
                try tmp_ranges.append(sa, .{});
                const range = &tmp_ranges.items[tmp_ranges.items.len - 1];
                try parse_type(
                    &.{
                        .{
                            .json_name = "stageFlags",
                            .field_name = "stageFlags",
                            .type = u32,
                        },
                        .{
                            .json_name = "size",
                            .field_name = "size",
                            .type = u32,
                        },
                        .{
                            .json_name = "offset",
                            .field_name = "offset",
                            .type = u32,
                        },
                    },
                    aa,
                    scanner,
                    range,
                );
            }
            return aa.dupe(vk.VkPushConstantRange, tmp_ranges.items);
        }

        fn parse_descriptor_set_layouts(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: *const Database,
        ) ![]vk.VkDescriptorSetLayout {
            if (try scanner.next() != .array_begin) return error.InvalidJson;
            var tmp_layouts: std.ArrayListUnmanaged(vk.VkDescriptorSetLayout) = .empty;
            while (true) {
                switch (try scanner.next()) {
                    .string => |hash_str| {
                        const hash = try std.fmt.parseInt(u64, hash_str, 16);
                        const layouts = db.entries.getPtrConst(.DESCRIPTOR_SET_LAYOUT);
                        const layout = layouts.getPtr(hash).?;
                        try tmp_layouts.append(sa, @ptrCast(layout.object));
                    },
                    .array_end => break,
                    else => return error.InvalidJson,
                }
            }
            return try aa.dupe(vk.VkDescriptorSetLayout, tmp_layouts.items);
        }
    };

    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_pipeline_layout_create_info =
        try alloc.create(vk.VkPipelineLayoutCreateInfo);
    vk_pipeline_layout_create_info.* =
        .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };

    var result: ParsedPipelineLayout = .{
        .version = 0,
        .hash = 0,
        .pipeline_layout_create_info = vk_pipeline_layout_create_info,
    };

    while (true) {
        switch (try scanner.next()) {
            .string => |s| {
                if (std.mem.eql(u8, s, "version")) {
                    const v = try scanner_next_number(&scanner);
                    result.version = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "pipelineLayouts")) {
                    if (try scanner.next() != .object_begin) return error.InvalidJson;
                    const ss = try scanner_next_string(&scanner);
                    result.hash = try std.fmt.parseInt(u64, ss, 16);
                    if (try scanner.next() != .object_begin) return error.InvalidJson;
                    try Inner.parse_layout(
                        alloc,
                        tmp_alloc,
                        &scanner,
                        vk_pipeline_layout_create_info,
                        database,
                    );
                } else {
                    return error.InvalidJson;
                }
            },
            .end_of_document => break,
            else => {},
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
        .object = @ptrFromInt(0x69),
    });

    const parsed_pipeline_layout = try parse_pipeline_layout(
        alloc,
        tmp_alloc,
        json,
        &db,
    );
    print_vk_chain(parsed_pipeline_layout.pipeline_layout_create_info);
}

pub const ParsedShaderModule = struct {
    version: u32,
    hash: u64,
    shader_module_create_info: *const vk.VkShaderModuleCreateInfo,
};
pub fn parse_shader_module(
    alloc: Allocator,
    tmp_alloc: Allocator,
    payload: []const u8,
) !ParsedShaderModule {
    const Inner = struct {
        fn parse_sm(
            aa: Allocator,
            scanner: *std.json.Scanner,
            vk_shader_module_create_info: *vk.VkShaderModuleCreateInfo,
            shader_code_payload: []const u8,
        ) !void {
            // NOTE: there is a possibility that the json object does not have
            // `varintOffset` and `variantSize` fields. In such case the shader code
            // is inlined in the `code` string. Skip this case for now.
            var variant_offset: u64 = 0;
            var variant_size: u64 = 0;
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "varintOffset")) {
                    const v = try scanner_next_number(scanner);
                    variant_offset = try std.fmt.parseInt(u64, v, 10);
                } else if (std.mem.eql(u8, s, "varintSize")) {
                    const v = try scanner_next_number(scanner);
                    variant_size = try std.fmt.parseInt(u64, v, 10);
                } else if (std.mem.eql(u8, s, "codeSize")) {
                    const v = try scanner_next_number(scanner);
                    vk_shader_module_create_info.codeSize = try std.fmt.parseInt(u64, v, 10);
                } else if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    vk_shader_module_create_info.flags = try std.fmt.parseInt(u32, v, 10);
                }
            }
            if (shader_code_payload.len < variant_offset + variant_size)
                return error.InvalidShaderPayload;
            const code = try aa.alignedAlloc(
                u32,
                64,
                vk_shader_module_create_info.codeSize / @sizeOf(u32),
            );
            if (!decode_shader_payload(
                shader_code_payload[variant_offset..][0..variant_size],
                code,
            ))
                return error.InvalidShaderPayloadEncoding;
            vk_shader_module_create_info.pCode = @ptrCast(code.ptr);
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
    vk_shader_module_create_info.* = .{ .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO };

    var result: ParsedShaderModule = .{
        .version = 0,
        .hash = 0,
        .shader_module_create_info = vk_shader_module_create_info,
    };

    while (try scanner_object_next_field(&scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(&scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "shaderModules")) {
            if (try scanner.next() != .object_begin) return error.InvalidJson;
            const ss = try scanner_next_string(&scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            if (try scanner.next() != .object_begin) return error.InvalidJson;
            try Inner.parse_sm(
                alloc,
                &scanner,
                vk_shader_module_create_info,
                shader_code_payload,
            );
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

    const parsed_shader_module = try parse_shader_module(alloc, tmp_alloc, json);
    print_vk_struct(parsed_shader_module.shader_module_create_info);
}

pub const ParsedRenderPass = struct {
    version: u32,
    hash: u64,
    render_pass_create_info: *const vk.VkRenderPassCreateInfo,
};
pub fn parse_render_pass(
    alloc: Allocator,
    tmp_alloc: Allocator,
    json_str: []const u8,
) !ParsedRenderPass {
    const Inner = struct {
        fn parse_rp(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            vk_render_pass_create_info: *vk.VkRenderPassCreateInfo,
        ) !void {
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    vk_render_pass_create_info.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "dependencies")) {
                    const dependencies = try parse_dependencies(aa, sa, scanner);
                    vk_render_pass_create_info.pDependencies = @ptrCast(dependencies.ptr);
                    vk_render_pass_create_info.dependencyCount = @intCast(dependencies.len);
                } else if (std.mem.eql(u8, s, "attachments")) {
                    const attachments = try parse_attachments(aa, sa, scanner);
                    vk_render_pass_create_info.pAttachments = @ptrCast(attachments.ptr);
                    vk_render_pass_create_info.attachmentCount = @intCast(attachments.len);
                } else if (std.mem.eql(u8, s, "subpasses")) {
                    const subpasses = try parse_subpasses(aa, sa, scanner);
                    vk_render_pass_create_info.pSubpasses = @ptrCast(subpasses.ptr);
                    vk_render_pass_create_info.subpassCount = @intCast(subpasses.len);
                }
            }
        }

        fn parse_dependencies(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
        ) ![]vk.VkSubpassDependency {
            var tmp: std.ArrayListUnmanaged(vk.VkSubpassDependency) = .empty;
            while (try scanner_array_next(scanner)) {
                try tmp.append(sa, .{});
                const item = &tmp.items[tmp.items.len - 1];
                try parse_type(
                    &.{
                        .{
                            .json_name = "dependencyFlags",
                            .field_name = "dependencyFlags",
                            .type = u32,
                        },
                        .{
                            .json_name = "dstAccessMask",
                            .field_name = "dstAccessMask",
                            .type = u32,
                        },
                        .{
                            .json_name = "srcAccessMask",
                            .field_name = "srcAccessMask",
                            .type = u32,
                        },
                        .{
                            .json_name = "dstStageMask",
                            .field_name = "dstStageMask",
                            .type = u32,
                        },
                        .{
                            .json_name = "srcStageMask",
                            .field_name = "srcStageMask",
                            .type = u32,
                        },
                        .{
                            .json_name = "dstSubpass",
                            .field_name = "dstSubpass",
                            .type = u32,
                        },
                        .{
                            .json_name = "srcSubpass",
                            .field_name = "srcSubpass",
                            .type = u32,
                        },
                    },
                    null,
                    scanner,
                    item,
                );
            }
            return aa.dupe(vk.VkSubpassDependency, tmp.items);
        }

        fn parse_attachments(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
        ) ![]vk.VkAttachmentDescription {
            var tmp: std.ArrayListUnmanaged(vk.VkAttachmentDescription) = .empty;
            while (try scanner_array_next(scanner)) {
                try tmp.append(sa, .{});
                const item = &tmp.items[tmp.items.len - 1];
                try parse_type(
                    &.{
                        .{
                            .json_name = "flags",
                            .field_name = "flags",
                            .type = u32,
                        },
                        .{
                            .json_name = "format",
                            .field_name = "format",
                            .type = u32,
                        },
                        .{
                            .json_name = "finalLayout",
                            .field_name = "finalLayout",
                            .type = u32,
                        },
                        .{
                            .json_name = "initialLayout",
                            .field_name = "initialLayout",
                            .type = u32,
                        },
                        .{
                            .json_name = "loadOp",
                            .field_name = "loadOp",
                            .type = u32,
                        },
                        .{
                            .json_name = "storeOp",
                            .field_name = "storeOp",
                            .type = u32,
                        },
                        .{
                            .json_name = "samples",
                            .field_name = "samples",
                            .type = u32,
                        },
                        .{
                            .json_name = "stencilLoadOp",
                            .field_name = "stencilLoadOp",
                            .type = u32,
                        },
                        .{
                            .json_name = "stencilStoreOp",
                            .field_name = "stencilStoreOp",
                            .type = u32,
                        },
                    },
                    null,
                    scanner,
                    item,
                );
            }
            return aa.dupe(vk.VkAttachmentDescription, tmp.items);
        }

        fn parse_subpasses(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
        ) ![]vk.VkSubpassDescription {
            var tmp: std.ArrayListUnmanaged(vk.VkSubpassDescription) = .empty;
            while (try scanner_array_next(scanner)) {
                try tmp.append(sa, .{});
                const item = &tmp.items[tmp.items.len - 1];

                while (try scanner_object_next_field(scanner)) |s| {
                    if (std.mem.eql(u8, s, "flags")) {
                        const v = try scanner_next_number(scanner);
                        item.flags = try std.fmt.parseInt(u32, v, 10);
                    } else if (std.mem.eql(u8, s, "pipelineBindPoint")) {
                        const v = try scanner_next_number(scanner);
                        item.pipelineBindPoint = try std.fmt.parseInt(u32, v, 10);
                    } else if (std.mem.eql(u8, s, "inputAttachments")) {
                        const attachments = try parse_attachment_references(aa, sa, scanner);
                        item.pInputAttachments = @ptrCast(attachments.ptr);
                        item.inputAttachmentCount = @intCast(attachments.len);
                    } else if (std.mem.eql(u8, s, "colorAttachments")) {
                        const attachments = try parse_attachment_references(aa, sa, scanner);
                        item.pColorAttachments = @ptrCast(attachments.ptr);
                        item.colorAttachmentCount = @intCast(attachments.len);
                    } else if (std.mem.eql(u8, s, "resolveAttachments")) {
                        const attachments = try parse_attachment_references(aa, sa, scanner);
                        item.pResolveAttachments = @ptrCast(attachments.ptr);
                    } else if (std.mem.eql(u8, s, "depthStencilAttachment")) {
                        const attachment = try aa.create(vk.VkAttachmentReference);
                        try parse_type(
                            &.{
                                .{
                                    .json_name = "attachment",
                                    .field_name = "attachment",
                                    .type = u32,
                                },
                                .{
                                    .json_name = "layout",
                                    .field_name = "layout",
                                    .type = u32,
                                },
                            },
                            null,
                            scanner,
                            attachment,
                        );
                        item.pDepthStencilAttachment = attachment;
                    } else if (std.mem.eql(u8, s, "preserveAttachments")) {
                        const attachments = try parse_attachment_references(aa, sa, scanner);
                        item.pPreserveAttachments = @ptrCast(attachments.ptr);
                        item.preserveAttachmentCount = @intCast(attachments.len);
                    }
                }
            }
            return aa.dupe(vk.VkSubpassDescription, tmp.items);
        }

        fn parse_attachment_references(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
        ) ![]vk.VkAttachmentReference {
            var tmp: std.ArrayListUnmanaged(vk.VkAttachmentReference) = .empty;
            while (try scanner_array_next(scanner)) {
                try tmp.append(sa, .{});
                const item = &tmp.items[tmp.items.len - 1];
                try parse_type(
                    &.{
                        .{
                            .json_name = "attachment",
                            .field_name = "attachment",
                            .type = u32,
                        },
                        .{
                            .json_name = "layout",
                            .field_name = "layout",
                            .type = u32,
                        },
                    },
                    null,
                    scanner,
                    item,
                );
            }
            return aa.dupe(vk.VkAttachmentReference, tmp.items);
        }
    };

    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_render_pass_create_info = try alloc.create(vk.VkRenderPassCreateInfo);
    vk_render_pass_create_info.* = .{ .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO };

    var result: ParsedRenderPass = .{
        .version = 0,
        .hash = 0,
        .render_pass_create_info = vk_render_pass_create_info,
    };

    while (try scanner_object_next_field(&scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(&scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "renderPasses")) {
            if (try scanner.next() != .object_begin) return error.InvalidJson;
            const ss = try scanner_next_string(&scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            if (try scanner.next() != .object_begin) return error.InvalidJson;
            try Inner.parse_rp(
                alloc,
                tmp_alloc,
                &scanner,
                vk_render_pass_create_info,
            );
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

    const parsed_render_pass = try parse_render_pass(alloc, tmp_alloc, json);
    print_vk_struct(parsed_render_pass.render_pass_create_info);
}
