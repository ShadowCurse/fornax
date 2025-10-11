const std = @import("std");
const Allocator = std.mem.Allocator;

const physical_device_features = @import("physical_device_features_gen.zig");
const vulkan_utils = @import("vulkan_utils_gen.zig");

pub const NOTE =
    \\// Copyright (c) 2025 Egor Lazarchuk
    \\// SPDX-License-Identifier: MIT
    \\//
    \\
;

const REPLACEMENTS: []const struct { []const u8, []const u8 } = &.{
    .{ "SM", "SM" },
    .{ "2D", "2D" },
    .{ "3D", "3D" },
    .{ "Int8", "INT8" },
    .{ "Int16", "INT16" },
    .{ "Int64", "INT64" },
    .{ "Bfloat16", "BFLOAT16" },
    .{ "Float2", "FLOAT_2" },
    .{ "Float8", "FLOAT8" },
    .{ "Float16", "FLOAT16" },
    .{ "Functions2", "FUNCTIONS_2" },
    .{ "8Bit", "8BIT" },
    .{ "16Bit", "16BIT" },
};

pub fn replace_beginning(
    alloc: Allocator,
    n: *[]const u8,
    result: *std.ArrayListUnmanaged(u8),
) !bool {
    for (REPLACEMENTS) |r| {
        const search, const replace = r;
        if (std.mem.startsWith(u8, n.*, search)) {
            try result.appendSlice(alloc, replace);
            n.* = n.*[search.len..];
            return true;
        }
    }
    return false;
}

const ENDINGS: []const []const u8 = &.{
    "ANDROID",
    "FUCHSIA",
    "HUAWEI",
    "INTEL",
    "VALVE",
    "MESA",
    "QCOM",
    "KHR",
    "EXT",
    "ARM",
    "NV",
};

pub fn replace_ending(
    alloc: Allocator,
    n: []const u8,
    result: *std.ArrayListUnmanaged(u8),
) !bool {
    inline for (ENDINGS) |end| {
        if (std.mem.startsWith(u8, n, end)) {
            try result.appendSlice(alloc, end);
            return true;
        }
    }
    return false;
}

pub fn format_name(
    alloc: Allocator,
    name: []const u8,
    comptime upper: bool,
) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    var n: []const u8 = name;
    if (!try replace_beginning(alloc, &n, &result)) {
        try result.append(alloc, n[0]);
        n = n[1..];
    }
    while (n.len != 0) {
        if (std.ascii.isDigit(n[0]))
            try result.append(alloc, '_');
        if (std.ascii.isUpper(n[0]))
            try result.append(alloc, '_');
        if (try replace_beginning(alloc, &n, &result))
            continue;
        if (try replace_ending(alloc, n, &result))
            break;
        try result.append(alloc, n[0]);
        n = n[1..];
    }

    const conversion_fn = if (upper) std.ascii.toUpper else std.ascii.toLower;
    for (result.items) |*r|
        r.* = conversion_fn(r.*);

    return result.items;
}

pub fn get_provider(type_name: []const u8) []const u8 {
    var e: u32 = 0;
    for (0..type_name.len) |i| {
        const index = type_name.len - i - 1;
        if (std.ascii.isUpper(type_name[index]))
            e += 1
        else
            break;
    }
    var provider = type_name[type_name.len - e ..];
    if (provider.len == 0)
        provider = "KHR";
    return provider;
}

pub fn get_extension(alloc: Allocator, type_name: []const u8) ![]const u8 {
    var provider = get_provider(type_name);

    const n = type_name["VkPhysicalDevice".len..];
    const i = std.mem.indexOf(u8, n, "Features") orelse @panic("No `Features` in struct name");
    const s = n[0..i];

    var upper = try format_name(alloc, s, true);
    if (std.mem.eql(u8, upper, "TENSOR"))
        upper = "TENSORS";
    if (std.mem.eql(u8, upper, "DESCRIPTOR_INDEXING"))
        provider = "EXT";
    const result = std.fmt.allocPrint(alloc, "VK_{s}_{s}_EXTENSION_NAME", .{ provider, upper });
    return result;
}

pub fn get_field_name(alloc: Allocator, type_name: []const u8) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    try result.append(alloc, std.ascii.toLower(type_name[2]));
    for (type_name[3..]) |c| {
        if (std.ascii.isUpper(c))
            try result.append(alloc, '_');
        try result.append(alloc, std.ascii.toLower(c));
    }
    return result.items;
}

pub fn get_stype(alloc: Allocator, type_name: []const u8) ![]const u8 {
    const upper = try format_name(alloc, type_name["Vk".len..], true);
    const result = std.fmt.allocPrint(alloc, "VK_STRUCTURE_TYPE_{s}", .{upper});
    return result;
}

const TYPE_PARTS_REPLACEMENTS: []const struct { []const u8, []const u8 } = &.{
    .{ "ID", "ID" },
    .{ "2D", "2D" },
    .{ "3D", "3D" },
    .{ "8BIT", "8Bit" },
    .{ "16BIT", "16Bit" },
    .{ "ASTC", "ASTC" },
    .{ "HDR", "HDR" },
    .{ "KHR", "KHR" },
    .{ "EXT", "EXT" },
    .{ "VALVE", "VALVE" },
    .{ "LUNARG", "LUNARG" },
    .{ "ARM", "ARM" },
    .{ "QCOM", "QCOM" },
    .{ "INTEL", "INTEL" },
    .{ "AMD", "AMD" },
    .{ "QNX", "QNX" },
    .{ "NV", "NV" },
    .{ "NVX", "NVX" },
    .{ "LOD", "LOD" },
    .{ "GGP", "GGP" },
    .{ "NN", "NN" },
    .{ "IMG", "IMG" },
    .{ "MVK", "MVK" },
    .{ "SM", "SM" },
    .{ "AABB", "AABB" },
    .{ "PCI", "PCI" },
    .{ "RGBA10X6", "RGBA10X6" },
    .{ "RDMA", "RDMA" },
    .{ "SEC", "SEC" },
    .{ "AV1", "AV1" },
    .{ "VP9", "VP9" },
    .{ "MSFT", "MSFT" },
    .{ "MESA", "MESA" },
};
fn replace_type_part(part: []const u8) ?[]const u8 {
    for (TYPE_PARTS_REPLACEMENTS) |r| {
        const search, const replace = r;
        if (std.mem.eql(u8, part, search))
            return replace;
    }
    return null;
}
pub fn get_type(alloc: Allocator, stype: []const u8) ![]const u8 {
    const n = stype["VK_STRUCTURE_TYPE_".len..];
    var result: std.ArrayListUnmanaged(u8) = .empty;
    try result.appendSlice(alloc, "Vk");
    var iter = std.mem.splitScalar(u8, n, '_');
    var position: u32 = 0;
    while (iter.next()) |part| : (position += 1) {
        if (position != 0) {
            if (replace_type_part(part)) |r|
                try result.appendSlice(alloc, r)
            else {
                try result.append(alloc, part[0]);
                for (part[1..]) |*c|
                    try result.append(alloc, std.ascii.toLower(c.*));
            }
        } else {
            try result.append(alloc, part[0]);
            for (part[1..]) |*c|
                try result.append(alloc, std.ascii.toLower(c.*));
        }
    }
    return result.items;
}

pub fn main() !void {
    try physical_device_features.gen();
    try vulkan_utils.gen();
}

comptime {
    _ = @import("xml.zig");
    _ = @import("vulkan_parsing.zig");
}
