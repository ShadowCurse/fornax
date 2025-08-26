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

fn scanner_array_next_object(scanner: *std.json.Scanner) !bool {
    loop: switch (try scanner.next()) {
        .array_begin => continue :loop try scanner.next(),
        .array_end => return false,
        .object_begin => return true,
        else => return error.InvalidJson,
    }
}

fn scanner_array_next_number(scanner: *std.json.Scanner) !?[]const u8 {
    loop: switch (try scanner.next()) {
        .array_begin => continue :loop try scanner.next(),
        .array_end => return null,
        .number => |v| return v,
        else => return error.InvalidJson,
    }
}

fn scanner_array_next_string(scanner: *std.json.Scanner) !?[]const u8 {
    loop: switch (try scanner.next()) {
        .array_begin => continue :loop try scanner.next(),
        .array_end => return null,
        .string => |s| return s,
        else => return error.InvalidJson,
    }
}

pub fn parse_simple_type(
    scanner: *std.json.Scanner,
    output: anytype,
) !void {
    const output_type = @typeInfo(@TypeOf(output)).pointer.child;
    const output_fields = @typeInfo(output_type).@"struct".fields;
    var field_is_parsed: [output_fields.len]bool = .{false} ** output_fields.len;
    while (try scanner_object_next_field(scanner)) |s| {
        inline for (output_fields, 0..) |field, i| {
            if (!field_is_parsed[i] and std.mem.eql(u8, s, field.name)) {
                field_is_parsed[i] = true;
                switch (field.type) {
                    i32, u32, c_uint => {
                        const v = try scanner_next_number(scanner);
                        @field(output, field.name) = try std.fmt.parseInt(field.type, v, 10);
                    },
                    f32 => {
                        const v = try scanner_next_number(scanner);
                        @field(output, field.name) = try std.fmt.parseFloat(field.type, v);
                    },
                    else => {},
                }
            }
        }
    }
}

fn parse_number_array(
    comptime T: type,
    aa: Allocator,
    sa: Allocator,
    scanner: *std.json.Scanner,
) ![]T {
    if (try scanner.next() != .array_begin) return error.InvalidJson;
    var tmp: std.ArrayListUnmanaged(T) = .empty;
    while (try scanner_array_next_number(scanner)) |v| {
        const number = try std.fmt.parseInt(T, v, 10);
        try tmp.append(sa, number);
    }
    return try aa.dupe(T, tmp.items);
}

fn parse_handle_array(
    comptime T: type,
    comptime TAG: Database.Entry.Tag,
    aa: Allocator,
    sa: Allocator,
    scanner: *std.json.Scanner,
    db: *const Database,
) ![]T {
    if (try scanner.next() != .array_begin) return error.InvalidJson;
    var tmp: std.ArrayListUnmanaged(T) = .empty;
    while (try scanner_array_next_string(scanner)) |hash_str| {
        const hash = try std.fmt.parseInt(u64, hash_str, 16);
        const entries = db.entries.getPtrConst(TAG);
        const entry = entries.getPtr(hash).?;
        try tmp.append(sa, @ptrCast(entry.handle));
    }
    return try aa.dupe(T, tmp.items);
}

fn parse_object_array(
    comptime T: type,
    comptime PARSE_FN: fn (
        Allocator,
        Allocator,
        *std.json.Scanner,
        ?*const Database,
        *T,
    ) anyerror!void,
    aa: Allocator,
    sa: Allocator,
    scanner: *std.json.Scanner,
    db: ?*const Database,
) ![]T {
    if (try scanner.next() != .array_begin) return error.InvalidJson;
    var tmp: std.ArrayListUnmanaged(T) = .empty;
    while (try scanner_array_next_object(scanner)) {
        try tmp.append(sa, .{});
        const item = &tmp.items[tmp.items.len - 1];
        try PARSE_FN(aa, sa, scanner, db, item);
    }
    return try aa.dupe(T, tmp.items);
}

pub fn parse_physical_device_mesh_shader_features_ext(
    scanner: *std.json.Scanner,
    obj: *vk.VkPhysicalDeviceMeshShaderFeaturesEXT,
) !void {
    return parse_simple_type(scanner, obj);
}

pub fn parse_physical_device_fragment_shading_rate_features_khr(
    scanner: *std.json.Scanner,
    obj: *vk.VkPhysicalDeviceFragmentShadingRateFeaturesKHR,
) !void {
    return parse_simple_type(scanner, obj);
}

pub fn parse_descriptor_set_layout_binding_flags_create_info_ext(
    alloc: Allocator,
    tmp_alloc: Allocator,
    scanner: *std.json.Scanner,
    obj: *vk.VkDescriptorSetLayoutBindingFlagsCreateInfoEXT,
) !void {
    while (try scanner_object_next_field(scanner)) |s| {
        if (std.mem.eql(u8, s, "bindingFlags")) {
            const flags = try parse_number_array(u32, alloc, tmp_alloc, scanner);
            obj.pBindingFlags = @ptrCast(flags.ptr);
            obj.bindingCount = @intCast(flags.len);
        }
    }
}

pub fn parse_pipeline_rendering_create_info_khr(
    alloc: Allocator,
    tmp_alloc: Allocator,
    scanner: *std.json.Scanner,
    obj: *vk.VkPipelineRenderingCreateInfo,
) !void {
    while (try scanner_object_next_field(scanner)) |s| {
        if (std.mem.eql(u8, s, "depthAttachmentFormat")) {
            const v = try scanner_next_number(scanner);
            obj.depthAttachmentFormat = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "stencilAttachmentFormat")) {
            const v = try scanner_next_number(scanner);
            obj.stencilAttachmentFormat = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "viewMask")) {
            const v = try scanner_next_number(scanner);
            obj.viewMask = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "colorAttachmentFormats")) {
            const formats = try parse_number_array(u32, alloc, tmp_alloc, scanner);
            obj.pColorAttachmentFormats = @ptrCast(formats.ptr);
            obj.colorAttachmentCount = @intCast(formats.len);
        } else if (std.mem.eql(u8, s, "depthAttachmentFormat")) {
            const v = try scanner_next_number(scanner);
            obj.depthAttachmentFormat = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "stencilAttachmentFormat")) {
            const v = try scanner_next_number(scanner);
            obj.stencilAttachmentFormat = try std.fmt.parseInt(u32, v, 10);
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
                vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR => {
                    const obj = try aa.create(vk.VkPipelineRenderingCreateInfo);
                    obj.* = .{ .sType = stype };
                    if (first_in_chain.* == null)
                        first_in_chain.* = obj;
                    if (last_pnext_in_chain.*) |lpic| {
                        lpic.* = obj;
                    }
                    last_pnext_in_chain.* = @ptrCast(&obj.pNext);
                    try parse_pipeline_rendering_create_info_khr(
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
    while (try scanner_array_next_object(scanner)) {
        const s = try scanner_object_next_field(scanner) orelse return error.InvalidJson;
        if (std.mem.eql(u8, s, "sType")) {
            try Inner.parse_next(
                alloc,
                tmp_alloc,
                scanner,
                &first_in_chain,
                &last_pnext_in_chain,
            );
        }
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
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "applicationName")) {
                    const name = try aa.dupeZ(u8, s);
                    vk_application_info.pApplicationName = @ptrCast(name.ptr);
                } else if (std.mem.eql(u8, s, "engineName")) {
                    const name = try aa.dupeZ(u8, s);
                    vk_application_info.pEngineName = @ptrCast(name.ptr);
                } else if (std.mem.eql(u8, s, "applicationVersion")) {
                    const v = try scanner_next_number(scanner);
                    vk_application_info.applicationVersion = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "engineVersion")) {
                    const v = try scanner_next_number(scanner);
                    vk_application_info.engineVersion = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "apiVersion")) {
                    const v = try scanner_next_number(scanner);
                    vk_application_info.apiVersion = try std.fmt.parseInt(u32, v, 10);
                }
            }
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
            try parse_simple_type(&scanner, vk_sampler_create_info);
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
                    const bindings = try parse_object_array(
                        vk.VkDescriptorSetLayoutBinding,
                        parse_vk_descriptor_set_layout_binding,
                        aa,
                        sa,
                        scanner,
                        db,
                    );
                    vk_descriptor_set_layout_create_info.pBindings = @ptrCast(bindings.ptr);
                    vk_descriptor_set_layout_create_info.bindingCount = @intCast(bindings.len);
                } else if (std.mem.eql(u8, s, "pNext")) {
                    vk_descriptor_set_layout_create_info.pNext =
                        try parse_pnext_chain(aa, sa, scanner);
                }
            }
        }

        fn parse_vk_descriptor_set_layout_binding(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: ?*const Database,
            item: *vk.VkDescriptorSetLayoutBinding,
        ) !void {
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "descriptorType")) {
                    const v = try scanner_next_number(scanner);
                    item.descriptorType = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "descriptorCount")) {
                    const v = try scanner_next_number(scanner);
                    item.descriptorCount = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "stageFlags")) {
                    const v = try scanner_next_number(scanner);
                    item.stageFlags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "binding")) {
                    const v = try scanner_next_number(scanner);
                    item.binding = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "immutableSamplers")) {
                    const samplers = try parse_handle_array(
                        vk.VkSampler,
                        .SAMPLER,
                        aa,
                        sa,
                        scanner,
                        db.?,
                    );
                    item.pImmutableSamplers = @ptrCast(samplers.ptr);
                }
            }
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

    while (try scanner_object_next_field(&scanner)) |s| {
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
                    const constant_ranges = try parse_object_array(
                        vk.VkPushConstantRange,
                        parse_vk_push_constant_range,
                        aa,
                        sa,
                        scanner,
                        db,
                    );
                    vk_pipeline_layout_create_info.pPushConstantRanges =
                        @ptrCast(constant_ranges.ptr);
                    vk_pipeline_layout_create_info.pushConstantRangeCount =
                        @intCast(constant_ranges.len);
                } else if (std.mem.eql(u8, s, "setLayouts")) {
                    const set_layouts = try parse_handle_array(
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

        fn parse_vk_push_constant_range(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: ?*const Database,
            item: *vk.VkPushConstantRange,
        ) !void {
            _ = aa;
            _ = sa;
            _ = db;
            try parse_simple_type(scanner, item);
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

    while (try scanner_object_next_field(&scanner)) |s| {
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
                    const dependencies = try parse_object_array(
                        vk.VkSubpassDependency,
                        parse_vk_subpass_dependency,
                        aa,
                        sa,
                        scanner,
                        null,
                    );
                    vk_render_pass_create_info.pDependencies = @ptrCast(dependencies.ptr);
                    vk_render_pass_create_info.dependencyCount = @intCast(dependencies.len);
                } else if (std.mem.eql(u8, s, "attachments")) {
                    const attachments = try parse_object_array(
                        vk.VkAttachmentDescription,
                        parse_vk_attachment_description,
                        aa,
                        sa,
                        scanner,
                        null,
                    );
                    vk_render_pass_create_info.pAttachments = @ptrCast(attachments.ptr);
                    vk_render_pass_create_info.attachmentCount = @intCast(attachments.len);
                } else if (std.mem.eql(u8, s, "subpasses")) {
                    const subpasses = try parse_object_array(
                        vk.VkSubpassDescription,
                        parse_vk_subpass_description,
                        aa,
                        sa,
                        scanner,
                        null,
                    );
                    vk_render_pass_create_info.pSubpasses = @ptrCast(subpasses.ptr);
                    vk_render_pass_create_info.subpassCount = @intCast(subpasses.len);
                }
            }
        }

        fn parse_vk_subpass_dependency(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: ?*const Database,
            item: *vk.VkSubpassDependency,
        ) !void {
            _ = aa;
            _ = sa;
            _ = db;
            try parse_simple_type(scanner, item);
        }

        fn parse_vk_attachment_description(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: ?*const Database,
            item: *vk.VkAttachmentDescription,
        ) !void {
            _ = aa;
            _ = sa;
            _ = db;
            try parse_simple_type(scanner, item);
        }

        fn parse_vk_subpass_description(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: ?*const Database,
            item: *vk.VkSubpassDescription,
        ) !void {
            _ = db;
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    item.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "pipelineBindPoint")) {
                    const v = try scanner_next_number(scanner);
                    item.pipelineBindPoint = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "inputAttachments")) {
                    const attachments = try parse_object_array(
                        vk.VkAttachmentReference,
                        parse_vk_attachment_reference,
                        aa,
                        sa,
                        scanner,
                        null,
                    );
                    item.pInputAttachments = @ptrCast(attachments.ptr);
                    item.inputAttachmentCount = @intCast(attachments.len);
                } else if (std.mem.eql(u8, s, "colorAttachments")) {
                    const attachments = try parse_object_array(
                        vk.VkAttachmentReference,
                        parse_vk_attachment_reference,
                        aa,
                        sa,
                        scanner,
                        null,
                    );
                    item.pColorAttachments = @ptrCast(attachments.ptr);
                    item.colorAttachmentCount = @intCast(attachments.len);
                } else if (std.mem.eql(u8, s, "resolveAttachments")) {
                    const attachments = try parse_object_array(
                        vk.VkAttachmentReference,
                        parse_vk_attachment_reference,
                        aa,
                        sa,
                        scanner,
                        null,
                    );
                    item.pResolveAttachments = @ptrCast(attachments.ptr);
                } else if (std.mem.eql(u8, s, "depthStencilAttachment")) {
                    const attachment = try aa.create(vk.VkAttachmentReference);
                    try parse_vk_attachment_reference(aa, sa, scanner, null, attachment);
                    item.pDepthStencilAttachment = attachment;
                } else if (std.mem.eql(u8, s, "preserveAttachments")) {
                    const attachments = try parse_object_array(
                        vk.VkAttachmentReference,
                        parse_vk_attachment_reference,
                        aa,
                        sa,
                        scanner,
                        null,
                    );
                    item.pPreserveAttachments = @ptrCast(attachments.ptr);
                    item.preserveAttachmentCount = @intCast(attachments.len);
                }
            }
        }

        fn parse_vk_attachment_reference(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: ?*const Database,
            item: *vk.VkAttachmentReference,
        ) !void {
            _ = aa;
            _ = sa;
            _ = db;
            try parse_simple_type(scanner, item);
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

pub const ParsedGraphicsPipeline = struct {
    version: u32,
    hash: u64,
    graphics_pipeline_create_info: *const vk.VkGraphicsPipelineCreateInfo,
};
pub fn parse_graphics_pipeline(
    alloc: Allocator,
    tmp_alloc: Allocator,
    json_str: []const u8,
    database: *const Database,
) !ParsedGraphicsPipeline {
    const Inner = struct {
        fn parse_gp(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            vk_graphics_pipeline_create_info: *vk.VkGraphicsPipelineCreateInfo,
            db: *const Database,
        ) !void {
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    vk_graphics_pipeline_create_info.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "basePipelineHandle")) {
                    const v = try scanner_next_string(scanner);
                    const base_pipeline_hash = try std.fmt.parseInt(u64, v, 16);
                    if (base_pipeline_hash != 0)
                        return error.BasePipelinesNotSupported;
                } else if (std.mem.eql(u8, s, "basePipelineIndex")) {
                    const v = try scanner_next_number(scanner);
                    vk_graphics_pipeline_create_info.basePipelineIndex =
                        try std.fmt.parseInt(i32, v, 10);
                } else if (std.mem.eql(u8, s, "layout")) {
                    const v = try scanner_next_string(scanner);
                    const layout_hash = try std.fmt.parseInt(u64, v, 16);
                    const layouts = db.entries.getPtrConst(.PIPELINE_LAYOUT);
                    const layout = layouts.getPtr(layout_hash).?;
                    vk_graphics_pipeline_create_info.layout = @ptrCast(layout.handle);
                } else if (std.mem.eql(u8, s, "renderPass")) {
                    const v = try scanner_next_string(scanner);
                    const render_pass_hash = try std.fmt.parseInt(u64, v, 16);
                    if (render_pass_hash != 0) {
                        const render_passes = db.entries.getPtrConst(.RENDER_PASS);
                        const render_pass = render_passes.getPtr(render_pass_hash).?;
                        vk_graphics_pipeline_create_info.renderPass =
                            @ptrCast(render_pass.handle);
                    }
                } else if (std.mem.eql(u8, s, "subpass")) {
                    const v = try scanner_next_number(scanner);
                    vk_graphics_pipeline_create_info.subpass = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "dynamicState")) {
                    const dynamic_state = try parse_dynamic_state(aa, sa, scanner);
                    vk_graphics_pipeline_create_info.pDynamicState = dynamic_state;
                } else if (std.mem.eql(u8, s, "multisampleState")) {
                    const multisample_state = try parse_multisample_state(aa, scanner);
                    vk_graphics_pipeline_create_info.pMultisampleState = multisample_state;
                } else if (std.mem.eql(u8, s, "vertexInputState")) {
                    const vertex_input_state = try parse_vertex_input_state(aa, sa, scanner);
                    vk_graphics_pipeline_create_info.pVertexInputState = vertex_input_state;
                } else if (std.mem.eql(u8, s, "rasterizationState")) {
                    const raseterization_state = try parse_rasterization_state(aa, scanner);
                    vk_graphics_pipeline_create_info.pRasterizationState = raseterization_state;
                } else if (std.mem.eql(u8, s, "inputAssemblyState")) {
                    const input_assembly_state = try parse_input_assembly_state(aa, scanner);
                    vk_graphics_pipeline_create_info.pInputAssemblyState = input_assembly_state;
                } else if (std.mem.eql(u8, s, "colorBlendState")) {
                    const color_blend_state = try parse_color_blend_state(aa, sa, scanner);
                    vk_graphics_pipeline_create_info.pColorBlendState = color_blend_state;
                } else if (std.mem.eql(u8, s, "viewportState")) {
                    const viewport_state = try parse_viewport_state(aa, scanner);
                    vk_graphics_pipeline_create_info.pViewportState = viewport_state;
                } else if (std.mem.eql(u8, s, "depthStencilState")) {
                    const depth_stencil_state = try parse_depth_stencil_state(aa, scanner);
                    vk_graphics_pipeline_create_info.pDepthStencilState = depth_stencil_state;
                } else if (std.mem.eql(u8, s, "stages")) {
                    const stages = try parse_object_array(
                        vk.VkPipelineShaderStageCreateInfo,
                        parse_vk_pipeline_shader_stage_create_info,
                        aa,
                        sa,
                        scanner,
                        db,
                    );
                    vk_graphics_pipeline_create_info.pStages = @ptrCast(stages.ptr);
                    vk_graphics_pipeline_create_info.stageCount = @intCast(stages.len);
                } else if (std.mem.eql(u8, s, "pNext")) {
                    vk_graphics_pipeline_create_info.pNext =
                        try parse_pnext_chain(aa, sa, scanner);
                }
            }
        }

        fn parse_dynamic_state(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
        ) !*const vk.VkPipelineDynamicStateCreateInfo {
            const dynamic_state = try aa.create(vk.VkPipelineDynamicStateCreateInfo);
            dynamic_state.* = .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            };
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    dynamic_state.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "dynamicState")) {
                    const states = try parse_number_array(u32, aa, sa, scanner);
                    dynamic_state.pDynamicStates = @ptrCast(states.ptr);
                    dynamic_state.dynamicStateCount = @intCast(states.len);
                }
            }
            return dynamic_state;
        }

        fn parse_multisample_state(
            aa: Allocator,
            scanner: *std.json.Scanner,
        ) !*const vk.VkPipelineMultisampleStateCreateInfo {
            const multisample_state =
                try aa.create(vk.VkPipelineMultisampleStateCreateInfo);
            multisample_state.* = .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            };
            try parse_simple_type(scanner, multisample_state);
            return multisample_state;
        }

        fn parse_vk_vertex_input_attribute_description(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: ?*const Database,
            item: *vk.VkVertexInputAttributeDescription,
        ) !void {
            _ = aa;
            _ = sa;
            _ = db;
            try parse_simple_type(scanner, item);
        }

        fn parse_vk_vertex_input_binding_description(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: ?*const Database,
            item: *vk.VkVertexInputBindingDescription,
        ) !void {
            _ = aa;
            _ = sa;
            _ = db;
            try parse_simple_type(scanner, item);
        }

        fn parse_vertex_input_state(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
        ) !*const vk.VkPipelineVertexInputStateCreateInfo {
            const vertex_input_state =
                try aa.create(vk.VkPipelineVertexInputStateCreateInfo);
            vertex_input_state.* = .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            };
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    vertex_input_state.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "attributes")) {
                    const attributes = try parse_object_array(vk.VkVertexInputAttributeDescription, parse_vk_vertex_input_attribute_description, aa, sa, scanner, null);
                    vertex_input_state.pVertexAttributeDescriptions = @ptrCast(attributes.ptr);
                    vertex_input_state.vertexAttributeDescriptionCount = @intCast(attributes.len);
                } else if (std.mem.eql(u8, s, "bindings")) {
                    const bindings = try parse_object_array(vk.VkVertexInputBindingDescription, parse_vk_vertex_input_binding_description, aa, sa, scanner, null);
                    vertex_input_state.pVertexBindingDescriptions = @ptrCast(bindings.ptr);
                    vertex_input_state.vertexBindingDescriptionCount = @intCast(bindings.len);
                }
            }
            return vertex_input_state;
        }

        fn parse_rasterization_state(
            aa: Allocator,
            scanner: *std.json.Scanner,
        ) !*const vk.VkPipelineRasterizationStateCreateInfo {
            const rasterization_state =
                try aa.create(vk.VkPipelineRasterizationStateCreateInfo);
            rasterization_state.* = .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            };
            try parse_simple_type(scanner, rasterization_state);
            return rasterization_state;
        }

        fn parse_input_assembly_state(
            aa: Allocator,
            scanner: *std.json.Scanner,
        ) !*const vk.VkPipelineInputAssemblyStateCreateInfo {
            const input_assembly_state =
                try aa.create(vk.VkPipelineInputAssemblyStateCreateInfo);
            input_assembly_state.* = .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            };
            try parse_simple_type(scanner, input_assembly_state);
            return input_assembly_state;
        }

        fn parse_vk_pipeline_color_blend_attachment_state(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: ?*const Database,
            item: *vk.VkPipelineColorBlendAttachmentState,
        ) !void {
            _ = aa;
            _ = sa;
            _ = db;
            try parse_simple_type(scanner, item);
        }

        fn parse_color_blend_state(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
        ) !*const vk.VkPipelineColorBlendStateCreateInfo {
            const color_blend_state =
                try aa.create(vk.VkPipelineColorBlendStateCreateInfo);
            color_blend_state.* = .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            };
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    color_blend_state.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "logicOp")) {
                    const v = try scanner_next_number(scanner);
                    color_blend_state.logicOp = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "logicOpEnable")) {
                    const v = try scanner_next_number(scanner);
                    color_blend_state.logicOpEnable = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "blendConstants")) {
                    if (try scanner.next() != .array_begin) return error.InvalidJson;
                    var i: u32 = 0;
                    while (try scanner_array_next_number(scanner)) |v| {
                        color_blend_state.blendConstants[i] = try std.fmt.parseFloat(f32, v);
                        i += 1;
                    }
                } else if (std.mem.eql(u8, s, "attachments")) {
                    const attachments = try parse_object_array(
                        vk.VkPipelineColorBlendAttachmentState,
                        parse_vk_pipeline_color_blend_attachment_state,
                        aa,
                        sa,
                        scanner,
                        null,
                    );
                    color_blend_state.pAttachments = @ptrCast(attachments.ptr);
                    color_blend_state.attachmentCount = @intCast(attachments.len);
                }
            }
            return color_blend_state;
        }

        fn parse_viewport_state(
            aa: Allocator,
            scanner: *std.json.Scanner,
        ) !*const vk.VkPipelineViewportStateCreateInfo {
            const viewport_state =
                try aa.create(vk.VkPipelineViewportStateCreateInfo);
            viewport_state.* = .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            };
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    viewport_state.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "viewportCount")) {
                    const v = try scanner_next_number(scanner);
                    viewport_state.viewportCount = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "pViewports")) {
                    // Do nothing for now
                } else if (std.mem.eql(u8, s, "scissorCount")) {
                    const v = try scanner_next_number(scanner);
                    viewport_state.scissorCount = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "pScissors")) {
                    // Do nothing for now
                } else if (std.mem.eql(u8, s, "pNext")) {
                    // Do nothing for now
                }
            }
            return viewport_state;
        }

        fn parse_depth_stencil_state(
            aa: Allocator,
            scanner: *std.json.Scanner,
        ) !*const vk.VkPipelineDepthStencilStateCreateInfo {
            const depth_stencil_state =
                try aa.create(vk.VkPipelineDepthStencilStateCreateInfo);
            depth_stencil_state.* = .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            };
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    depth_stencil_state.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "stencilTestEnable")) {
                    const v = try scanner_next_number(scanner);
                    depth_stencil_state.stencilTestEnable = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "maxDepthBounds")) {
                    const v = try scanner_next_number(scanner);
                    depth_stencil_state.maxDepthBounds = try std.fmt.parseFloat(f32, v);
                } else if (std.mem.eql(u8, s, "minDepthBounds")) {
                    const v = try scanner_next_number(scanner);
                    depth_stencil_state.minDepthBounds = try std.fmt.parseFloat(f32, v);
                } else if (std.mem.eql(u8, s, "depthBoundsTestEnable")) {
                    const v = try scanner_next_number(scanner);
                    depth_stencil_state.depthBoundsTestEnable = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "depthWriteEnable")) {
                    const v = try scanner_next_number(scanner);
                    depth_stencil_state.depthWriteEnable = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "depthTestEnable")) {
                    const v = try scanner_next_number(scanner);
                    depth_stencil_state.depthTestEnable = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "depthCompareOp")) {
                    const v = try scanner_next_number(scanner);
                    depth_stencil_state.depthCompareOp = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "front")) {
                    try parse_simple_type(scanner, &depth_stencil_state.front);
                } else if (std.mem.eql(u8, s, "back")) {
                    try parse_simple_type(scanner, &depth_stencil_state.front);
                }
            }
            return depth_stencil_state;
        }

        fn parse_vk_pipeline_shader_stage_create_info(
            aa: Allocator,
            sa: Allocator,
            scanner: *std.json.Scanner,
            db: ?*const Database,
            item: *vk.VkPipelineShaderStageCreateInfo,
        ) !void {
            _ = sa;
            item.* = .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            };
            while (try scanner_object_next_field(scanner)) |s| {
                if (std.mem.eql(u8, s, "flags")) {
                    const v = try scanner_next_number(scanner);
                    item.flags = try std.fmt.parseInt(u32, v, 10);
                } else if (std.mem.eql(u8, s, "name")) {
                    const name_str = try scanner_next_string(scanner);
                    const name = try aa.dupeZ(u8, name_str);
                    item.pName = @ptrCast(name.ptr);
                } else if (std.mem.eql(u8, s, "module")) {
                    const hash_str = try scanner_next_string(scanner);
                    const hash = try std.fmt.parseInt(u64, hash_str, 16);
                    const shader_modules = db.?.entries.getPtrConst(.SHADER_MODULE);
                    const shader_module = shader_modules.getPtr(hash).?;
                    item.module = @ptrCast(shader_module.handle);
                } else if (std.mem.eql(u8, s, "stage")) {
                    const v = try scanner_next_number(scanner);
                    item.stage = try std.fmt.parseInt(u32, v, 10);
                }
            }
        }
    };

    var scanner = std.json.Scanner.initCompleteInput(tmp_alloc, json_str);
    const vk_graphics_pipeline_create_info = try alloc.create(vk.VkGraphicsPipelineCreateInfo);
    vk_graphics_pipeline_create_info.* = .{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    };

    var result: ParsedGraphicsPipeline = .{
        .version = 0,
        .hash = 0,
        .graphics_pipeline_create_info = vk_graphics_pipeline_create_info,
    };

    while (try scanner_object_next_field(&scanner)) |s| {
        if (std.mem.eql(u8, s, "version")) {
            const v = try scanner_next_number(&scanner);
            result.version = try std.fmt.parseInt(u32, v, 10);
        } else if (std.mem.eql(u8, s, "graphicsPipelines")) {
            if (try scanner.next() != .object_begin) return error.InvalidJson;
            const ss = try scanner_next_string(&scanner);
            result.hash = try std.fmt.parseInt(u64, ss, 16);
            if (try scanner.next() != .object_begin) return error.InvalidJson;
            try Inner.parse_gp(
                alloc,
                tmp_alloc,
                &scanner,
                vk_graphics_pipeline_create_info,
                database,
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

    const parsed_graphics_pipeline = try parse_graphics_pipeline(alloc, tmp_alloc, json, &db);
    print_vk_struct(parsed_graphics_pipeline.graphics_pipeline_create_info);
}
