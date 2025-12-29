const std = @import("std");
const Allocator = std.mem.Allocator;
const XmlParser = @import("xml_parser.zig");
const Database = @import("vk_database.zig");
const PATH = "gen/vk.zig";

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const xml_file = try std.fs.cwd().openFile(
        "thirdparty/vulkan-object/src/vulkan_object/vk.xml",
        .{},
    );
    const buffer = try alloc.alloc(u8, (try xml_file.stat()).size);
    _ = try xml_file.readAll(buffer);

    const db: Database = try .init(alloc, buffer);

    std.fs.cwd().deleteFile(PATH) catch {};
    const file = try std.fs.cwd().createFile(PATH, .{});
    defer file.close();

    var type_map: TypeMap = .{ .alloc = alloc };
    try fill_type_map(&type_map, &db);

    var tmp_arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const tmp_alloc = tmp_arena.allocator();
    write_constants(tmp_alloc, file, &db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_basetypes(tmp_alloc, file, &db, &type_map);
    _ = tmp_arena.reset(.retain_capacity);
    write_handles(tmp_alloc, file, &db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_bitmasks(tmp_alloc, file, &db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_enums(tmp_alloc, file, &db);
    _ = tmp_arena.reset(.retain_capacity);
    try write_funtions(tmp_alloc, file, &type_map);
    _ = tmp_arena.reset(.retain_capacity);
    try write_structs(tmp_alloc, file, &db, &type_map);
    _ = tmp_arena.reset(.retain_capacity);
    try write_unions(tmp_alloc, file, &db, &type_map);
    _ = tmp_arena.reset(.retain_capacity);
    try write_commands(tmp_alloc, file, &db, &type_map);
    _ = tmp_arena.reset(.retain_capacity);
    write_extensions(tmp_alloc, file, &db);
    _ = tmp_arena.reset(.retain_capacity);
    write_unknown_types(tmp_alloc, file, &type_map);
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

fn write_constants(alloc: Allocator, file: std.fs.File, db: *const Database) void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\// Constants
        \\
    , .{});
    for (db.constants.items) |*c| {
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
    db: *const Database,
    type_map: *TypeMap,
) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Base types
        \\
    , .{});
    for (db.types.basetypes) |*v| {
        const t, _ = try resolve_type(type_map, v.type);
        if (v.pointer)
            w.write("pub const {s} = *{s};\n", .{ v.name, t })
        else
            w.write("pub const {s} = {s};\n", .{ v.name, t });
    }
}

fn write_handles(alloc: Allocator, file: std.fs.File, db: *const Database) void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Handles
        \\
    , .{});
    for (db.types.handles) |*v| {
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
                \\pub const {s} = enum(u64) {{ null = 0, _ }};
                \\
            , .{v.name});
        }
    }
}

fn write_bitmasks(alloc: Allocator, file: std.fs.File, db: *const Database) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Empty bitmasks
        \\
    , .{});
    for (db.types.bitmasks) |v| switch (v.value) {
        .type => |t| {
            var bits: u32 = 0;
            if (std.mem.eql(u8, t, "VkFlags"))
                bits = 32;
            if (std.mem.eql(u8, t, "VkFlags64"))
                bits = 64;

            w.write(
                \\const {s} = packed struct(u{d}) {{
                \\    _: {d},
                \\    pub const zero = @import("std").mem.zeroes(@This());
                \\}};
                \\
            , .{ v.name, bits, bits });
        },
        else => {},
    };

    w.write(
        \\
        \\// Bitmasks
        \\
    , .{});
    for (db.types.bitmasks) |v| switch (v.value) {
        .enum_name => |s| {
            if (db.enum_by_name(s)) |e| {
                w.write(
                    \\pub const {s} = packed struct(u{d}) {{
                    \\
                , .{ v.name, e.bitwidth });

                var extensions: std.ArrayListUnmanaged(struct {
                    ext_name: []const u8,
                    items: Database.Extension.EnumExtensions,
                }) = .empty;
                // check if extensions extend this bitmask with new values
                for (db.extensions.items) |ext| {
                    const ex = try ext.enum_extensions(alloc, s);
                    if (ex.items.len != 0) try extensions.append(
                        alloc,
                        .{ .ext_name = ext.name, .items = ex },
                    );
                }

                const Bitpos = struct {
                    bit: u32,
                    name: []const u8,
                    comment: ?[]const u8 = null,
                    ext_name: ?[]const u8 = null,

                    fn less_than(_: void, a: @This(), b: @This()) bool {
                        return a.bit < b.bit;
                    }
                };
                var all_bitpos: std.ArrayListUnmanaged(Bitpos) = .empty;

                for (e.items) |item| {
                    switch (item.value) {
                        .bitpos => |bitpos| {
                            try all_bitpos.append(
                                alloc,
                                .{ .bit = bitpos, .name = item.name, .comment = item.comment },
                            );
                        },
                        else => {},
                    }
                }
                for (extensions.items) |ext| {
                    for (ext.items.items) |item| {
                        switch (item.value) {
                            .bitpos => |bitpos| {
                                try all_bitpos.append(
                                    alloc,
                                    .{ .bit = bitpos, .name = item.name, .ext_name = ext.ext_name },
                                );
                            },
                            else => {},
                        }
                    }
                }
                std.mem.sortUnstable(Bitpos, all_bitpos.items, {}, Bitpos.less_than);

                // all bits
                var last_bitpos: ?u32 = null;
                for (all_bitpos.items, 0..) |bitpos, i| {
                    if (last_bitpos) |lb| {
                        const diff = bitpos.bit - lb;
                        if (1 < diff and lb != 0) w.write(
                            \\    _{d}: u{d},
                            \\
                        , .{ lb, diff - 1 });
                    } else {
                        if (bitpos.bit != 0) w.write(
                            \\    _0: u{d},
                            \\
                        , .{bitpos.bit});
                    }
                    last_bitpos = bitpos.bit;

                    if (bitpos.ext_name) |c| w.write(
                        \\    // Extension: {s}
                        \\
                    , .{c});

                    // Some extensions add same bits, so check consecutive bits
                    if (i < all_bitpos.items.len - 1) {
                        if (bitpos.bit == all_bitpos.items[i + 1].bit) {
                            continue;
                        }
                    }

                    for (extensions.items) |ext| {
                        for (ext.items.items) |item| {
                            switch (item.value) {
                                .alias => |alias| {
                                    if (std.mem.eql(u8, alias, bitpos.name)) w.write(
                                        \\    // Alias: {s}
                                        \\
                                    , .{item.name});
                                },
                                else => {},
                            }
                        }
                    }

                    if (bitpos.comment) |c| w.write(
                        \\    // Comment: {s}
                        \\
                    , .{c});

                    // TODO: lowercase names without prefix
                    w.write(
                        \\    // bit: {d}
                        \\    {s}: bool,
                        \\
                    , .{ bitpos.bit, bitpos.name });
                }
                if (last_bitpos) |lb| {
                    const last_element_width = e.bitwidth - lb - 1;
                    if (last_element_width != 0) w.write(
                        \\    _: u{d},
                        \\
                    , .{last_element_width});
                } else {
                    w.write(
                        \\    _: u{d},
                        \\
                    , .{e.bitwidth});
                }

                // all constants
                for (e.items) |item| {
                    switch (item.value) {
                        .value => |value| {
                            if (item.comment) |c| w.write(
                                \\    // {s}
                                \\
                            , .{c});
                            // TODO: lowercase names without prefix
                            w.write(
                                \\    pub const {s}: @This() = @bitCast(@as(u{d}, 0x{x}));
                                \\
                            , .{ item.name, e.bitwidth, value });
                        },
                        else => {},
                    }
                }
                // NOTE: Bitmasks do not have expandable constants
                w.write(
                    \\    pub const zero = @import("std").mem.zeroes(@This());
                    \\}};
                    \\
                , .{});
            } else {
                std.log.warn(
                    "While writing bitmasks, unable to find corresponding enum with name: {s}",
                    .{s},
                );
            }
        },
        else => {},
    };
}

fn write_enums(alloc: Allocator, file: std.fs.File, db: *const Database) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Enums
        \\
    , .{});
    for (db.enums.items) |e| switch (e.type) {
        .@"enum" => {
            w.write(
                \\pub const {s} = enum(u{d}) {{
                \\
            , .{ e.name, e.bitwidth });

            var extensions: std.ArrayListUnmanaged(struct {
                ext_name: []const u8,
                items: Database.Extension.EnumExtensions,
            }) = .empty;
            // check if extensions extend this enum with new values
            for (db.extensions.items) |ext| {
                const ex = try ext.enum_extensions(alloc, e.name);
                if (ex.items.len != 0) try extensions.append(
                    alloc,
                    .{ .ext_name = ext.name, .items = ex },
                );
            }

            const Value = struct {
                value: i32,
                name: []const u8,
                comment: ?[]const u8 = null,
                ext_name: ?[]const u8 = null,

                fn less_than(_: void, a: @This(), b: @This()) bool {
                    return a.value < b.value;
                }
            };
            var all_values: std.ArrayListUnmanaged(Value) = .empty;

            for (e.items) |item| {
                switch (item.value) {
                    .value => |value| {
                        try all_values.append(
                            alloc,
                            .{ .value = value, .name = item.name, .comment = item.comment },
                        );
                    },
                    else => {},
                }
            }

            for (extensions.items) |ext| {
                for (ext.items.items) |item| {
                    switch (item.value) {
                        .offset => |offset| {
                            var value = enum_offset(
                                @intCast(offset.extnumber),
                                @intCast(offset.offset),
                            );
                            if (offset.negative) value *= -1;
                            try all_values.append(
                                alloc,
                                .{ .value = value, .name = item.name, .ext_name = ext.ext_name },
                            );
                        },
                        else => {},
                    }
                }
            }
            std.mem.sortUnstable(Value, all_values.items, {}, Value.less_than);

            // enum values
            for (all_values.items, 0..) |item, i| {
                if (item.ext_name) |c| w.write(
                    \\    // Extension: {s}
                    \\
                , .{c});

                // Some extensions add same enum values, so check consecutive bits
                if (i < all_values.items.len - 1) {
                    if (item.value == all_values.items[i + 1].value) continue;
                }

                for (extensions.items) |ext2| {
                    for (ext2.items.items) |item2| {
                        switch (item2.value) {
                            .alias => |alias| {
                                if (std.mem.eql(u8, alias, item.name)) w.write(
                                    \\    // Alias: {s}
                                    \\
                                , .{item2.name});
                            },
                            else => {},
                        }
                    }
                }

                if (item.comment) |c| w.write(
                    \\    // Comment: {s}
                    \\
                , .{c});

                // TODO: lowercase names without prefix
                w.write(
                    \\    {s} = {d},
                    \\
                , .{ item.name, item.value });
            }

            w.write(
                \\    pub const zero = @import("std").mem.zeroes(@This());
                \\}};
                \\
            , .{});
        },
        else => {},
    };
}

const ADDITIONAL_FUNCTIONS = [_]Database.Command{
    .{
        .name = "vkInternalAllocationNotification",
        .return_type = "void",
        .parameters = &.{
            .{ .name = "pUserData", .type = "void", .pointer = true },
            .{ .name = "size", .type = "size_t" },
            .{ .name = "allocationType", .type = "VkInternalAllocationType" },
            .{ .name = "allocationScope", .type = "VkSystemAllocationScope" },
        },
    },
    .{
        .name = "vkInternalFreeNotification",
        .return_type = "void",
        .parameters = &.{
            .{ .name = "pUserData", .type = "void", .pointer = true },
            .{ .name = "size", .type = "size_t" },
            .{ .name = "allocationType", .type = "VkInternalAllocationType" },
            .{ .name = "allocationScope", .type = "VkSystemAllocationScope" },
        },
    },
    .{
        .name = "vkReallocationFunction",
        .return_type = "[*]u8",
        .parameters = &.{
            .{ .name = "pUserData", .type = "void", .pointer = true },
            .{ .name = "pOriginal", .type = "void", .pointer = true },
            .{ .name = "size", .type = "size_t" },
            .{ .name = "alignment", .type = "size_t" },
            .{ .name = "allocationScope", .type = "VkSystemAllocationScope" },
        },
    },
    .{
        .name = "vkAllocationFunction",
        .return_type = "[*]u8",
        .parameters = &.{
            .{ .name = "pUserData", .type = "void", .pointer = true },
            .{ .name = "size", .type = "size_t" },
            .{ .name = "alignment", .type = "size_t" },
            .{ .name = "allocationScope", .type = "VkSystemAllocationScope" },
        },
    },
    .{
        .name = "vkFreeFunction",
        .return_type = "void",
        .parameters = &.{
            .{ .name = "pUserData", .type = "void", .pointer = true },
            .{ .name = "pMemory", .type = "void", .pointer = true },
        },
    },
    .{
        .name = "vkVoidFunction",
        .return_type = "void",
        .parameters = &.{
            .{ .name = "pUserData", .type = "void", .pointer = true },
            .{ .name = "pMemory", .type = "void", .pointer = true },
        },
    },
    .{
        .name = "vkDebugReportCallbackEXT",
        .return_type = "VkBool32",
        .parameters = &.{
            .{ .name = "flags", .type = "VkDebugReportFlagsEXT" },
            .{ .name = "objectType", .type = "VkDebugReportObjectTypeEXT" },
            .{ .name = "object", .type = "uint64_t" },
            .{ .name = "location", .type = "size_t" },
            .{ .name = "messageCode", .type = "int32_t" },
            .{ .name = "pLayerPrefix", .type = "char", .pointer = true, .constant = true },
            .{ .name = "pMessage", .type = "char", .pointer = true, .constant = true },
            .{ .name = "pUserData", .type = "void", .pointer = true },
        },
    },
    .{
        .name = "vkDebugUtilsMessengerCallbackEXT",
        .return_type = "VkBool32",
        .parameters = &.{
            .{ .name = "messageSeverity", .type = "VkDebugUtilsMessageSeverityFlagBitsEXT" },
            .{ .name = "messageTypes", .type = "VkDebugUtilsMessageTypeFlagsEXT" },
            .{
                .name = "pCallbackData",
                .type = "VkDebugUtilsMessengerCallbackDataEXT",
                .pointer = true,
                .constant = true,
            },
            .{ .name = "pUserData", .type = "void", .pointer = true },
        },
    },
    .{
        .name = "vkFaultCallbackFunction",
        .return_type = "void",
        .parameters = &.{
            .{ .name = "unrecordedFaults", .type = "VkBool32" },
            .{ .name = "faultCount", .type = "uint32_t" },
            .{ .name = "pFaults", .type = "void", .pointer = true },
        },
    },
    .{
        .name = "vkDeviceMemoryReportCallbackEXT",
        .return_type = "void",
        .parameters = &.{
            .{
                .name = "pCallbackData",
                .type = "VkDeviceMemoryReportCallbackDataEXT",
                .pointer = true,
                .constant = true,
            },
            .{ .name = "pUserData", .type = "void", .pointer = true },
        },
    },
    .{
        .name = "vkGetInstanceProcAddrLUNARG",
        .return_type = "PFN_vkVoidFunction",
        .parameters = &.{
            .{ .name = "instance", .type = "VkInstance" },
            .{ .name = "pName", .type = "char", .pointer = true, .constant = true },
        },
    },
};

// TODO: funcpointers are encoded "horribly" in the xml, so save sanity by
// hardcoding this
fn write_funtions(alloc: Allocator, file: std.fs.File, type_map: *TypeMap) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Functions
        \\
    , .{});

    for (&ADDITIONAL_FUNCTIONS) |*f| {
        try write_command(alloc, type_map, &w, f, false);
    }
}

fn write_structs(
    alloc: Allocator,
    file: std.fs.File,
    db: *const Database,
    type_map: *TypeMap,
) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Structs
        \\
    , .{});

    for (db.types.structs) |str| {
        for (db.extensions.items) |ext| {
            if (ext.unlocks_type(str.name)) w.write(
                \\// Extension: {s}
                \\
            , .{ext.name});
        }
        if (str.alias) |c| {
            w.write(
                \\pub const {s} = {s};
                \\
            , .{ str.name, c });
        } else {
            if (str.comment) |c| w.write(
                \\// Comment: {s}
                \\
            , .{c});

            if (str.extends) |extends| w.write(
                \\// Extends: {s}
                \\
            , .{extends});
            w.write(
                \\// Returned only: {}
                \\// Allow duplicate in pNext chain: {}
                \\pub const {s} = extern struct {{
                \\
            , .{ str.returnedonly, str.allowduplicate, str.name });

            for (str.members) |member| {
                if (member.len) |len| w.write(
                    \\    // Length member: {s}
                    \\
                , .{len});
                if (member.stride) |stride| w.write(
                    \\    // Stride member: {s}
                    \\
                , .{stride});
                if (member.deprecated) |deprecated| w.write(
                    \\    // Deprecated: {s}
                    \\
                , .{deprecated});
                w.write(
                    \\    // Extern sync: {}
                    \\    // Optional: {}
                    \\
                , .{ member.externsync, member.optional });
                if (member.selector) |selector| w.write(
                    \\    // Selector member: {s} (What union field is valid)
                    \\
                , .{selector});
                if (member.objecttype) |objecttype| w.write(
                    \\    // Object type: {s} (Which object handle is this)
                    \\
                , .{objecttype});
                if (member.featurelink) |featurelink| w.write(
                    \\    // Feature link: {s}
                    \\
                , .{featurelink});
                if (member.comment) |comment| w.write(
                    \\    // Comment: {s}
                    \\
                , .{comment});

                const t = try format_type(alloc, type_map, member.type, .{
                    .pointer = member.pointer,
                    .multi_pointer = member.multi_pointer,
                    .constant = member.constant,
                    .multi_constant = member.multi_constant,
                    .len = member.len,
                    .dimensions = member.dimensions,
                    .value = member.value,
                    .make_optional_pointer = true,
                    .print_default = true,
                });
                w.write(
                    \\    {s}: {s},
                    \\
                , .{ member.name, t });
            }

            w.write(
                \\}};
                \\
            , .{});
        }
    }
}

fn write_unions(
    alloc: Allocator,
    file: std.fs.File,
    db: *const Database,
    type_map: *TypeMap,
) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Unions
        \\
    , .{});

    for (db.types.unions) |un| {
        for (db.extensions.items) |ext| {
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

                const t = try format_type(alloc, type_map, member.type, .{
                    .pointer = member.pointer,
                    .constant = member.constant,
                    .len = member.len,
                    .dimensions = member.dimensions,
                });
                w.write(
                    \\    {s}: {s},
                    \\
                , .{ member.name, t });
            }

            w.write(
                \\    pub const zero = @import("std").mem.zeroes(@This());
                \\}};
                \\
            , .{});
        }
    }
}

fn write_command(
    alloc: Allocator,
    type_map: *TypeMap,
    w: *Writer,
    command: *const Database.Command,
    make_global_var: bool,
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
            \\pub const PFN_{s} = fn (
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

            const t = try format_type(alloc, type_map, parameter.type, .{
                .pointer = parameter.pointer,
                .constant = parameter.constant,
                .len = parameter.len,
                .dimensions = parameter.dimensions,
                .convert_arrays_to_pointers = true,
            });
            w.write(
                \\    {s}: {s},
                \\
            , .{ parameter.name, t });
        }

        const return_type = try format_type(alloc, type_map, command.return_type, .{
            .convert_arrays_to_pointers = true,
            .return_type = true,
        });
        w.write(
            \\) callconv(.c) {s};
            \\
        , .{return_type});

        if (make_global_var)
            w.write(
                \\pub var {[name]s} = ?*const PFN_{[name]s};
                \\
            , .{ .name = command.name });
    }
}

fn write_commands(
    alloc: Allocator,
    file: std.fs.File,
    db: *const Database,
    type_map: *TypeMap,
) !void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Commands
        \\
    , .{});

    var visited: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (db.commands.items) |*command| {
        if (visited.get(command.name) != null) continue;
        try visited.put(alloc, command.name, {});

        for (db.extensions.items) |ext| {
            if (ext.unlocks_command(command.name)) w.write(
                \\// Extension: {s}
                \\
            , .{ext.name});
        }
        try write_command(alloc, type_map, &w, command, true);
    }
}

fn write_extensions(alloc: Allocator, file: std.fs.File, db: *const Database) void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Extensions
        \\
    , .{});
    for (db.extensions.items) |ext| {
        w.write(
            \\// Extension: {s}
            \\// Number: {d}
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
        if (ext.supported) |v| w.write(
            \\// Supported: {s}
            \\
        , .{v});
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

fn write_unknown_types(alloc: Allocator, file: std.fs.File, type_map: *const TypeMap) void {
    var w: Writer = .{ .alloc = alloc, .file = file };
    w.write(
        \\
        \\// Unknown types
        \\
    , .{});
    for (type_map.not_found.keys()) |key| {
        w.write(
            \\pub const {[name]s} = if (@hasDecl(@import("root"), "{[name]s}")) @import("root").{[name]s} else @compileError("Unknown type: {{{[name]s}}}");
            \\
        , .{ .name = key });
    }
}

pub fn enum_offset(extension_number: i32, offset: i32) i32 {
    const BASE = 1000000000;
    const RANGE = 1000;
    const result = BASE + (extension_number - 1) * RANGE + offset;
    return result;
}

pub const FormatOptions = struct {
    pointer: bool = false,
    multi_pointer: bool = false,
    constant: bool = false,
    multi_constant: bool = false,
    make_optional_pointer: bool = false,
    print_default: bool = false,
    convert_arrays_to_pointers: bool = false,
    return_type: bool = false,
    len: ?[]const u8 = null,
    dimensions: ?[]const u8 = null,
    value: ?[]const u8 = null,
};
pub fn format_type(
    alloc: Allocator,
    type_map: *TypeMap,
    type_str: []const u8,
    options: FormatOptions,
) ![]const u8 {
    var base_type, var default = try resolve_type(type_map, type_str);

    // return types cannot be plain `anyopaque`, but for simplicity
    // the type_map has `void` -> `anyopaque` since many fields will have `void` type
    if (options.return_type and std.mem.eql(u8, base_type, "anyopaque")) {
        std.debug.assert(!options.pointer);
        std.debug.assert(!options.multi_pointer);
        std.debug.assert(!options.constant);
        std.debug.assert(!options.multi_constant);
        std.debug.assert(options.len == null);
        std.debug.assert(options.dimensions == null);
        std.debug.assert(options.value == null);

        base_type = "void";
    }

    // if the type is a function, we need a pointer to it
    var function_start: []const u8 = &.{};
    if (std.mem.startsWith(u8, base_type, "PFN_")) {
        function_start = "?*const ";
        default = "null";
    }

    var first_len: []const u8 = "";
    var second_len: []const u8 = "";
    if (options.len) |l| {
        var iter = std.mem.splitScalar(u8, l, ',');
        first_len = iter.next() orelse "";
        second_len = iter.next() orelse "";
        std.debug.assert(iter.next() == null);
    }
    const first_const = if (options.constant) "const " else "";
    const second_const = if (options.multi_constant) "const " else "";

    var optional_ptr: []const u8 = &.{};
    var first_ptr: []const u8 = &.{};
    var second_ptr: []const u8 = &.{};
    if (options.pointer) {
        if (options.make_optional_pointer) optional_ptr = "?";
        if (options.len) |l| {
            var n: u32 = 0;
            var iter = std.mem.splitScalar(u8, l, ',');
            while (iter.next()) |ll| : (n += 1) {
                if (std.mem.eql(u8, ll, "null-terminated")) {
                    if (n == 0) {
                        first_ptr = "[*:0]";
                    } else if (n == 1) {
                        std.debug.assert(options.multi_pointer);
                        second_ptr = "[*:0]";
                    }
                } else if (std.mem.eql(u8, ll, "1")) {
                    if (n == 0) {
                        first_ptr = "*";
                    } else if (n == 1) {
                        std.debug.assert(options.multi_pointer);
                        second_ptr = "*";
                    }
                } else {
                    if (n == 0) {
                        first_ptr = "[*]";
                    } else if (n == 1) {
                        std.debug.assert(options.multi_pointer);
                        second_ptr = "[*]";
                    }
                }
            }
            // Sometimes `len` is not specified for second pointer,
            // so just hallucinate smth
            if (n == 1 and options.multi_pointer) second_ptr = "[*]";
        } else {
            first_ptr = "*";
            if (options.multi_pointer)
                second_ptr = "*";
        }
    }

    var dims: []const u8 = &.{};
    if (options.dimensions) |d| {
        std.debug.assert(!options.pointer);
        std.debug.assert(!options.multi_pointer);
        std.debug.assert(!options.multi_constant);
        // constant can still be use with arrays
        // len can still be specified even for an array like `null-terminated`
        // usually dimensions look like `[4]`, but sometimes
        // it is specified as a constant like `[CONSTANT]`
        if (d[0] == '[')
            dims = d
        else
            dims = try std.fmt.allocPrint(alloc, "[{s}]", .{d});

        // this C syntax `const float blendConstants[4]` if used as a function argument
        // becomes a pointer to the fixed size array
        if (options.convert_arrays_to_pointers) {
            first_ptr = "*";
        }
    }

    var value_str: []const u8 = &.{};
    if (options.print_default) {
        if (options.value) |v| {
            value_str = try std.fmt.allocPrint(alloc, " = VkStructureType.{s}", .{v});
        } else if (options.pointer and options.make_optional_pointer) {
            value_str = " = null";
        } else if (default) |def| {
            value_str = try std.fmt.allocPrint(alloc, " = {s}", .{def});
        }
    }

    const result = try std.fmt.allocPrint(alloc,
        \\{[function_start]s}{[optional_ptr]s}{[first_ptr]s}{[first_const]s}{[second_ptr]s}{[second_const]s}{[dimensions]s}{[base_type]s}{[value]s}
    , .{
        .function_start = function_start,
        .optional_ptr = optional_ptr,
        .first_ptr = first_ptr,
        .first_const = first_const,
        .second_ptr = second_ptr,
        .second_const = second_const,
        .dimensions = dims,
        .base_type = base_type,
        .value = value_str,
    });
    return result;
}

test "format_type" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var type_map: TypeMap = .{ .alloc = alloc };
    try fill_type_map(&type_map, &.{});
    try std.testing.expectEqualSlices(
        u8,
        "u32 = 0",
        try format_type(alloc, &type_map, "uint32_t", .{
            .print_default = true,
        }),
    );
    try std.testing.expectEqualSlices(
        u8,
        "A",
        try format_type(alloc, &type_map, "A", .{}),
    );
    try std.testing.expectEqualSlices(
        u8,
        "*A",
        try format_type(alloc, &type_map, "A", .{
            .pointer = true,
            .print_default = true,
        }),
    );
    try std.testing.expectEqualSlices(
        u8,
        "?**A = null",
        try format_type(alloc, &type_map, "A", .{
            .pointer = true,
            .multi_pointer = true,
            .make_optional_pointer = true,
            .print_default = true,
        }),
    );
    try std.testing.expectEqualSlices(
        u8,
        "?*const *A = null",
        try format_type(alloc, &type_map, "A", .{
            .pointer = true,
            .multi_pointer = true,
            .constant = true,
            .make_optional_pointer = true,
            .print_default = true,
        }),
    );
    try std.testing.expectEqualSlices(
        u8,
        "?*const *const A = null",
        try format_type(alloc, &type_map, "A", .{
            .pointer = true,
            .multi_pointer = true,
            .constant = true,
            .multi_constant = true,
            .make_optional_pointer = true,
            .print_default = true,
        }),
    );
    try std.testing.expectEqualSlices(
        u8,
        "?[*]const [*]const A = null",
        try format_type(alloc, &type_map, "A", .{
            .pointer = true,
            .multi_pointer = true,
            .constant = true,
            .multi_constant = true,
            .make_optional_pointer = true,
            .print_default = true,
            .len = "L,L",
        }),
    );
    try std.testing.expectEqualSlices(
        u8,
        "[D]A",
        try format_type(alloc, &type_map, "A", .{
            .dimensions = "D",
        }),
    );
}

pub const TypeInfo = struct { []const u8, ?[]const u8 };
pub const TypeMap = struct {
    alloc: Allocator,
    map: std.StringArrayHashMapUnmanaged(TypeInfo) = .empty,
    not_found: std.StringArrayHashMapUnmanaged(void) = .empty,
};
pub fn fill_type_map(type_map: *TypeMap, db: *const Database) !void {
    for (&[_]struct { []const u8, TypeInfo }{
        .{ "void", .{ "anyopaque", "{}" } },
        .{ "char", .{ "u8", "0" } },
        .{ "float", .{ "f32", "0.0" } },
        .{ "double", .{ "f64", "0.0" } },
        .{ "int8_t", .{ "i8", "0" } },
        .{ "uint8_t", .{ "u8", "0" } },
        .{ "int16_t", .{ "i16", "0" } },
        .{ "uint16_t", .{ "u16", "0" } },
        .{ "uint32_t", .{ "u32", "0" } },
        .{ "uint64_t", .{ "u64", "0" } },
        .{ "int32_t", .{ "i32", "0" } },
        .{ "int64_t", .{ "i64", "0" } },
        .{ "size_t", .{ "usize", "0" } },
        .{ "int", .{ "i32", "0" } },
        .{ "[*]u8", .{ "[*]u8", null } },
    }) |tuple| {
        const c_name, const zig_type = tuple;
        try type_map.map.put(type_map.alloc, c_name, zig_type);
    }

    for (db.types.basetypes) |s| try type_map.map.put(type_map.alloc, s.name, .{ s.type, null });
    for (db.types.handles) |s| try type_map.map.put(type_map.alloc, s.name, .{ s.name, ".none" });
    for (db.types.bitmasks) |bitmask| {
        try type_map.map.put(type_map.alloc, bitmask.name, .{ bitmask.name, ".zero" });
        switch (bitmask.value) {
            .enum_name => |en| {
                try type_map.map.put(type_map.alloc, en, .{ bitmask.name, ".zero" });
            },
            .alias => |alias| {
                try type_map.map.put(type_map.alloc, bitmask.name, .{ alias, ".zero" });
            },
            else => {},
        }
    }
    for (db.types.enum_aliases) |s|
        try type_map.map.put(type_map.alloc, s.name, .{ s.alias, ".zero" });

    for (db.types.structs) |s| try type_map.map.put(type_map.alloc, s.name, .{ s.name, ".{}" });
    for (db.types.unions) |s| try type_map.map.put(type_map.alloc, s.name, .{ s.name, ".zero" });
    for (db.enums.items) |s| {
        if (s.type != .bitmask)
            try type_map.map.put(type_map.alloc, s.name, .{ s.name, ".zero" });
    }

    inline for (ADDITIONAL_FUNCTIONS) |s|
        try type_map.map.put(type_map.alloc, "PFN_" ++ s.name, .{ "PFN_" ++ s.name, "" });
}
pub fn resolve_type(type_map: *TypeMap, name: []const u8) !TypeInfo {
    var result: TypeInfo = undefined;
    if (type_map.map.get(name)) |mapping| {
        // basetypes need to go one indirection deeper to find correct default value
        if (mapping[1] == null) {
            if (type_map.map.get(mapping[0])) |r2|
                result = .{ name, r2[1] }
            else
                unreachable;
        } else {
            result = mapping;
        }
    } else {
        try type_map.not_found.put(type_map.alloc, name, {});
        result = .{ name, null };
    }
    return result;
}
