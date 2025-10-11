const std = @import("std");
const Allocator = std.mem.Allocator;

const xml = @import("xml.zig");

// Ignore list for extensions names
const IGNORE_SUB_NAMES: []const []const u8 = &.{
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
};

pub const Database = struct {
    types: Types,
    extensions: Extensions,
    enums: std.ArrayListUnmanaged(Enum),

    const Self = @This();

    pub fn init(alloc: Allocator, path: []const u8) !Self {
        const xml_file = try std.fs.cwd().openFile(path, .{});
        const buffer = try alloc.alloc(u8, (try xml_file.stat()).size);
        _ = try xml_file.readAll(buffer);

        var types: Types = undefined;
        var extensions: Extensions = undefined;
        var enums: std.ArrayListUnmanaged(Enum) = .empty;
        var parser: xml.Parser = .init(buffer);
        while (parser.peek_next()) |token| {
            switch (token) {
                .element_start => |es| {
                    if (std.mem.eql(u8, es, "registry")) {
                        _ = parser.next();
                        continue;
                    } else if (std.mem.eql(u8, es, "types")) {
                        types = try parse_types(alloc, &parser);
                    } else if (std.mem.eql(u8, es, "extensions")) {
                        extensions = try parse_extensions(alloc, &parser, IGNORE_SUB_NAMES);
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
            name: []const u8,
            extends: []const u8,
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
    while (parser.element_start()) |es| {
        if (std.mem.eql(u8, es, "enum")) {
            const first_attr = parser.attribute() orelse return null;
            if (std.mem.eql(u8, first_attr.name, "extends") or
                std.mem.eql(u8, first_attr.name, "offset") or
                std.mem.eql(u8, first_attr.name, "value") or
                std.mem.eql(u8, first_attr.name, "alias") or
                std.mem.eql(u8, first_attr.name, "name") or
                std.mem.eql(u8, first_attr.name, "api"))
            {
                _ = parser.skip_attributes();
                continue;
            }
            var e: Extension.Require.Enum = undefined;
            const extends = parser.attribute() orelse return null;
            e.extends = extends.value;
            const name = parser.attribute() orelse return null;
            e.name = name.value;
            _ = parser.skip_attributes();
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
            \\    <enum offset="0" extends="A" dir="-" name="A"/>
            \\    <enum bitpos="0" extends="A" name="A"/>
            \\    <type name="A"/>
            \\    <command name="A"/>
            \\    <feature name="A" struct="A"/>
            \\</require>----
        ;

        var parser: xml.Parser = .init(text);
        const r = (try parse_extension_require(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = r;
        // std.log.err("{f}", .{r});
    }
    {
        const text =
            \\<require depends="A">
            \\    <comment>comment</comment>
            \\    <enum value="1" name="A"/>
            \\    <enum value="&quot;B&quot;" name="A"/>
            \\    <enum offset="0" extends="A" dir="-" name="A"/>
            \\    <enum bitpos="0" extends="A" name="A"/>
            \\    <type name="A"/>
            \\    <command name="A"/>
            \\    <feature name="A" struct="A"/>
            \\</require>----
        ;
        var parser: xml.Parser = .init(text);
        const r = (try parse_extension_require(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = r;
        // std.log.err("{f}", .{r});
    }
    {
        const text =
            \\<require comment="A"/>----
        ;
        var parser: xml.Parser = .init(text);
        const r = try parse_extension_require(alloc, &parser);
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = r;
        // std.log.err("{f}", .{r});
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
    loop: while (true) {
        if (try parse_extension(alloc, parser)) |tuple| {
            const ext, const t = tuple;
            for (ignore_subnames) |ia|
                if (std.mem.indexOf(u8, ext.name, ia) != null) continue :loop;
            switch (t) {
                .instance => try instance_extensions.append(alloc, ext),
                .device => try device_extensions.append(alloc, ext),
            }
        } else {
            // std.log.err("skipped out {s}", .{parser.buffer[0..50]});
            parser.skip_current_element();
        }
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "extension")) break,
            else => {},
        }
    }
    _ = parser.next();
    return .{
        .instance = instance_extensions.items,
        .device = device_extensions.items,
    };
}

test "parse_several_extensions" {
    const text =
        \\<extensions comment="Text">
        \\  <extension name="A" number="1" type="device" author="B" depends="C" contact="D" supported="vulkan" promotedto="E" ratified="F">
        \\      <require>
        \\      </require>
        \\  </extension>
        \\  <extension name="B" number="1" type="device" author="B" depends="C" contact="D" supported="vulkan" promotedto="E" ratified="F">
        \\      <require>
        \\      </require>
        \\  </extension>
        \\</extensions>----
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var parser: xml.Parser = .init(text);
    const extensions = try parse_extensions(alloc, &parser, &.{});
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    try std.testing.expectEqual(2, extensions.items.len);
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
    members: []const Member = &.{},

    pub const Member = struct {
        name: []const u8 = &.{},
        type: []const u8 = &.{},
        value: ?[]const u8 = null,
        len: ?[]const u8 = null,
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
};

pub fn parse_struct_member(original_parser: *xml.Parser) ?Struct.Member {
    if (!original_parser.check_peek_element_start("member")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Struct.Member = .{};
    if (parser.state == .attribute) {
        while (parser.attribute()) |attr| {
            if (std.mem.eql(u8, attr.name, "len")) {
                result.len = attr.value;
            } else if (std.mem.eql(u8, attr.name, "values")) {
                result.value = attr.value;
            }
        }
    }

    parser.skip_to_specific_element_start("type");
    result.type = parser.text() orelse return null;
    parser.skip_to_specific_element_end("type");

    parser.skip_to_specific_element_start("name");
    result.name = parser.text() orelse return null;
    parser.skip_to_specific_element_end("name");

    parser.skip_to_specific_element_end("member");

    original_parser.* = parser;
    return result;
}

test "parse_struct_member" {
    const text0 =
        \\<member><type>A</type> <name>A</name><comment>AAA</comment></member>----
    ;
    {
        var parser: xml.Parser = .init(text0);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = m;
        // std.log.err("{f}", .{m});
    }
    const text1 =
        \\<member values="A"><type>A</type> <name>A</name></member>----
    ;
    {
        var parser: xml.Parser = .init(text1);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = m;
        // std.log.err("{f}", .{m});
    }
    const text2 =
        \\<member noautovalidity="true" optional="true">const <type>A</type>* <name>A</name><comment>AAA</comment></member>----
    ;
    {
        var parser: xml.Parser = .init(text2);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = m;
        // std.log.err("{f}", .{m});
    }
    const text3 =
        \\<member optional="true"><type>A</type> <name>A</name></member>----
    ;
    {
        var parser: xml.Parser = .init(text3);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = m;
        // std.log.err("{f}", .{m});
    }
    const text4 =
        \\<member len="A,null-terminated"> <type>A</type> <name>A</name></member>----
    ;
    {
        var parser: xml.Parser = .init(text4);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = m;
        // std.log.err("{f}", .{m});
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
        }
    }

    const attributes_end = parser.skip_attributes().?;
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
            \\<type category="struct" name="A" structextends="A">
            \\    <member><type>A</type> <name>A</name><comment>AAA</comment></member>
            \\</type>----
        ;
        var parser: xml.Parser = .init(text);
        const s = (try parse_struct(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = s;
        // std.log.err("{f}", .{s});
    }

    {
        const text =
            \\<type category="struct" name="A" alias="A"/>----
        ;
        var parser: xml.Parser = .init(text);
        const s = (try parse_struct(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        _ = s;
        // std.log.err("{f}", .{s});
    }
}

pub fn parse_types(alloc: Allocator, parser: *xml.Parser) !Types {
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
            try structs.append(alloc, v);
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
    const types = try parse_types(alloc, &parser);
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
