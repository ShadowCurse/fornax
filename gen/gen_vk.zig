const std = @import("std");
const Allocator = std.mem.Allocator;
const XmlParser = @import("xml_parser.zig");
const XmlDatabase = @import("vk_database.zig").XmlDatabase;
const TypeDatabase = @import("vk_database.zig").TypeDatabase;

const IN_PATH = "thirdparty/vulkan-object/src/vulkan_object/vk.xml";
const OUT_PATH = "src/vk.zig";

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const xml_file = try std.fs.cwd().openFile(IN_PATH, .{});
    const buffer = try alloc.alloc(u8, (try xml_file.stat()).size);
    _ = try xml_file.readAll(buffer);

    const xml_db: XmlDatabase = try .init(alloc, buffer);
    var type_db: TypeDatabase = try .from_xml_database(alloc, &xml_db);

    std.fs.cwd().deleteFile(OUT_PATH) catch {};
    const file = try std.fs.cwd().createFile(OUT_PATH, .{});
    defer file.close();

    var tmp_arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const tmp_alloc = tmp_arena.allocator();
    write_constants(tmp_alloc, file, &xml_db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_basetypes(tmp_alloc, file, &xml_db, &type_db);
    _ = tmp_arena.reset(.retain_capacity);
    write_versions(tmp_alloc, file);
    _ = tmp_arena.reset(.retain_capacity);
    write_handles(tmp_alloc, file, &xml_db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_bitfields(tmp_alloc, file, &type_db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_enums(tmp_alloc, file, &type_db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_structs(tmp_alloc, file, &type_db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_unions(tmp_alloc, file, &xml_db, &type_db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_funtions(tmp_alloc, file, &type_db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_commands(tmp_alloc, file, &xml_db, &type_db);
    _ = tmp_arena.reset(.retain_capacity);
    write_extensions(tmp_alloc, file, &xml_db);
    _ = tmp_arena.reset(.retain_capacity);
    write_unknown_types(tmp_alloc, file, &type_db);
}

const Writer = struct {
    alloc: Allocator,
    file: std.fs.File,

    const Self = @This();

    fn write(self: *Self, comptime fmt: []const u8, args: anytype) void {
        const line = std.fmt.allocPrint(self.alloc, fmt, args) catch |e| {
            std.log.err("Err: {t}", .{e});
            unreachable;
        };
        _ = self.file.write(line) catch |e| {
            std.log.err("Err: {t}", .{e});
            unreachable;
        };
    }

    fn write_comment(self: *Self, comment: []const u8, line_start: []const u8) void {
        var iter = std.mem.splitScalar(u8, comment, '\n');
        while (iter.next()) |line| {
            const trimmed_line = std.mem.trimStart(u8, line, " ");
            if (trimmed_line.len == 0) break;

            _ = self.file.write(line_start) catch |e| {
                std.log.err("Err: {t}", .{e});
                unreachable;
            };
            _ = self.file.write(trimmed_line) catch |e| {
                std.log.err("Err: {t}", .{e});
                unreachable;
            };
            _ = self.file.write("\n") catch |e| {
                std.log.err("Err: {t}", .{e});
                unreachable;
            };
        }
    }
};

fn write_constants(alloc: Allocator, file: std.fs.File, xml_db: *const XmlDatabase) void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\// Constants
        \\
    , .{});
    for (xml_db.constants.items) |*c| {
        switch (c.value) {
            .invalid => {},
            .u32 => |v| w.write("pub const {s}: u32 = {d};\n", .{ c.name, v }),
            .u64 => |v| w.write("pub const {s}: u64 = {d};\n", .{ c.name, v }),
            .f32 => |v| w.write("pub const {s}: f32 = {d};\n", .{ c.name, v }),
        }
    }
}

fn write_basetypes(
    alloc: Allocator,
    file: std.fs.File,
    xml_db: *const XmlDatabase,
    type_db: *TypeDatabase,
) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Base types
        \\
    , .{});
    for (xml_db.types.basetypes) |*v| {
        const type_idx = try type_db.resolve_base(v.name);
        const type_str = try type_db.type_string(alloc, type_idx);
        w.write("pub const {s} = {s};\n", .{ v.name, type_str });
    }
}

fn write_versions(alloc: Allocator, file: std.fs.File) void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\// Versions
        \\pub const ApiVersion = packed struct(u32) {{
        \\    patch: u12 = 0,
        \\    minor: u10 = 0,
        \\    major: u7 = 0,
        \\    variant: u3 = 0,
        \\}};
        \\pub const Version = packed struct(u32) {{
        \\    patch: u12 = 0,
        \\    minor: u10 = 0,
        \\    major: u10 = 0,
        \\}};
        \\pub const VK_API_VERSION_1_0: ApiVersion = .{{
        \\    .variant = 0,
        \\    .major = 1,
        \\    .minor = 0,
        \\    .patch = 0,
        \\}};
        \\pub const VK_API_VERSION_1_1: ApiVersion = .{{
        \\    .variant = 0,
        \\    .major = 1,
        \\    .minor = 1,
        \\    .patch = 0,
        \\}};
        \\pub const VK_API_VERSION_1_2: ApiVersion = .{{
        \\    .variant = 0,
        \\    .major = 1,
        \\    .minor = 2,
        \\    .patch = 0,
        \\}};
        \\pub const VK_API_VERSION_1_3: ApiVersion = .{{
        \\    .variant = 0,
        \\    .major = 1,
        \\    .minor = 3,
        \\    .patch = 0,
        \\}};
        \\pub const VK_API_VERSION_1_4: ApiVersion = .{{
        \\    .variant = 0,
        \\    .major = 1,
        \\    .minor = 4,
        \\    .patch = 0,
        \\}};
        \\
    , .{});
}

fn write_handles(alloc: Allocator, file: std.fs.File, xml_db: *const XmlDatabase) void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Handles
        \\
    , .{});
    for (xml_db.types.handles) |*v| {
        if (v.alias) |s| {
            w.write(
                \\pub const {s} = {s};
                \\
            , .{ v.name, s });
        } else {
            if (v.objtypeenum) |s| w.write(
                \\// Type enum: {s}
                \\
            , .{s});

            if (v.parent) |s| w.write(
                \\// Parent: {s}
                \\
            , .{s});
            w.write(
                \\pub const {s} = enum(u64) {{ none = 0, _ }};
                \\
            , .{v.name});
        }
    }
}

fn write_bitfields(alloc: Allocator, file: std.fs.File, type_db: *const TypeDatabase) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Empty bitmasks
        \\
    , .{});

    for (type_db.bitfields.items) |bitfield| {
        w.write(
            \\pub const {s} = packed struct(u{d}) {{
            \\
        , .{ bitfield.name, bitfield.backing_integer_width });

        var last_bitpos: ?u32 = null;
        for (bitfield.bits, 0..) |bit, i| {
            if (last_bitpos) |lb| {
                const diff = bit.bit - lb;
                if (1 < diff) w.write(
                    \\    _{d}: u{d} = 0,
                    \\
                , .{ lb, diff - 1 });
            } else {
                if (bit.bit != 0) w.write(
                    \\    _0: u{d} = 0,
                    \\
                , .{bit.bit});
            }
            last_bitpos = bit.bit;

            if (bit.enabled_by_extension) |e| w.write(
                \\    // Extension: {s}
                \\
            , .{e});

            // Some extensions add same bits, so check consecutive bits
            if (i < bitfield.bits.len - 1) {
                if (bit.bit == bitfield.bits[i + 1].bit) {
                    continue;
                }
            }

            if (bit.comment) |c| w.write(
                \\    // Comment: {s}
                \\
            , .{c});

            // TODO: lowercase names without prefix
            w.write(
                \\    // bit: {d}
                \\    {s}: bool = false,
                \\
            , .{ bit.bit, bit.name });
        }
        if (last_bitpos) |lb| {
            const last_element_width = bitfield.backing_integer_width - lb - 1;
            if (last_element_width != 0) w.write(
                \\    _: u{d} = 0,
                \\
            , .{last_element_width});
        } else {
            w.write(
                \\    _: u{d} = 0,
                \\
            , .{bitfield.backing_integer_width});
        }

        // all constants
        for (bitfield.constants) |constant| {
            if (constant.comment) |c| w.write(
                \\    // {s}
                \\
            , .{c});
            // TODO: lowercase names without prefix
            w.write(
                \\    pub const {s}: @This() = @bitCast(@as(u{d}, 0x{x}));
                \\
            , .{ constant.name, bitfield.backing_integer_width, constant.value });
        }
        // NOTE: Bitmasks do not have expandable constants
        w.write(
            \\}};
            \\
        , .{});
    }
}

fn write_enums(
    alloc: Allocator,
    file: std.fs.File,
    type_db: *const TypeDatabase,
) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Enums
        \\
    , .{});
    for (type_db.enums.items) |@"enum"| {
        w.write(
            \\pub const {s} = enum(i{d}) {{
            \\
        , .{ @"enum".name, @"enum".backing_integer_width });
        for (@"enum".values, 0..) |value, i| {
            if (value.enabled_by_extension) |e| w.write(
                \\    // Extension: {s}
                \\
            , .{e});

            // Some extensions add same enum values, so check consecutive bits
            if (i < @"enum".values.len - 1) {
                if (value.value == @"enum".values[i + 1].value) continue;
            }

            if (value.comment) |c| w.write(
                \\    // Comment: {s}
                \\
            , .{c});

            w.write(
                \\    {s} = {d},
                \\
            , .{ value.name, value.value });
        }

        w.write(
            \\    pub const zero = @import("std").mem.zeroes(@This());
            \\}};
            \\
        , .{});
    }
}

const ADDITIONAL_FUNCTIONS = [_]XmlDatabase.Command{
    .{
        .name = "vkInternalAllocationNotification",
        .return_type = "void",
        .parameters = &.{
            .{ .name = "pUserData", .type_middle = "void", .type_back = "*" },
            .{ .name = "size", .type_middle = "size_t" },
            .{ .name = "allocationType", .type_middle = "VkInternalAllocationType" },
            .{ .name = "allocationScope", .type_middle = "VkSystemAllocationScope" },
        },
    },
    .{
        .name = "vkInternalFreeNotification",
        .return_type = "void",
        .parameters = &.{
            .{ .name = "pUserData", .type_middle = "void", .type_back = "*" },
            .{ .name = "size", .type_middle = "size_t" },
            .{ .name = "allocationType", .type_middle = "VkInternalAllocationType" },
            .{ .name = "allocationScope", .type_middle = "VkSystemAllocationScope" },
        },
    },
    .{
        .name = "vkReallocationFunction",
        .return_type = "[*]u8",
        .parameters = &.{
            .{ .name = "pUserData", .type_middle = "void", .type_back = "*" },
            .{ .name = "pOriginal", .type_middle = "void", .type_back = "*" },
            .{ .name = "size", .type_middle = "size_t" },
            .{ .name = "alignment", .type_middle = "size_t" },
            .{ .name = "allocationScope", .type_middle = "VkSystemAllocationScope" },
        },
    },
    .{
        .name = "vkAllocationFunction",
        .return_type = "[*]u8",
        .parameters = &.{
            .{ .name = "pUserData", .type_middle = "void", .type_back = "*" },
            .{ .name = "size", .type_middle = "size_t" },
            .{ .name = "alignment", .type_middle = "size_t" },
            .{ .name = "allocationScope", .type_middle = "VkSystemAllocationScope" },
        },
    },
    .{
        .name = "vkFreeFunction",
        .return_type = "void",
        .parameters = &.{
            .{ .name = "pUserData", .type_middle = "void", .type_back = "*" },
            .{ .name = "pMemory", .type_middle = "void", .type_back = "*" },
        },
    },
    .{
        .name = "vkVoidFunction",
        .return_type = "void",
        .parameters = &.{
            .{ .name = "pUserData", .type_middle = "void", .type_back = "*" },
            .{ .name = "pMemory", .type_middle = "void", .type_back = "*" },
        },
    },
    .{
        .name = "vkDebugReportCallbackEXT",
        .return_type = "VkBool32",
        .parameters = &.{
            .{ .name = "flags", .type_middle = "VkDebugReportFlagsEXT" },
            .{ .name = "objectType", .type_middle = "VkDebugReportObjectTypeEXT" },
            .{ .name = "object", .type_middle = "uint64_t" },
            .{ .name = "location", .type_middle = "size_t" },
            .{ .name = "messageCode", .type_middle = "int32_t" },
            .{
                .name = "pLayerPrefix",
                .type_front = "const",
                .type_middle = "char",
                .type_back = "*",
            },
            .{
                .name = "pMessage",
                .type_front = "const",
                .type_middle = "char",
                .type_back = "*",
            },
            .{
                .name = "pUserData",
                .type_middle = "void",
                .type_back = "*",
            },
        },
    },
    .{
        .name = "vkDebugUtilsMessengerCallbackEXT",
        .return_type = "VkBool32",
        .parameters = &.{
            .{ .name = "messageSeverity", .type_middle = "VkDebugUtilsMessageSeverityFlagBitsEXT" },
            .{ .name = "messageTypes", .type_middle = "VkDebugUtilsMessageTypeFlagsEXT" },
            .{
                .name = "pCallbackData",
                .type_front = "const",
                .type_middle = "VkDebugUtilsMessengerCallbackDataEXT",
                .type_back = "*",
            },
            .{ .name = "pUserData", .type_middle = "void", .type_back = "*" },
        },
    },
    .{
        .name = "vkFaultCallbackFunction",
        .return_type = "void",
        .parameters = &.{
            .{ .name = "unrecordedFaults", .type_middle = "VkBool32" },
            .{ .name = "faultCount", .type_middle = "uint32_t" },
            .{
                .name = "pFaults",
                .type_front = "const",
                .type_middle = "void",
                .type_back = "*",
            },
        },
    },
    .{
        .name = "vkDeviceMemoryReportCallbackEXT",
        .return_type = "void",
        .parameters = &.{
            .{
                .name = "pCallbackData",
                .type_front = "const",
                .type_middle = "VkDeviceMemoryReportCallbackDataEXT",
                .type_back = "*",
            },
            .{
                .name = "pUserData",
                .type_front = "const",
                .type_middle = "void",
                .type_back = "*",
            },
        },
    },
    .{
        .name = "vkGetInstanceProcAddrLUNARG",
        .return_type = "PFN_vkVoidFunction",
        .parameters = &.{
            .{ .name = "instance", .type_middle = "VkInstance" },
            .{
                .name = "pName",
                .type_front = "const",
                .type_middle = "char",
                .type_back = "*",
            },
        },
    },
};

// TODO: funcpointers are encoded "horribly" in the xml, so save sanity by
// hardcoding this
fn write_funtions(alloc: Allocator, file: std.fs.File, type_db: *TypeDatabase) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Functions
        \\
    , .{});

    for (&ADDITIONAL_FUNCTIONS) |*f|
        try write_command(alloc, type_db, &w, f);
}

fn write_structs(alloc: Allocator, file: std.fs.File, type_db: *TypeDatabase) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Structs
        \\
    , .{});

    for (type_db.structs.items) |@"struct"| {
        if (@"struct".enabled_by_extension) |ext| w.write(
            \\// Extension: {s}
            \\
        , .{ext});

        if (@"struct".alias) |c| {
            w.write(
                \\pub const {s} = {s};
                \\
            , .{ @"struct".name, c });
        } else {
            if (@"struct".comment) |c| w.write(
                \\// Comment: {s}
                \\
            , .{c});

            if (@"struct".extends.len != 0) {
                w.write(
                    \\// Extends: 
                , .{});
                for (@"struct".extends, 0..) |e, i| {
                    const t = type_db.get_type(e);
                    const s = type_db.get_struct(t.struct_idx());
                    w.write(
                        \\{s}
                    , .{s.name});
                    if (i != @"struct".extends.len - 1) {
                        w.write(
                            \\,
                        , .{});
                    }
                }
                w.write(
                    \\
                    \\
                , .{});
            }
            w.write(
                \\// Returned only: {}
                \\// Allow duplicate in pNext chain: {}
                \\pub const {s} = extern struct {{
                \\
            , .{ @"struct".returnedonly, @"struct".allowduplicate, @"struct".name });

            var packed_field_idx: u8 = 0;
            for (@"struct".fields) |f| {
                switch (f) {
                    .single_field => |field| {
                        if (field.len_expression) |len| w.write(
                            \\    // Length field: {s}
                            \\
                        , .{len});
                        if (field.stride) |stride| w.write(
                            \\    // Stride field: {s}
                            \\
                        , .{stride});
                        if (field.deprecated) |deprecated| w.write(
                            \\    // Deprecated: {s}
                            \\
                        , .{deprecated});
                        w.write(
                            \\    // Extern sync: {}
                            \\    // Optional: {}
                            \\
                        , .{ field.externsync, field.optional });
                        if (field.selector) |selector| w.write(
                            \\    // Selector field: {s} (What union field is valid)
                            \\
                        , .{selector});
                        if (field.objecttype) |objecttype| w.write(
                            \\    // Object type: {s} (Which object handle is this)
                            \\
                        , .{objecttype});
                        if (field.featurelink) |featurelink| w.write(
                            \\    // Feature link: {s}
                            \\
                        , .{featurelink});
                        if (field.comment) |comment| w.write(
                            \\    // Comment: {s}
                            \\
                        , .{comment});

                        try write_single_struct_field(
                            alloc,
                            type_db,
                            &w,
                            @"struct".name,
                            &field,
                            field.type_idx,
                        );
                    },
                    .packed_field => |field| {
                        w.write(
                            \\    packed_field{d}: packed struct(u{d}) {{
                            \\
                        , .{ packed_field_idx, field.backing_integer_width });
                        for (field.parts) |part| {
                            w.write(
                                \\        {s}: u{d} = 0,
                                \\
                            , .{ part.name, part.bits });
                        }
                        w.write(
                            \\    }} = .{{}},
                            \\
                        , .{});
                        packed_field_idx += 1;
                    },
                }
            }
            w.write(
                \\}};
                \\
            , .{});
        }
    }
}

fn write_single_struct_field(
    alloc: Allocator,
    type_db: *const TypeDatabase,
    w: *Writer,
    struct_name: []const u8,
    field: *const TypeDatabase.Struct.SingleField,
    type_idx: TypeDatabase.Type.Idx,
) !void {
    const t = type_db.get_type(type_idx);
    const type_str = try type_db.type_string(alloc, type_idx);
    switch (t.*) {
        .base => |base| {
            switch (base) {
                .builtin => |_| {
                    w.write(
                        \\    {s}: {s} = 0,
                        \\
                    , .{ field.name, type_str });
                },
                .handle_idx => |_| {
                    w.write(
                        \\    {s}: {s} = .none,
                        \\
                    , .{ field.name, type_str });
                },
                .struct_idx => |struct_idx| {
                    var should_have_default: bool = true;
                    const s = type_db.get_struct(struct_idx);
                    for (s.fields) |f| {
                        if (f == .single_field) {
                            const tt = type_db.get_type(f.single_field.type_idx);
                            switch (tt.*) {
                                .base => |b| {
                                    switch (b) {
                                        .enum_idx, .union_idx => should_have_default = false,
                                        else => {},
                                    }
                                },
                                else => {},
                            }
                        }
                    }
                    var default_str: []const u8 = &.{};
                    if (should_have_default)
                        default_str = " = .{}";

                    w.write(
                        \\    {s}: {s}{s},
                        \\
                    , .{ field.name, type_str, default_str });
                },
                .bitfield_idx => |_| {
                    w.write(
                        \\    {s}: {s} = .{{}},
                        \\
                    , .{ field.name, type_str });
                },
                .enum_idx => |_| {
                    // Should only be valid for sType: VkStructureType
                    if (field.stype_value) |v| {
                        w.write(
                            \\    {s}: {s} = VkStructureType.{s},
                            \\
                        , .{ field.name, type_str, v });
                    } else {
                        w.write(
                            \\    {s}: {s},
                            \\
                        , .{ field.name, type_str });
                    }
                },
                .union_idx => |_| {
                    w.write(
                        \\    {s}: {s},
                        \\
                    , .{ field.name, type_str });
                },
                else => {
                    std.log.err(
                        "Cannot determine default value for {s}.{s} with type: {any}",
                        .{ struct_name, field.name, t },
                    );
                },
            }
        },
        .pointer => |_| {
            w.write(
                \\    {s}: ?{s} = null,
                \\
            , .{ field.name, type_str });
        },
        .array => |_| {
            w.write(
                \\    {[name]s}: {[type]s} = @import("std").mem.zeroes({[type]s}),
                \\
            , .{ .name = field.name, .type = type_str });
        },
        .alias => |alias| {
            try write_single_struct_field(alloc, type_db, w, struct_name, field, alias.type_idx);
        },
        .placeholder => |placeholder| {
            std.log.err(
                "Cannot determine default value for {s}.{s} with type: {any} found placeholder for {s}",
                .{ struct_name, field.name, t, placeholder },
            );
        },
        else => unreachable,
    }
}

fn write_unions(
    alloc: Allocator,
    file: std.fs.File,
    xml_db: *const XmlDatabase,
    type_db: *TypeDatabase,
) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Unions
        \\
    , .{});

    for (xml_db.types.unions) |un| {
        for (xml_db.features.items) |ext| {
            if (ext.unlocks_type(un.name)) w.write(
                \\// Extension: {s}
                \\
            , .{ext.name});
        }
        for (xml_db.extensions.items) |ext| {
            if (ext.unlocks_type(un.name)) w.write(
                \\// Extension: {s}
                \\
            , .{ext.name});
        }

        if (un.alias) |c| {
            w.write(
                \\pub const {s} = {s};
                \\
            , .{ un.name, c });
        } else {
            if (un.comment) |c| w.write(
                \\// Comment: {s}
                \\
            , .{c});

            w.write(
                \\pub const {s} = extern union {{
                \\
            , .{un.name});

            for (un.members) |member| {
                if (member.selection) |selection| w.write(
                    \\    // Selected with: {s}
                    \\
                , .{selection});

                const type_idx = try type_db.c_type_parts_to_type(
                    member.type_front,
                    member.type_middle,
                    member.type_back,
                    member.dimensions,
                    member.len,
                    false,
                );
                const type_str = try type_db.type_string(alloc, type_idx);
                w.write(
                    \\    {s}: {s},
                    \\
                , .{ member.name, type_str });
            }

            w.write(
                \\}};
                \\
            , .{});
        }
    }
}

fn write_command(
    alloc: Allocator,
    type_db: *TypeDatabase,
    w: *Writer,
    command: *const XmlDatabase.Command,
) !void {
    if (command.alias) |c| {
        w.write(
            \\pub const {s} = {s};
            \\
        , .{ command.name, c });
    } else {
        if (command.queues) |c| w.write(
            \\// Queues: {s}
            \\
        , .{c});
        if (command.successcodes) |c| w.write(
            \\// Success codes: {s}
            \\
        , .{c});
        if (command.errorcodes) |c| w.write(
            \\// Error codes: {s}
            \\
        , .{c});
        if (command.renderpass) |c| w.write(
            \\// Render pass: {s}
            \\
        , .{c});
        if (command.videocoding) |c| w.write(
            \\// Video conding: {s}
            \\
        , .{c});
        if (command.cmdbufferlevel) |c| w.write(
            \\// Command buffer levels: {s}
            \\
        , .{c});
        if (command.conditionalrendering) |c| w.write(
            \\// Conditional rendering: {}
            \\
        , .{c});
        w.write(
            \\// Can be used without queues: {}
            \\
        , .{command.allownoqueues});
        if (command.comment) |c| w.write(
            \\// Comment: {s}
            \\
        , .{c});

        w.write(
            \\pub const {s} = fn (
            \\
        , .{command.name});
        for (command.parameters) |parameter| {
            if (parameter.len) |l| w.write(
                \\    // len: {s}
                \\
            , .{l});
            if (parameter.valid_structs) |vs| w.write(
                \\    // valid structs: {s}
                \\
            , .{vs});

            const type_idx = try type_db.c_type_parts_to_type(
                parameter.type_front,
                parameter.type_middle,
                parameter.type_back,
                parameter.dimensions,
                parameter.len,
                true,
            );

            var is_handle: bool = false;
            const t = type_db.get_type(type_idx);
            switch (t.*) {
                .base => |base| switch (base) {
                    .handle_idx => |_| is_handle = true,
                    else => {},
                },
                else => {},
            }

            const type_str = try type_db.type_string(alloc, type_idx);
            var optional_str: []const u8 = &.{};
            if (parameter.optional and !is_handle)
                optional_str = "?";
            w.write(
                \\    {s}: {s}{s},
                \\
            , .{ parameter.name, optional_str, type_str });
        }

        const return_type_idx = try type_db.resolve_base(command.return_type);
        var is_pointer: bool = false;
        const t = type_db.get_type(return_type_idx);
        switch (t.*) {
            .pointer => |_| is_pointer = true,
            else => {},
        }
        const type_str = try type_db.type_string(alloc, return_type_idx);
        var optional_str: []const u8 = &.{};
        if (is_pointer)
            optional_str = "?";
        w.write(
            \\) callconv(.c) {s}{s};
            \\
        , .{ optional_str, type_str });
    }
}

fn write_commands(
    alloc: Allocator,
    file: std.fs.File,
    xml_db: *const XmlDatabase,
    type_db: *TypeDatabase,
) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Commands
        \\
    , .{});

    var visited: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (xml_db.commands.items) |*command| {
        if (visited.get(command.name) != null) continue;
        try visited.put(alloc, command.name, {});

        for (xml_db.features.items) |ext| {
            if (ext.unlocks_type(ext.name)) w.write(
                \\// Extension: {s}
                \\
            , .{ext.name});
        }
        for (xml_db.extensions.items) |ext| {
            if (ext.unlocks_command(command.name)) w.write(
                \\// Extension: {s}
                \\
            , .{ext.name});
        }
        try write_command(alloc, type_db, &w, command);
    }
}

fn write_extensions(alloc: Allocator, file: std.fs.File, db: *const XmlDatabase) void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Extensions
        \\
    , .{});
    for (db.extensions.items) |ext| {
        w.write(
            \\// Extension: {s}
            \\// Number: {s}
            \\// Type: {t}
            \\
        , .{
            ext.name,
            ext.number,
            ext.type,
        });
        if (ext.author) |v| w.write(
            \\// Author: {s}
            \\
        , .{v});
        if (ext.depends) |v| w.write(
            \\// Depends: {s}
            \\
        , .{v});
        if (ext.platform) |v| w.write(
            \\// Platform: {s}
            \\
        , .{v});
        w.write(
            \\// Supported: {t}
            \\
        , .{ext.supported});
        if (ext.promotedto) |v| w.write(
            \\// Promoted to: {s}
            \\
        , .{v});
        if (ext.deprecatedby) |v| w.write(
            \\// Deprecated by: {s}
            \\
        , .{v});
        if (ext.obsoletedby) |v| w.write(
            \\// Obsoleted by: {s}
            \\
        , .{v});
        if (ext.comment) |v| {
            w.write(
                \\// Comment:
                \\
            , .{});
            w.write_comment(v, "//     ");
        }
        w.write(
            \\// Unlocks:
            \\
        , .{});

        for (ext.require) |require| {
            if (require.depends) |v| w.write(
                \\//     Depends: {s}
                \\
            , .{v});
            for (require.items) |i| {
                switch (i) {
                    .comment => |v| {
                        w.write(
                            \\//         Comment:
                            \\
                        , .{});
                        w.write_comment(v, "//             ");
                    },
                    .command => |v| {
                        w.write(
                            \\//         Command:
                            \\//             Name: {s}
                            \\
                        , .{v.name});
                        if (v.comment) |vv| {
                            w.write(
                                \\//             Comment:
                                \\
                            , .{});
                            w.write_comment(vv, "//                 ");
                        }
                    },
                    .@"enum" => |v| {
                        w.write(
                            \\//         Enum:
                            \\//             Name: {s}
                            \\//             Negative: {}
                            \\
                        , .{
                            v.name,
                            v.negative[0],
                        });
                        if (v.value) |vv| w.write(
                            \\//             Value: {s}
                            \\
                        , .{vv});
                        if (v.bitpos) |vv| w.write(
                            \\//             Bitpos: {d}
                            \\
                        , .{vv});
                        if (v.extends) |vv| w.write(
                            \\//             Extends: {s}
                            \\
                        , .{vv});
                        if (v.extnumber) |vv| w.write(
                            \\//             Extnumber: {d}
                            \\
                        , .{vv});
                        if (v.offset) |vv| w.write(
                            \\//             Offset: {d}
                            \\
                        , .{vv});
                        if (v.alias) |vv| w.write(
                            \\//             Alias: {s}
                            \\
                        , .{vv});
                        if (v.comment) |vv| {
                            w.write(
                                \\//             Comment:
                                \\
                            , .{});
                            w.write_comment(vv, "//                 ");
                        }
                    },
                    .type => |v| w.write(
                        \\//         Type:
                        \\//             Name: {s}
                        \\
                    , .{v.name}),
                    .feature => |v| {
                        w.write(
                            \\//         Feature:
                            \\//             Name: {s}
                            \\
                        , .{v.name});
                        if (v.@"struct") |vv| w.write(
                            \\//             Struct: {s}
                            \\
                        , .{vv});
                        if (v.comment) |vv| {
                            w.write(
                                \\//             Comment:
                                \\
                            , .{});
                            w.write_comment(vv, "//                 ");
                        }
                    },
                }
            }
        }
    }
}

fn write_unknown_types(alloc: Allocator, file: std.fs.File, type_db: *const TypeDatabase) void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Unknown types
        \\
    , .{});
    for (type_db.types.items) |t| {
        switch (t) {
            .placeholder => |name| {
                w.write(
                    \\pub const {[name]s} = if (@hasDecl(@import("root"), "{[name]s}")) @import("root").{[name]s} else @compileError("Unknown type: {{{[name]s}}}");
                    \\
                , .{ .name = name });
            },
            else => {},
        }
    }
}

pub fn enum_offset(extension_number: i32, offset: i32) i32 {
    const BASE = 1000000000;
    const RANGE = 1000;
    const result = BASE + (extension_number - 1) * RANGE + offset;
    return result;
}

comptime {
    _ = @import("vk_database.zig");
    _ = @import("vk_database.zig").XmlDatabase;
}
