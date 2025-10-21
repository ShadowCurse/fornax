const std = @import("std");
const Allocator = std.mem.Allocator;

const xml = @import("xml.zig");

// Ignore list for extensions names
const IGNORE_EXTENSIONS: []const []const u8 = &.{
    "AMD",
    "ANDROID",
    "ARM",
    "FUCHSIA",
    "GGP",
    "GOOGLE",
    "HUAWEI",
    "LUNARG",
    "MESA",
    "MSFT",
    "MVK",
    "NN",
    "NV",
    "OHOS",
    "QNX",
    "RESERVED",
    "SEC",
    "android",
    "extension",
    "mir",
    "wayland",
    "win32",
    "xcb",
    "xlib",
    "VK_EXT_application_parameters",
    "VK_KHR_performance_query",
    "VK_KHR_portability_subset",
    "VK_KHR_object_refresh",
};

// Ignore list for structs
const IGNORE_STRUCTS: []const []const u8 = &.{
    "NV",
    "NVX",
    "AMD",
    "AMDX",
    "QCOM",
    "ARM",
    "SEC",
    "GOOGLE",
    "GGP",
    "VkPipelineOfflineCreateInfo",
    "VkExternalFormatANDROID",
};

// Ignore list for structs
const IGNORE_SPIRV: []const []const u8 = &.{
    "AMD",
    "AMDX",
    "ARM",
    "GGP",
    "GOOGLE",
    "HUAWEI",
    "INTEL",
    "NV",
    "NVX",
    "QCOM",
    "SEC",
};

pub fn c_to_zig_type(name: []const u8) ?[]const u8 {
    for (&[_]struct { []const u8, []const u8 }{
        .{ "void", "void" },
        .{ "char", "u8" },
        .{ "float", "f32" },
        .{ "double", "f64" },
        .{ "int8_t", "i8" },
        .{ "uint8_t", "u8" },
        .{ "int16_t", "i16" },
        .{ "uint16_t", "u16" },
        .{ "uint32_t", "u32" },
        .{ "uint64_t", "u64" },
        .{ "int32_t", "i32" },
        .{ "int64_t", "i64" },
        .{ "size_t", "usize" },
        .{ "int", "i32" },
    }) |tuple| {
        const c_name, const zig_name = tuple;
        if (std.mem.eql(u8, c_name, name)) return zig_name;
    }
    return null;
}

pub const Database = struct {
    types: Types,
    extensions: Extensions,
    enums: std.ArrayListUnmanaged(Enum),
    spirv: Spirv,

    const Self = @This();

    pub fn init(alloc: Allocator, path: []const u8) !Self {
        const xml_file = try std.fs.cwd().openFile(path, .{});
        const buffer = try alloc.alloc(u8, (try xml_file.stat()).size);
        _ = try xml_file.readAll(buffer);

        var types: Types = undefined;
        var extensions: Extensions = undefined;
        var enums: std.ArrayListUnmanaged(Enum) = .empty;
        var spirv: Spirv = undefined;
        var parser: xml.Parser = .init(buffer);
        while (parser.peek_next()) |token| {
            switch (token) {
                .element_start => |es| {
                    if (std.mem.eql(u8, es, "registry")) {
                        _ = parser.next();
                        continue;
                    } else if (std.mem.eql(u8, es, "types")) {
                        types = try parse_types(alloc, &parser, IGNORE_STRUCTS);
                    } else if (std.mem.eql(u8, es, "extensions")) {
                        extensions = try parse_extensions(alloc, &parser, IGNORE_EXTENSIONS);
                    } else if (std.mem.eql(u8, es, "spirvextensions")) {
                        spirv = try parse_spirv(alloc, &parser, IGNORE_SPIRV);
                    } else if (std.mem.eql(u8, es, "enums")) {
                        if (try parse_enum(alloc, &parser)) |e|
                            try enums.append(alloc, e)
                        else
                            parser.skip_current_element();
                    } else {
                        parser.skip_current_element();
                    }
                },
                else => {
                    _ = parser.next();
                },
            }
        }
        return .{
            .types = types,
            .extensions = extensions,
            .enums = enums,
            .spirv = spirv,
        };
    }

    pub const AllExtensionsIterator = struct {
        db: *const Self,
        instance_index: u32 = 0,
        device_index: u32 = 0,

        pub fn next(self: *AllExtensionsIterator) ?struct { *const Extension, Extension.Type } {
            while (self.instance_index < self.db.extensions.instance.len) {
                const ext = &self.db.extensions.instance[self.instance_index];
                self.instance_index += 1;
                return .{ ext, .instance };
            }
            while (self.device_index < self.db.extensions.device.len) {
                const ext = &self.db.extensions.device[self.device_index];
                self.device_index += 1;
                return .{ ext, .device };
            }
            return null;
        }
    };

    pub fn all_extensions(self: *const Self) AllExtensionsIterator {
        return .{ .db = self };
    }

    pub fn extension_by_name(self: *const Self, name: []const u8) ?struct { *const Extension, Extension.Type } {
        var iter = self.all_extensions();
        while (iter.next()) |tuple| {
            const ext, _ = tuple;
            if (std.mem.eql(u8, ext.name, name))
                return tuple;
        }
        return null;
    }

    pub fn enum_by_name(self: *const Self, name: []const u8) ?*const Enum {
        for (self.enums.items) |*e| {
            if (std.mem.eql(u8, e.name, name))
                return e;
        }
        return null;
    }

    pub fn struct_by_name(self: *const Self, name: []const u8) ?*const Struct {
        for (self.types.structs) |*s| {
            if (std.mem.eql(u8, s.name, name)) {
                if (s.alias) |alias| return self.struct_by_name(alias);
                return s;
            }
        }
        return null;
    }

    pub fn is_struct_name(self: *const Self, name: []const u8) bool {
        for (self.types.structs) |*s|
            if (std.mem.eql(u8, s.name, name)) return true;
        return false;
    }
};

pub const Extensions = struct {
    instance: []const Extension = &.{},
    device: []const Extension = &.{},
};

pub const Extension = struct {
    name: []const u8 = &.{},
    depends: []const u8 = &.{},
    promoted_to: []const u8 = &.{},
    deprecated_by: []const u8 = &.{},
    require: []const Require = &.{},

    pub const Type = enum {
        instance,
        device,
    };

    pub const Require = struct {
        depends: ?[]const u8 = null,
        items: []const Item = &.{},

        pub const Item = union(enum) {
            @"enum": Require.Enum,
            type: []const u8,
        };

        pub const Enum = struct {
            name: []const u8 = &.{},
            extends: []const u8 = &.{},
            alias: ?[]const u8 = null,
        };

        pub fn format(self: *const Require, writer: anytype) !void {
            try writer.print("depends: {?s}\n", .{self.depends});
            for (self.items) |i| {
                switch (i) {
                    .@"enum" => |ee| try writer.print(
                        "enum: name: {s} extends: {s}\n",
                        .{ ee.name, ee.extends },
                    ),
                    .type => |t| try writer.print("type: {s}\n", .{t}),
                }
            }
        }
    };

    pub fn format(self: *const Extension, writer: anytype) !void {
        try writer.print(
            "name: {s} depends: {s} promoted_to: {s} deprecated_by: {s}\n",
            .{ self.name, self.depends, self.promoted_to, self.deprecated_by },
        );
        for (self.require) |r| try writer.print("require: {f}\n", .{r});
    }
};

pub fn parse_extension_require(alloc: Allocator, original_parser: *xml.Parser) !?Extension.Require {
    if (!original_parser.check_peek_element_start("require")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Extension.Require = .{};
    if (parser.state == .attribute) {
        while (parser.attribute()) |attr| {
            if (std.mem.eql(u8, attr.name, "depends")) {
                result.depends = attr.value;
                _ = parser.skip_attributes();
                break;
            } else if (std.mem.eql(u8, attr.name, "comment")) {
                loop: switch (parser.next() orelse return null) {
                    .attribute_list_end => break,
                    .attribute_list_end_contained => {
                        original_parser.* = parser;
                        return result;
                    },
                    else => continue :loop parser.next() orelse return null,
                }
            }
        }
    }

    var items: std.ArrayListUnmanaged(Extension.Require.Item) = .empty;
    outer: while (parser.element_start()) |es| {
        if (std.mem.eql(u8, es, "enum")) {
            var e: Extension.Require.Enum = .{};
            while (parser.attribute()) |attr| {
                if (std.mem.eql(u8, attr.name, "value") or
                    std.mem.eql(u8, attr.name, "api"))
                {
                    _ = parser.skip_attributes();
                    continue :outer;
                } else if (std.mem.eql(u8, attr.name, "extends")) {
                    e.extends = attr.value;
                } else if (std.mem.eql(u8, attr.name, "name")) {
                    e.name = attr.value;
                } else if (std.mem.eql(u8, attr.name, "alias")) {
                    e.alias = attr.value;
                }
            }
            try items.append(alloc, .{ .@"enum" = e });
        } else if (std.mem.eql(u8, es, "type")) {
            const name = parser.attribute() orelse return null;
            _ = parser.skip_attributes();
            try items.append(alloc, .{ .type = name.value });
        } else if (std.mem.eql(u8, es, "command")) {
            _ = parser.skip_attributes();
        } else if (std.mem.eql(u8, es, "feature")) {
            _ = parser.skip_attributes();
        } else {
            parser.skip_to_specific_element_end(es);
        }
    }
    result.items = items.items;
    original_parser.* = parser;
    return result;
}

test "parse_extension_require" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    {
        const text =
            \\<require>
            \\    <comment>comment</comment>
            \\    <enum value="1" name="A"/>
            \\    <enum value="&quot;B&quot;" name="A"/>
            \\    <enum offset="0" extends="A" dir="-" name="B"/>
            \\    <enum bitpos="0" extends="C" name="D" alias="E"/>
            \\    <type name="F"/>
            \\    <command name="A"/>
            \\    <feature name="A" struct="A"/>
            \\</require>----
        ;

        var parser: xml.Parser = .init(text);
        const r = (try parse_extension_require(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Extension.Require = .{
            .depends = null,
            .items = &.{
                .{ .@"enum" = .{ .name = "B", .extends = "A", .alias = null } },
                .{ .@"enum" = .{ .name = "D", .extends = "C", .alias = "E" } },
                .{ .type = "F" },
            },
        };
        try std.testing.expectEqual(expected.depends, r.depends);
        try std.testing.expectEqualDeep(expected.items, r.items);
    }
    {
        const text =
            \\<require depends="AAA">
            \\    <comment>comment</comment>
            \\    <enum value="1" name="A"/>
            \\    <enum value="&quot;B&quot;" name="A"/>
            \\    <enum offset="0" extends="A" dir="-" name="B"/>
            \\    <enum bitpos="0" extends="C" name="D" alias="E"/>
            \\    <type name="F"/>
            \\    <command name="A"/>
            \\    <feature name="A" struct="A"/>
            \\</require>----
        ;

        var parser: xml.Parser = .init(text);
        const r = (try parse_extension_require(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Extension.Require = .{
            .depends = "AAA",
            .items = &.{
                .{ .@"enum" = .{ .name = "B", .extends = "A", .alias = null } },
                .{ .@"enum" = .{ .name = "D", .extends = "C", .alias = "E" } },
                .{ .type = "F" },
            },
        };
        try std.testing.expectEqualStrings(expected.depends.?, r.depends.?);
        try std.testing.expectEqualDeep(expected.items, r.items);
    }
    {
        const text =
            \\<require comment="A"/>----
        ;
        var parser: xml.Parser = .init(text);
        _ = try parse_extension_require(alloc, &parser);
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    }
}

pub fn parse_extension(alloc: Allocator, original_parser: *xml.Parser) !?struct {
    Extension,
    Extension.Type,
} {
    if (!original_parser.check_peek_element_start("extension")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();
    if (parser.state != .attribute) return null;

    var result: Extension = .{};
    var t: ?Extension.Type = null;
    while (parser.attribute()) |attr| {
        if (std.mem.eql(u8, attr.name, "name")) {
            result.name = attr.value;
        } else if (std.mem.eql(u8, attr.name, "supported")) {
            if (std.mem.eql(u8, attr.value, "disabled")) return null;
        } else if (std.mem.eql(u8, attr.name, "depends")) {
            result.depends = attr.value;
        } else if (std.mem.eql(u8, attr.name, "promotedto")) {
            result.promoted_to = attr.value;
        } else if (std.mem.eql(u8, attr.name, "deprecatedby")) {
            result.deprecated_by = attr.value;
        } else if (std.mem.eql(u8, attr.name, "type")) {
            if (std.mem.eql(u8, attr.value, "device"))
                t = .device
            else if (std.mem.eql(u8, attr.value, "instance"))
                t = .instance;
        }
    }
    if (t == null) return null;

    var fields: std.ArrayListUnmanaged(Extension.Require) = .empty;
    while (parser.peek_element_start()) |next_es| {
        if (std.mem.eql(u8, next_es, "require")) {
            if (try parse_extension_require(alloc, &parser)) |r|
                try fields.append(alloc, r);
        } else {
            parser.skip_current_element();
        }
    }
    result.require = fields.items;
    _ = parser.element_end();

    original_parser.* = parser;
    return .{ result, t.? };
}

test "parse_single_extension" {
    const text =
        \\<extension name="A" number="1" type="device" author="B" depends="C" contact="D" supported="vulkan" promotedto="E" ratified="F">
        \\    <require>
        \\        <comment>comment</comment>
        \\        <enum value="1" name="A"/>
        \\        <enum value="&quot;A&quot;" name="A"/>
        \\        <enum extends="A" name="A" alias="A"/>
        \\        <enum bitpos="0" extends="A" name="A"/>
        \\        <type name="A"/>
        \\        <feature name="A" struct="A"/>
        \\    </require>
        \\    <require depends="B">
        \\        <comment>comment</comment>
        \\        <enum value="1" name="B"/>
        \\        <enum value="&quot;B&quot;" name="B"/>
        \\        <enum extends="B" name="B" alias="B"/>
        \\        <enum bitpos="0" extends="B" name="B"/>
        \\        <type name="B"/>
        \\        <feature name="B" struct="B"/>
        \\    </require>
        \\    <require comment="C">
        \\        <comment>comment</comment>
        \\        <enum value="1" name="C"/>
        \\        <enum value="&quot;C&quot;" name="C"/>
        \\        <enum extends="C" name="C" alias="C"/>
        \\        <enum bitpos="0" extends="C" name="C"/>
        \\        <type name="C"/>
        \\        <feature name="C" struct="C"/>
        \\    </require>
        \\    <deprecate explanationlink="D">
        \\        <command name="D"/>
        \\    </deprecate>
        \\</extension>----
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var parser: xml.Parser = .init(text);
    const e = (try parse_extension(alloc, &parser)).?;
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    _ = e;
    // std.log.err("{f}", .{e});
}

pub fn parse_extensions(
    alloc: Allocator,
    parser: *xml.Parser,
    ignore_subnames: []const []const u8,
) !Extensions {
    if (!parser.check_peek_element_start("extensions")) return .{};

    _ = parser.element_start();
    _ = parser.skip_attributes();

    var instance_extensions: std.ArrayListUnmanaged(Extension) = .empty;
    var device_extensions: std.ArrayListUnmanaged(Extension) = .empty;
    while (true) {
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "extensions")) break,
            else => {},
        }

        if (try parse_extension(alloc, parser)) |tuple| {
            const ext, const t = tuple;
            for (ignore_subnames) |ia| {
                if (std.mem.indexOf(u8, ext.name, ia) != null) break;
            } else switch (t) {
                .instance => try instance_extensions.append(alloc, ext),
                .device => try device_extensions.append(alloc, ext),
            }
        } else parser.skip_current_element();
    }
    _ = parser.next();
    return .{
        .instance = instance_extensions.items,
        .device = device_extensions.items,
    };
}

test "parse_extensions" {
    const text =
        \\<extensions comment="Text">
        \\  <extension name="A" number="1" type="device" author="B" depends="C" contact="D" supported="vulkan" promotedto="E" ratified="F">
        \\      <require>
        \\      </require>
        \\  </extension>
        \\  <extension name="B" number="1" type="instance" author="B" depends="C" contact="D" supported="vulkan" promotedto="E" ratified="F">
        \\      <require>
        \\      </require>
        \\  </extension>
        \\</extensions>----
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var parser: xml.Parser = .init(text);
    const e = try parse_extensions(alloc, &parser, &.{});
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    const expected: Extensions = .{
        .instance = &.{
            .{ .name = "B", .depends = "C", .promoted_to = "E", .require = &.{.{}} },
        },
        .device = &.{
            .{ .name = "A", .depends = "C", .promoted_to = "E", .require = &.{.{}} },
        },
    };
    try std.testing.expectEqualDeep(expected, e);
}

pub const Types = struct {
    basetypes: []const Basetype = &.{},
    bitmasks: []const Bitmask = &.{},
    structs: []const Struct = &.{},
};

pub const Basetype = struct {
    type: []const u8,
    name: []const u8,
};

pub fn parse_basetype(original_parser: *xml.Parser) ?Basetype {
    if (!original_parser.check_peek_element_start("type")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    const first_attr = parser.attribute() orelse return null;
    if (!std.mem.eql(u8, first_attr.name, "category") or
        !std.mem.eql(u8, first_attr.value, "basetype"))
        return null;
    _ = parser.skip_attributes();

    var result: Basetype = undefined;
    parser.skip_to_specific_element_start("type");
    result.type = parser.text() orelse return null;
    parser.skip_to_specific_element_end("type");

    parser.skip_to_specific_element_start("name");
    result.name = parser.text() orelse return null;
    parser.skip_to_specific_element_end("type");

    original_parser.* = parser;
    return result;
}

test "parse_basetype" {
    {
        const text =
            \\<type category="basetype"> <name> </name>;</type>
        ;
        var parser: xml.Parser = .init(text);
        const b = parse_basetype(&parser);
        try std.testing.expectEqual(null, b);
    }
    const text =
        \\<type category="basetype"> <type>A</type> <name>A</name>;</type>----
    ;
    var parser: xml.Parser = .init(text);
    const b = parse_basetype(&parser).?;
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    _ = b;
    // std.log.err("{f}", .{b});
}

pub const Bitmask = struct {
    type_name: []const u8,
    enum_name: []const u8,

    pub fn format(self: *const Bitmask, writer: anytype) !void {
        try writer.print("type_name: {s} enum_name: {s}", .{ self.type_name, self.enum_name });
    }
};

pub fn parse_bitmask(original_parser: *xml.Parser) ?Bitmask {
    if (!original_parser.check_peek_element_start("type")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var correct_category: bool = false;
    var enum_name: ?[]const u8 = null;
    if (parser.state == .attribute) {
        while (parser.attribute()) |attr| {
            if (std.mem.eql(u8, attr.name, "requires")) {
                enum_name = attr.value;
            } else if (std.mem.eql(u8, attr.name, "category")) {
                if (!std.mem.eql(u8, attr.value, "bitmask"))
                    return null
                else
                    correct_category = true;
            }
        }
    }
    if (!correct_category or enum_name == null) return null;

    var result: Bitmask = undefined;
    result.enum_name = enum_name.?;
    parser.skip_to_specific_element_start("name");
    result.type_name = parser.text() orelse return null;
    parser.skip_to_specific_element_end("type");

    original_parser.* = parser;
    return result;
}

test "parse_bitmask" {
    {
        const text =
            \\<type requires="A" category="bitmask">typedef <type> </type> <name>B</name>;</type>----
        ;
        var parser: xml.Parser = .init(text);
        const b = parse_bitmask(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = b;
        // std.log.err("{f}", .{m});
    }
}

pub const Struct = struct {
    name: []const u8 = &.{},
    extends: ?[]const u8 = null,
    alias: ?[]const u8 = null,
    members: []const Member = &.{},

    pub const Member = struct {
        name: []const u8 = &.{},
        type: []const u8 = &.{},
        value: ?[]const u8 = null,
        len: ?Len = null,
        optional: bool = false,
        pointer: bool = false,

        pub const Len = union(enum) {
            member: []const u8,
            null: void,
        };

        pub fn format(self: *const Member, writer: anytype) !void {
            try writer.print(
                "name: {s} type: {s} value: {?s} len: {?s}",
                .{ self.name, self.type, self.value, self.len },
            );
        }
    };

    pub fn format(self: *const Struct, writer: anytype) !void {
        try writer.print(
            "name: {s} extends: {?s} fields: {d}\n",
            .{ self.name, self.extends, self.members.len },
        );
        for (self.members) |*field| try writer.print("{f}\n", .{field});
    }

    pub fn stype(self: *const Struct) ?[]const u8 {
        for (self.members) |*member| {
            if (std.mem.eql(u8, member.name, "sType")) return member.value;
        }
        return null;
    }

    pub fn has_member(self: *const Struct, name: []const u8) bool {
        for (self.members) |*m|
            if (std.mem.eql(u8, m.name, name)) return true;
        return false;
    }
};

pub fn parse_struct_member(original_parser: *xml.Parser) ?Struct.Member {
    if (!original_parser.check_peek_element_start("member")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Struct.Member = .{};
    if (parser.state == .attribute) {
        while (parser.attribute()) |attr| {
            if (std.mem.eql(u8, attr.name, "len")) {
                if (std.mem.eql(u8, attr.value, "null-terminated")) {
                    result.len = .null;
                } else if (std.mem.endsWith(u8, attr.value, "null-terminated")) {
                    const len = attr.value.len - ",null-terminated".len;
                    result.len = .{ .member = attr.value[0..len] };
                } else {
                    result.len = .{ .member = attr.value };
                }
            } else if (std.mem.eql(u8, attr.name, "altlen")) {
                result.len = .{ .member = attr.value };
            } else if (std.mem.eql(u8, attr.name, "values")) {
                result.value = attr.value;
            } else if (std.mem.eql(u8, attr.name, "optional")) {
                if (std.mem.eql(u8, attr.value, "true"))
                    result.optional = true;
            }
        }
    }

    parser.skip_to_specific_element_start("type");
    result.type = parser.text() orelse return null;
    parser.skip_to_specific_element_end("type");
    if (parser.peek_text()) |text|
        result.pointer = std.mem.indexOfScalar(u8, text, '*') != null;
    parser.skip_to_specific_element_start("name");
    result.name = parser.text() orelse return null;
    parser.skip_to_specific_element_end("name");

    parser.skip_to_specific_element_end("member");

    original_parser.* = parser;
    return result;
}

test "parse_struct_member" {
    {
        const text =
            \\<member><type>T</type> <name>N</name><comment>CCC</comment></member>----
        ;
        var parser: xml.Parser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member values="V"><type>T</type> <name>N</name></member>----
        ;
        var parser: xml.Parser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .value = "V",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member noautovalidity="true" optional="true"> <type>T</type>* <name>N</name><comment>C</comment></member>----
        ;
        var parser: xml.Parser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .optional = true,
            .pointer = true,
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member optional="true"><type>T</type> <name>N</name></member>----
        ;
        var parser: xml.Parser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .optional = true,
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member len="null-terminated"> <type>T</type> <name>N</name></member>----
        ;
        var parser: xml.Parser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .len = .null,
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member len="L">B <type>T</type>* <name>N</name></member>----
        ;
        var parser: xml.Parser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .len = .{ .member = "L" },
            .pointer = true,
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member len="L,null-terminated">B <type>T</type>* <name>N</name></member>----
        ;
        var parser: xml.Parser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .len = .{ .member = "L" },
            .pointer = true,
        };
        try std.testing.expectEqualDeep(expected, m);
    }
}

pub fn parse_struct(alloc: Allocator, original_parser: *xml.Parser) !?Struct {
    if (!original_parser.check_peek_element_start("type")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();
    if (parser.state != .attribute) return null;

    var result: Struct = .{};
    const first_attr = parser.attribute().?;
    if (!std.mem.eql(u8, first_attr.name, "category") or
        !std.mem.eql(u8, first_attr.value, "struct"))
        return null;

    while (parser.peek_attribute()) |_| {
        const attr = parser.attribute().?;
        if (std.mem.eql(u8, attr.name, "name")) {
            result.name = attr.value;
        } else if (std.mem.eql(u8, attr.name, "structextends")) {
            result.extends = attr.value;
        } else if (std.mem.eql(u8, attr.name, "alias")) {
            result.alias = attr.value;
        }
    }

    const attributes_end = parser.skip_attributes() orelse return null;
    if (attributes_end != .attribute_list_end_contained) {
        var members: std.ArrayListUnmanaged(Struct.Member) = .empty;
        while (parse_struct_member(&parser)) |member| {
            try members.append(alloc, member);
        }
        parser.skip_to_specific_element_end("type");
        result.members = members.items;
    }
    original_parser.* = parser;
    return result;
}

test "parse_single_struct" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    {
        const text =
            \\<type category="struct" name="N" structextends="E">
            \\    <member values="V"><type>T1</type> <name>N1</name></member>
            \\    <member optional="true"><type>T2</type>* <name>N2</name></member>
            \\    <member><type>T3</type> <name>N3</name></member>
            \\    <member><type>T4</type> <name>N4</name></member>
            \\</type>----
        ;
        var parser: xml.Parser = .init(text);
        const s = (try parse_struct(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct = .{
            .name = "N",
            .extends = "E",
            .alias = null,
            .members = &.{
                .{
                    .name = "N1",
                    .type = "T1",
                    .value = "V",
                    .len = null,
                    .optional = false,
                    .pointer = false,
                },
                .{
                    .name = "N2",
                    .type = "T2",
                    .value = null,
                    .len = null,
                    .optional = true,
                    .pointer = true,
                },
                .{
                    .name = "N3",
                    .type = "T3",
                    .value = null,
                    .len = null,
                    .optional = false,
                    .pointer = false,
                },
                .{
                    .name = "N4",
                    .type = "T4",
                    .value = null,
                    .len = null,
                    .optional = false,
                    .pointer = false,
                },
            },
        };
        try std.testing.expectEqualDeep(expected, s);
    }

    {
        const text =
            \\<type category="struct" name="N" alias="A"/>----
        ;
        var parser: xml.Parser = .init(text);
        const s = (try parse_struct(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct = .{
            .name = "N",
            .extends = null,
            .alias = "A",
            .members = &.{},
        };
        try std.testing.expectEqualDeep(expected, s);
    }
}

pub fn parse_types(
    alloc: Allocator,
    parser: *xml.Parser,
    ignore_structs: []const []const u8,
) !Types {
    if (!parser.check_peek_element_start("types")) return .{};

    _ = parser.element_start();
    _ = parser.skip_attributes();

    var basetypes: std.ArrayListUnmanaged(Basetype) = .empty;
    var bitmasks: std.ArrayListUnmanaged(Bitmask) = .empty;
    var structs: std.ArrayListUnmanaged(Struct) = .empty;
    while (true) {
        if (parse_basetype(parser)) |v| {
            try basetypes.append(alloc, v);
        } else if (parse_bitmask(parser)) |v| {
            try bitmasks.append(alloc, v);
        } else if (try parse_struct(alloc, parser)) |v| {
            for (ignore_structs) |ignore| {
                if (std.mem.eql(u8, v.name, ignore) or
                    std.mem.endsWith(u8, v.name, ignore))
                    break;
            } else try structs.append(alloc, v);
        } else {
            parser.skip_current_element();
        }
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "types")) break,
            else => {},
        }
    }
    _ = parser.next();

    return .{
        .basetypes = basetypes.items,
        .bitmasks = bitmasks.items,
        .structs = structs.items,
    };
}

test "parse_types" {
    const text =
        \\<types comment="AAAA">
        \\    <type name="a" category="include">A</type>
        \\        <comment>AAA</comment>
        \\    <type category="include" name="X11/Xlib.h"/>
        \\    <type category="struct" name="A" alias="A"/>
        \\    <type category="struct" name="A">
        \\        <member values="A"><type>A</type> <name>sType</name></member>
        \\    </type>
        \\    <type requires="A" category="bitmask"><type>A</type><name>A</name>;</type>
        \\</types>----
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var parser: xml.Parser = .init(text);
    const types = try parse_types(alloc, &parser, &.{});
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    try std.testing.expectEqual(2, types.structs.len);
    try std.testing.expectEqual(1, types.bitmasks.len);
}

pub const Enum = struct {
    type: enum { @"enum", bitmask },
    name: []const u8,
    bitwidth: u32,
    items: []const Item,

    pub const Item = struct {
        type: enum { value, bitpos },
        name: []const u8,
        comment: []const u8,

        pub fn format(self: *const Item, writer: anytype) !void {
            try writer.print(
                "type: {t} name: {s}",
                .{ self.type, self.name },
            );
        }
    };

    pub fn format(self: *const Enum, writer: anytype) !void {
        try writer.print("name: {s} type: {t}\n", .{ self.name, self.type });
        for (self.items) |v| try writer.print("{f}\n", .{v});
    }
};

pub fn parse_enum_item(original_parser: *xml.Parser) ?Enum.Item {
    if (!original_parser.check_peek_element_start("enum")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Enum.Item = undefined;
    while (parser.attribute()) |attr| {
        if (std.mem.eql(u8, attr.name, "api")) {
            return null;
        } else if (std.mem.eql(u8, attr.name, "value")) {
            result.type = .value;
        } else if (std.mem.eql(u8, attr.name, "bitpos")) {
            result.type = .bitpos;
        } else if (std.mem.eql(u8, attr.name, "name")) {
            result.name = attr.value;
        } else if (std.mem.eql(u8, attr.name, "comment")) {
            result.comment = attr.value;
        }
    }
    original_parser.* = parser;
    return result;
}

test "parse_single_enum_item" {
    {
        const text =
            \\<enum value="8" name="A"/>----
        ;
        var parser: xml.Parser = .init(text);
        const e = parse_enum_item(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = e;
        // std.log.err("{f}", .{e});
    }
    {
        const text =
            \\<enum bitpos="8" name="A" comment="A"/>----
        ;
        var parser: xml.Parser = .init(text);
        const e = parse_enum_item(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = e;
        // std.log.err("{f}", .{e});
    }

    {
        const text =
            \\<enum api="vulkan"  name="A" alias="B" deprecated="aliased"/>
        ;
        var parser: xml.Parser = .init(text);
        const e = parse_enum_item(&parser);
        try std.testing.expectEqualSlices(u8, text, parser.buffer);
        try std.testing.expectEqual(null, e);
    }
}

pub fn parse_enum(alloc: Allocator, original_parser: *xml.Parser) !?Enum {
    if (!original_parser.check_peek_element_start("enums")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Enum = undefined;
    result.bitwidth = 32;
    while (parser.attribute()) |attr| {
        if (std.mem.eql(u8, attr.name, "name")) {
            result.name = attr.value;
        } else if (std.mem.eql(u8, attr.name, "type")) {
            if (std.mem.eql(u8, attr.value, "enum"))
                result.type = .@"enum"
            else if (std.mem.eql(u8, attr.value, "bitmask"))
                result.type = .bitmask;
        } else if (std.mem.eql(u8, attr.name, "bitwidth")) {
            result.bitwidth = try std.fmt.parseInt(u32, attr.value, 10);
        }
    }

    var values: std.ArrayListUnmanaged(Enum.Item) = .empty;
    while (true) {
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "enums")) break,
            else => {},
        }
        if (parse_enum_item(&parser)) |t| {
            try values.append(alloc, t);
        } else {
            parser.skip_current_element();
        }
    }
    _ = parser.next();
    result.items = values.items;

    original_parser.* = parser;
    return result;
}

test "parse_enum" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    {
        const text =
            \\<enums name="A" type="bitmask">
            \\    <enum bitpos="0" name="A" comment="A"/>
            \\    <enum bitpos="1" name="A" comment="A"/>
            \\    <enum value="0x00000003" name="A" comment="A"/>
            \\    <enum api="vulkan"  name="A" alias="A" deprecated="aliased"/>
            \\</enums>----
        ;
        var parser: xml.Parser = .init(text);
        const e = (try parse_enum(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = e;
        // std.log.err("{f}", .{e});
    }

    {
        const text =
            \\<enums name="A" type="bitmask">
            \\</enums>----
        ;
        var parser: xml.Parser = .init(text);
        const e = (try parse_enum(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = e;
        // std.log.err("{f}", .{e});
    }
}

pub const Spirv = struct {
    extensions: []const Spirv.Extension = &.{},
    capabilities: []const Spirv.Capability = &.{},

    pub const Extension = struct {
        name: []const u8 = &.{},
        version: ?[]const u8 = null,
        extension: []const u8 = &.{},
    };
    pub const Capability = struct {
        name: []const u8 = &.{},
        enable: []const Capability.Enable = &.{},

        pub const Enable = union(enum) {
            sfr: Enable.Sfr,
            property: Enable.Property,
            version: []const u8,
            extension: []const u8,

            pub const Sfr = struct {
                @"struct": []const u8 = &.{},
                feature: []const u8 = &.{},
                requires: []const u8 = &.{},
            };

            pub const Property = struct {
                property: []const u8 = &.{},
                member: []const u8 = &.{},
                value: []const u8 = &.{},
                requires: []const u8 = &.{},
            };
        };
    };
};

pub fn parse_spirv_extension(original_parser: *xml.Parser) ?Spirv.Extension {
    if (!original_parser.check_peek_element_start("spirvextension")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Spirv.Extension = .{};
    const name = parser.attribute() orelse return null;
    result.name = name.value;
    _ = parser.skip_attributes();

    while (true) {
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "spirvextension")) break,
            else => {},
        }
        _ = parser.element_start() orelse return null;
        const attr = parser.attribute() orelse return null;
        if (std.mem.eql(u8, attr.name, "version")) {
            result.version = attr.value;
            _ = parser.skip_attributes();
        } else if (std.mem.eql(u8, attr.name, "extension")) {
            result.extension = attr.value;
            _ = parser.skip_attributes();
        }
    }
    _ = parser.next();

    original_parser.* = parser;
    return result;
}

test "parse_spirv_extension" {
    {
        const text =
            \\<spirvextension name="N">
            \\    <enable extension="E"/>
            \\</spirvextension>----
        ;
        var parser: xml.Parser = .init(text);
        const e = parse_spirv_extension(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Spirv.Extension = .{
            .name = "N",
            .version = null,
            .extension = "E",
        };
        try std.testing.expectEqualDeep(expected, e);
    }
    {
        const text =
            \\<spirvextension name="N">
            \\    <enable version="V"/>
            \\    <enable extension="E"/>
            \\</spirvextension>----
        ;
        var parser: xml.Parser = .init(text);
        const e = parse_spirv_extension(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Spirv.Extension = .{
            .name = "N",
            .version = "V",
            .extension = "E",
        };
        try std.testing.expectEqualDeep(expected, e);
    }
}

pub fn parse_spirv_capability(alloc: Allocator, original_parser: *xml.Parser) !?Spirv.Capability {
    if (!original_parser.check_peek_element_start("spirvcapability")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Spirv.Capability = .{};
    const name = parser.attribute() orelse return null;
    result.name = name.value;
    _ = parser.skip_attributes();

    var items: std.ArrayListUnmanaged(Spirv.Capability.Enable) = .empty;
    while (true) {
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "spirvcapability")) break,
            else => {},
        }
        _ = parser.element_start() orelse return null;

        const first = parser.attribute() orelse return null;
        if (std.mem.eql(u8, first.name, "version")) {
            try items.append(alloc, .{ .version = first.value });
        } else if (std.mem.eql(u8, first.name, "extension")) {
            try items.append(alloc, .{ .extension = first.value });
        } else if (std.mem.eql(u8, first.name, "struct")) {
            var sfr: Spirv.Capability.Enable.Sfr = .{};
            sfr.@"struct" = first.value;

            const feature = parser.attribute() orelse return null;
            if (!std.mem.eql(u8, feature.name, "feature")) return null;
            sfr.feature = feature.value;

            const requires = parser.attribute() orelse return null;
            if (!std.mem.eql(u8, requires.name, "requires")) return null;
            sfr.requires = requires.value;

            try items.append(alloc, .{ .sfr = sfr });
        } else if (std.mem.eql(u8, first.name, "property")) {
            var prop: Spirv.Capability.Enable.Property = .{};
            prop.property = first.value;

            const member = parser.attribute() orelse return null;
            if (!std.mem.eql(u8, member.name, "member")) return null;
            prop.member = member.value;

            const value = parser.attribute() orelse return null;
            if (!std.mem.eql(u8, value.name, "value")) return null;
            prop.value = value.value;

            const requires = parser.attribute() orelse return null;
            if (!std.mem.eql(u8, requires.name, "requires")) return null;
            prop.requires = requires.value;

            try items.append(alloc, .{ .property = prop });
        }

        _ = parser.skip_attributes();
    }
    _ = parser.next();

    result.enable = items.items;
    original_parser.* = parser;
    return result;
}

test "parse_spirv_capability" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    {
        const text =
            \\<spirvcapability name="N">
            \\    <enable version="V"/>
            \\</spirvcapability>----
        ;
        var parser: xml.Parser = .init(text);
        const c = (try parse_spirv_capability(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Spirv.Capability = .{
            .name = "N",
            .enable = &.{
                .{ .version = "V" },
            },
        };
        try std.testing.expectEqualDeep(expected, c);
    }
    {
        const text =
            \\<spirvcapability name="N">
            \\    <enable struct="S1" feature="F1" requires="R1"/>
            \\    <enable struct="S2" feature="F2" requires="R2"/>
            \\    <enable struct="S3" feature="F3" requires="R3"/>
            \\</spirvcapability>----
        ;
        var parser: xml.Parser = .init(text);
        const c = (try parse_spirv_capability(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Spirv.Capability = .{
            .name = "N",
            .enable = &.{
                .{ .sfr = .{ .@"struct" = "S1", .feature = "F1", .requires = "R1" } },
                .{ .sfr = .{ .@"struct" = "S2", .feature = "F2", .requires = "R2" } },
                .{ .sfr = .{ .@"struct" = "S3", .feature = "F3", .requires = "R3" } },
            },
        };
        try std.testing.expectEqualDeep(expected, c);
    }
    {
        const text =
            \\<spirvcapability name="N">
            \\    <enable struct="S" feature="F" requires="R"/>
            \\    <enable version="V"/>
            \\    <enable extension="E"/>
            \\</spirvcapability>----
        ;
        var parser: xml.Parser = .init(text);
        const c = (try parse_spirv_capability(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Spirv.Capability = .{
            .name = "N",
            .enable = &.{
                .{ .sfr = .{ .@"struct" = "S", .feature = "F", .requires = "R" } },
                .{ .version = "V" },
                .{ .extension = "E" },
            },
        };
        try std.testing.expectEqualDeep(expected, c);
    }
    {
        const text =
            \\<spirvcapability name="N">
            \\    <enable property="P" member="M" value="V" requires="R"/>
            \\</spirvcapability>----
        ;
        var parser: xml.Parser = .init(text);
        const c = (try parse_spirv_capability(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Spirv.Capability = .{
            .name = "N",
            .enable = &.{
                .{ .property = .{
                    .property = "P",
                    .member = "M",
                    .value = "V",
                    .requires = "R",
                } },
            },
        };
        try std.testing.expectEqualDeep(expected, c);
    }
}

pub fn parse_spirv(
    alloc: Allocator,
    parser: *xml.Parser,
    ignore_spirv: []const []const u8,
) !Spirv {
    if (!parser.check_peek_element_start("spirvextensions")) return .{};
    _ = parser.element_start();
    _ = parser.skip_attributes();

    var extensions: std.ArrayListUnmanaged(Spirv.Extension) = .empty;
    while (true) {
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "spirvextensions")) break,
            else => {},
        }

        if (parse_spirv_extension(parser)) |v| {
            for (ignore_spirv) |ignore| {
                if (std.mem.endsWith(u8, v.name, ignore))
                    break;
            } else try extensions.append(alloc, v);
        } else {
            parser.skip_current_element();
        }
    }
    _ = parser.next();

    if (!parser.check_peek_element_start("spirvcapabilities")) return .{};
    _ = parser.element_start();
    _ = parser.skip_attributes();

    var capabilities: std.ArrayListUnmanaged(Spirv.Capability) = .empty;
    while (true) {
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "spirvcapabilities")) break,
            else => {},
        }

        if (try parse_spirv_capability(alloc, parser)) |v| {
            for (ignore_spirv) |ignore| {
                if (std.mem.endsWith(u8, v.name, ignore))
                    break;
            } else try capabilities.append(alloc, v);
        } else {
            parser.skip_current_element();
        }
    }
    _ = parser.next();
    return .{
        .extensions = extensions.items,
        .capabilities = capabilities.items,
    };
}

test "parse_spirv" {
    const text =
        \\<spirvextensions comment="C">
        \\    <spirvextension name="N1">
        \\        <enable extension="X1"/>
        \\    </spirvextension>
        \\    <spirvextension name="N2">
        \\        <enable version="V2"/>
        \\        <enable extension="X2"/>
        \\    </spirvextension>
        \\</spirvextensions>
        \\<spirvcapabilities comment="C">
        \\    <spirvcapability name="N1">
        \\        <enable struct="S" feature="F" requires="R"/>
        \\    </spirvcapability>
        \\    <spirvcapability name="N2">
        \\        <enable struct="S" feature="F" requires="R"/>
        \\    </spirvcapability>
        \\</spirvcapabilities>----
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var parser: xml.Parser = .init(text);
    const s = try parse_spirv(alloc, &parser, &.{});
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    const expected: Spirv = .{
        .extensions = &.{
            .{ .name = "N1", .version = null, .extension = "X1" },
            .{ .name = "N2", .version = "V2", .extension = "X2" },
        },
        .capabilities = &.{
            .{
                .name = "N1",
                .enable = &.{
                    .{ .sfr = .{ .@"struct" = "S", .feature = "F", .requires = "R" } },
                },
            },
            .{
                .name = "N2",
                .enable = &.{
                    .{ .sfr = .{ .@"struct" = "S", .feature = "F", .requires = "R" } },
                },
            },
        },
    };
    try std.testing.expectEqualDeep(expected, s);
}
