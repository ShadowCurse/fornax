const std = @import("std");
const vk = @import("volk.zig");
const log = @import("log.zig");

const Allocator = std.mem.Allocator;

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
            ?*anyopaque, ?*const anyopaque => {
                log.info(@src(), "\t{s}: {?}", .{ field.name, @field(@"struct", field.name) });
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
    arena_alloc: ?Allocator,
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
                        if (arena_alloc) |aa| {
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
    arena_alloc: Allocator,
    scratch_alloc: Allocator,
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
            const flags = try Inner.parse_flags(arena_alloc, scratch_alloc, scanner);
            obj.pBindingFlags = @ptrCast(flags.ptr);
            obj.bindingCount = @intCast(flags.len);
        } else {
            return error.InvalidJson;
        }
    }
}

pub fn parse_pnext_chain(
    arena_alloc: Allocator,
    scratch_alloc: Allocator,
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
                arena_alloc,
                scratch_alloc,
                scanner,
                &first_in_chain,
                &last_pnext_in_chain,
            );
        } else return error.InvalidJson;
    }
    return first_in_chain;
}

pub fn parse_application_info(
    arena_alloc: Allocator,
    scratch_alloc: Allocator,
    json_str: []const u8,
) !*const vk.VkApplicationInfo {
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

    var scanner = std.json.Scanner.initCompleteInput(arena_alloc, json_str);
    const vk_application_info = try arena_alloc.create(vk.VkApplicationInfo);
    vk_application_info.* = .{ .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO };
    const vk_physical_device_features2 = try arena_alloc.create(vk.VkPhysicalDeviceFeatures2);
    vk_physical_device_features2.* = .{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 };

    while (try scanner_object_next_field(&scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            switch (try scanner.next()) {
                .number => |n| {
                    const version = try std.fmt.parseInt(u32, n, 10);
                    log.info(@src(), "version: {d}", .{version});
                },
                else => return error.InvalidJson,
            }
        } else if (std.mem.eql(u8, s, "applicationInfo")) {
            try Inner.parse_app_info(arena_alloc, &scanner, vk_application_info);
        } else if (std.mem.eql(u8, s, "physicalDeviceFeatures")) {
            try Inner.parse_device_features(
                arena_alloc,
                scratch_alloc,
                &scanner,
                vk_physical_device_features2,
            );
            vk_application_info.pNext = @ptrCast(vk_physical_device_features2);
        }
    }
    return vk_application_info;
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
    const arena_alloc = arena.allocator();
    var scratch_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const scratch_alloc = scratch_arena.allocator();

    const vk_app_info = try parse_application_info(arena_alloc, scratch_alloc, json);
    print_vk_chain(vk_app_info);
}

pub const ParsedSampler = struct {
    hash: u64,
    sampler_create_info: *const vk.VkSamplerCreateInfo,
};
pub fn parse_sampler(
    arena_alloc: Allocator,
    json_str: []const u8,
) !ParsedSampler {
    var scanner = std.json.Scanner.initCompleteInput(arena_alloc, json_str);
    const vk_sampler_create_info = try arena_alloc.create(vk.VkSamplerCreateInfo);
    vk_sampler_create_info.* = .{ .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO };

    var result: ParsedSampler = .{
        .hash = 0,
        .sampler_create_info = vk_sampler_create_info,
    };

    while (try scanner_object_next_field(&scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(&scanner);
            const version = try std.fmt.parseInt(u32, v, 10);
            log.info(@src(), "version: {d}", .{version});
        } else if (std.mem.eql(u8, s, "samplers")) {
            if (try scanner.next() != .object_begin) return error.InvalidJson;
            const ss = try scanner_next_string(&scanner);
            const hash = try std.fmt.parseInt(u64, ss, 16);
            log.info(@src(), "hash: 0x{x}", .{hash});
            result.hash = hash;
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
                arena_alloc,
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
    const arena_alloc = arena.allocator();

    const parsed_sampler = try parse_sampler(arena_alloc, json);
    print_vk_struct(parsed_sampler.sampler_create_info);
}

pub const ParsedDescriptorSetLayout = struct {
    hash: u64,
    descriptor_set_layout_create_info: *const vk.VkDescriptorSetLayoutCreateInfo,
};
pub fn parse_descriptor_set_layout(
    arena_alloc: Allocator,
    scratch_alloc: Allocator,
    json_str: []const u8,
) !ParsedDescriptorSetLayout {
    const Inner = struct {
        fn parse_layout(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            vk_descriptor_set_layout_create_info: *vk.VkDescriptorSetLayoutCreateInfo,
        ) !void {
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    vk_descriptor_set_layout_create_info.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "bindings")) {
                    const bindings = try parse_bindings(aa, sa, scanner);
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
        ) ![]vk.VkDescriptorSetLayoutBinding {
            var tmp_bindings: std.ArrayListUnmanaged(vk.VkDescriptorSetLayoutBinding) = .empty;
            while (try scanner_array_next(scanner)) {
                try tmp_bindings.append(sa, .{});
                try parse_type(
                    &.{
                        .{
                            .json_name = "descriptorType",
                            .field_name = "descriptorType",
                            .type = u32,
                        },
                        .{
                            .json_name = "descriptorCount",
                            .field_name = "descriptorCount",
                            .type = u32,
                        },
                        .{
                            .json_name = "stageFlags",
                            .field_name = "stageFlags",
                            .type = u32,
                        },
                        .{
                            .json_name = "binding",
                            .field_name = "binding",
                            .type = u32,
                        },
                    },
                    null,
                    scanner,
                    &tmp_bindings.items[tmp_bindings.items.len - 1],
                );
            }
            return aa.dupe(vk.VkDescriptorSetLayoutBinding, tmp_bindings.items);
        }
    };

    var scanner = std.json.Scanner.initCompleteInput(arena_alloc, json_str);
    const vk_descriptor_set_layout_create_info =
        try arena_alloc.create(vk.VkDescriptorSetLayoutCreateInfo);
    vk_descriptor_set_layout_create_info.* =
        .{ .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO };

    var result: ParsedDescriptorSetLayout = .{
        .hash = 0,
        .descriptor_set_layout_create_info = vk_descriptor_set_layout_create_info,
    };

    while (true) {
        switch (try scanner.next()) {
            .string => |s| {
                if (std.mem.eql(u8, s, "version")) {
                    const v = try scanner_next_number(&scanner);
                    const version = try std.fmt.parseInt(u32, v, 10);
                    log.info(@src(), "version: {d}", .{version});
                } else if (std.mem.eql(u8, s, "setLayouts")) {
                    if (try scanner.next() != .object_begin) return error.InvalidJson;
                    const ss = try scanner_next_string(&scanner);
                    const hash = try std.fmt.parseInt(u64, ss, 16);
                    log.info(@src(), "hash: 0x{x}", .{hash});
                    result.hash = hash;
                    if (try scanner.next() != .object_begin) return error.InvalidJson;
                    try Inner.parse_layout(
                        arena_alloc,
                        scratch_alloc,
                        &scanner,
                        vk_descriptor_set_layout_create_info,
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
        \\          "binding": 46
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
    const json2 =
        \\{
        \\  "version": 6,
        \\  "setLayouts": {
        \\    "01fe45398ef51d72": {
        \\      "flags": 2,
        \\      "bindings": [
        \\        {
        \\          "descriptorType": 2,
        \\          "descriptorCount": 65536,
        \\          "stageFlags": 16185,
        \\          "binding": 46,
        \\          "immutableSamplers": [
        \\            "8c0a0c8a78e29f7c"
        \\          ]
        \\        }
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    // TODO handle `immutableSamplers`.
    _ = json2;
    var gpa = std.heap.DebugAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const arena_alloc = arena.allocator();
    var scratch_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const scratch_alloc = scratch_arena.allocator();

    const parsed_descriptro_set_layout = try parse_descriptor_set_layout(
        arena_alloc,
        scratch_alloc,
        json,
    );
    print_vk_chain(parsed_descriptro_set_layout.descriptor_set_layout_create_info);
}
