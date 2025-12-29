const std = @import("std");
const Allocator = std.mem.Allocator;
const XmlParser = @import("xml_parser.zig");

// Descriptions of XML tags/attributes:
// https://registry.khronos.org/vulkan/specs/latest/registry.html
types: Types = .{},
features: std.ArrayListUnmanaged(Extension) = .empty,
extensions: std.ArrayListUnmanaged(Extension) = .empty,
enums: std.ArrayListUnmanaged(Enum) = .empty,
constants: Constants = .{},
commands: std.ArrayListUnmanaged(Command) = .empty,
// formats
spirv: Spirv = .{},

const Self = @This();

pub fn init(alloc: Allocator, buffer: []const u8) !Self {
    var types: Types = undefined;
    var features: std.ArrayListUnmanaged(Extension) = .empty;
    var extensions: std.ArrayListUnmanaged(Extension) = .empty;
    var enums: std.ArrayListUnmanaged(Enum) = .empty;
    var constants: Constants = undefined;
    var commands: std.ArrayListUnmanaged(Command) = .empty;
    var spirv: Spirv = undefined;
    var parser: XmlParser = .init(buffer);
    while (parser.peek_next()) |token| {
        switch (token) {
            .element_start => |es| {
                if (std.mem.eql(u8, es, "registry")) {
                    _ = parser.next();
                    continue;
                } else if (std.mem.eql(u8, es, "types")) {
                    types = try parse_types(alloc, &parser);
                } else if (std.mem.eql(u8, es, "extensions")) {
                    extensions = try parse_extensions(alloc, &parser);
                } else if (std.mem.eql(u8, es, "commands")) {
                    commands = try parse_commands(alloc, &parser);
                } else if (std.mem.eql(u8, es, "spirvextensions")) {
                    spirv = try parse_spirv(alloc, &parser);
                } else if (std.mem.eql(u8, es, "enums")) {
                    if (try parse_enum(alloc, &parser)) |e| {
                        try enums.append(alloc, e);
                    } else {
                        if (try parse_constants(alloc, &parser)) |c| {
                            constants = c;
                        } else {
                            parser.skip_current_element();
                        }
                    }
                } else if (std.mem.eql(u8, es, "feature")) {
                    if (try parse_extension(alloc, &parser)) |e|
                        try features.append(alloc, e);
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
        .features = features,
        .extensions = extensions,
        .enums = enums,
        .constants = constants,
        .commands = commands,
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

/// Iterator over all extensions
pub fn all_extensions(self: *const Self) AllExtensionsIterator {
    return .{ .db = self };
}

/// Find extension with the `extension_name`
pub fn extension_by_name(self: *const Self, extension_name: []const u8) ?struct {
    *const Extension,
    Extension.Type,
} {
    var iter = self.all_extensions();
    while (iter.next()) |tuple| {
        const ext, _ = tuple;
        if (std.mem.eql(u8, ext.name, extension_name))
            return tuple;
    }
    return null;
}

/// Find extension which has the struct in the list of types that the
/// extension adds
pub fn extension_which_adds_struct(
    self: *const Self,
    struct_name: []const u8,
) ?*const Extension {
    var search_name = struct_name;
    if (self.struct_alias_of(struct_name)) |alias_of| search_name = alias_of.name;

    var iter = self.all_extensions();
    while (iter.next()) |tuple| {
        const ext, _ = tuple;
        for (ext.require) |*require| {
            for (require.items) |item| {
                switch (item) {
                    .type => |name| {
                        if (std.mem.eql(u8, name, search_name)) return ext;
                    },
                    else => {},
                }
            }
        }
    }
    return null;
}

/// Find enum with `enum_name`
pub fn enum_by_name(self: *const Self, enum_name: []const u8) ?*const Enum {
    for (self.enums.items) |*e| {
        if (std.mem.eql(u8, e.name, enum_name))
            return e;
    }
    return null;
}

/// Find struct with with the `struct_name`. If the `struct_name` is
/// an alias to other struct, returns other struct
pub fn struct_by_name(self: *const Self, struct_name: []const u8) ?*const Struct {
    for (self.types.structs) |*s| {
        if (std.mem.eql(u8, s.name, struct_name)) {
            if (s.alias) |alias| return self.struct_by_name(alias);
            return s;
        }
    }
    return null;
}

/// Find the struct which is the aliased by the `struct_name`
pub fn struct_alias_of(self: *const Self, struct_name: []const u8) ?*const Struct {
    for (self.types.structs) |*s| {
        if (s.alias) |alias| {
            if (std.mem.eql(u8, alias, struct_name)) {
                return s;
            }
        }
    }
    return null;
}

/// Check if the struct with `struct_name` exists
pub fn is_struct_name(self: *const Self, struct_name: []const u8) bool {
    for (self.types.structs) |*s|
        if (std.mem.eql(u8, s.name, struct_name)) return true;
    return false;
}

fn parse_attributes(
    comptime PREFIX: []const u8,
    comptime PEEK: bool,
    parser: *XmlParser,
    value: anytype,
    comptime ATTRS: []const struct { []const u8, ?[]const u8 },
) void {
    const Inner = struct {
        fn process(v: anytype, attr: XmlParser.Attribute) void {
            var parsed: bool = false;
            inline for (ATTRS) |tuple| {
                const attr_name, const maybe_field_name = tuple;
                const field_name = maybe_field_name orelse attr_name;
                if (std.mem.eql(u8, attr.name, attr_name)) {
                    switch (@TypeOf(@field(v, field_name))) {
                        u32,
                        ?u32,
                        => @field(v, field_name) = std.fmt.parseInt(u32, attr.value, 10) catch |e| blk: {
                            std.log.err("Error parsing u32: {s}: {t}", .{ attr.value, e });
                            break :blk 0;
                        },
                        ?[]const u8,
                        []const u8,
                        => @field(v, field_name) = attr.value,
                        ?bool,
                        bool,
                        => @field(v, field_name) = std.mem.eql(u8, attr.value, "true"),
                        Extension.Type,
                        => @field(v, field_name) = if (std.mem.eql(u8, attr.value, "device"))
                            .device
                        else
                            .instance,
                        Extension.Supported,
                        => {
                            if (std.mem.eql(u8, attr.value, "disabled"))
                                @field(v, field_name) = .disabled;
                        },
                        Extension.Require.Enum.Negative,
                        => @field(v, field_name) = .{true},
                        else => |e| @compileError(std.fmt.comptimePrint(
                            "Unknown type: {s}",
                            .{@typeName(e)},
                        )),
                    }
                    parsed = true;
                }
            }
            if (!parsed) std.log.warn(
                "{s}: skipping attribute {s}={s}",
                .{ PREFIX, attr.name, attr.value },
            );
        }
    };
    if (PEEK) {
        while (parser.peek_attribute()) |attr| {
            _ = parser.attribute();
            Inner.process(value, attr);
        }
    } else {
        while (parser.attribute()) |attr| {
            Inner.process(value, attr);
        }
    }
}

// Also <feature> tags
pub const Extension = struct {
    name: []const u8 = &.{},
    number: []const u8 = &.{},
    author: ?[]const u8 = null,
    type: Type = .disabled,
    depends: ?[]const u8 = null,
    platform: ?[]const u8 = null,
    supported: Supported = .supported,
    promotedto: ?[]const u8 = null,
    deprecatedby: ?[]const u8 = null,
    obsoletedby: ?[]const u8 = null,
    comment: ?[]const u8 = null,

    require: []const Require = &.{},

    pub const Type = enum {
        disabled,
        instance,
        device,
    };

    pub const Supported = enum {
        supported,
        disabled,
    };

    pub const Require = struct {
        depends: ?[]const u8 = null,
        comment: ?[]const u8 = null,
        items: []const Item = &.{},

        pub const Item = union(enum) {
            comment: []const u8,
            command: Require.Command,
            @"enum": Require.Enum,
            type: Require.Type,
            feature: Require.Feature,
        };

        pub const Command = struct {
            name: []const u8 = &.{},
            comment: ?[]const u8 = null,
        };

        pub const Enum = struct {
            name: []const u8 = &.{},
            comment: ?[]const u8 = null,

            value: ?[]const u8 = null,
            bitpos: ?u32 = null,
            extends: ?[]const u8 = null,
            extnumber: ?u32 = null,
            offset: ?u32 = null,
            negative: @This().Negative = .{false},
            alias: ?[]const u8 = null,

            pub const Negative = struct { bool };
        };

        pub const Type = struct {
            name: []const u8 = &.{},
        };

        pub const Feature = struct {
            name: []const u8 = &.{},
            @"struct": ?[]const u8 = null,
            comment: ?[]const u8 = null,
        };
    };

    pub fn unlocks_type(self: *const Extension, type_name: []const u8) bool {
        for (self.require) |require| {
            for (require.items) |item| {
                switch (item) {
                    .type => |t| {
                        if (std.mem.eql(u8, t.name, type_name)) return true;
                    },
                    else => {},
                }
            }
        }
        return false;
    }

    pub fn unlocks_command(self: *const Extension, command_name: []const u8) bool {
        for (self.require) |require| {
            for (require.items) |item| {
                switch (item) {
                    .command => |c| {
                        if (std.mem.eql(u8, c.name, command_name)) return true;
                    },
                    else => {},
                }
            }
        }
        return false;
    }

    pub const EnumExtensions =
        std.ArrayListUnmanaged(struct {
            name: []const u8,
            value: union(enum) { value: i32, offset: struct {
                offset: u32,
                extnumber: u32,
                negative: bool,
            }, bitpos: u32, alias: []const u8 },
        });
    pub fn enum_extensions(
        self: *const Extension,
        alloc: Allocator,
        enum_name: []const u8,
    ) !EnumExtensions {
        var result: EnumExtensions = .empty;
        for (self.require) |require| {
            for (require.items) |item| {
                switch (item) {
                    .@"enum" => |e| {
                        if (e.extends) |ext| {
                            if (std.mem.eql(u8, ext, enum_name)) {
                                if (e.value) |v| try result.append(
                                    alloc,
                                    .{ .name = e.name, .value = .{
                                        .value = try std.fmt.parseInt(i32, v, 10),
                                    } },
                                );
                                if (e.bitpos) |v| try result.append(
                                    alloc,
                                    .{ .name = e.name, .value = .{ .bitpos = v } },
                                );
                                if (e.offset) |v| try result.append(
                                    alloc,
                                    .{ .name = e.name, .value = .{ .offset = .{
                                        .offset = v,
                                        .extnumber = e.extnumber orelse
                                            try std.fmt.parseInt(u32, self.number, 10),
                                        .negative = e.negative[0],
                                    } } },
                                );
                                if (e.alias) |v| try result.append(
                                    alloc,
                                    .{ .name = e.name, .value = .{ .alias = v } },
                                );
                            }
                        }
                    },
                    else => {},
                }
            }
        }
        return result;
    }
};

pub fn parse_extension_require(alloc: Allocator, original_parser: *XmlParser) !?Extension.Require {
    if (!original_parser.check_peek_element_start("require")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Extension.Require = .{};
    if (parser.state == .attribute) {
        parse_attributes("parse_extension_require", true, &parser, &result, &.{
            .{ "depends", null },
            .{ "comment", null },
        });
    }
    const attributes_end = parser.skip_attributes() orelse .attribute_list_end;
    if (attributes_end == .attribute_list_end_contained) return null;

    var items: std.ArrayListUnmanaged(Extension.Require.Item) = .empty;
    while (parser.element_start()) |es| {
        if (std.mem.eql(u8, es, "comment")) {
            try items.append(alloc, .{ .comment = parser.text() orelse return null });
            parser.skip_to_specific_element_end("comment");
        } else if (std.mem.eql(u8, es, "command")) {
            var e: Extension.Require.Command = .{};
            parse_attributes("parse_extension_require_command", false, &parser, &e, &.{
                .{ "name", null },
                .{ "comment", null },
            });
            try items.append(alloc, .{ .command = e });
        } else if (std.mem.eql(u8, es, "enum")) {
            var e: Extension.Require.Enum = .{};
            parse_attributes("parse_extension_require_enum", false, &parser, &e, &.{
                .{ "name", null },
                .{ "comment", null },
                .{ "value", null },
                .{ "bitpos", null },
                .{ "extends", null },
                .{ "extnumber", null },
                .{ "offset", null },
                .{ "dir", "negative" },
                .{ "alias", null },
            });
            try items.append(alloc, .{ .@"enum" = e });
        } else if (std.mem.eql(u8, es, "type")) {
            var e: Extension.Require.Type = .{};
            parse_attributes("parse_extension_require_type", false, &parser, &e, &.{
                .{ "name", null },
            });
            try items.append(alloc, .{ .type = e });
        } else if (std.mem.eql(u8, es, "feature")) {
            var e: Extension.Require.Feature = .{};
            parse_attributes("parse_extension_require_feature", false, &parser, &e, &.{
                .{ "name", null },
                .{ "struct", null },
                .{ "comment", null },
            });
            try items.append(alloc, .{ .feature = e });
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
            \\    <comment>C</comment>
            \\    <enum value="1" name="A"/>
            \\    <enum value="&quot;B&quot;" name="B"/>
            \\    <enum offset="0" extends="E1" dir="-" name="C"/>
            \\    <enum bitpos="0" extends="E2" name="D" alias="F"/>
            \\    <type name="G"/>
            \\    <command name="E"/>
            \\    <feature name="F2" struct="S"/>
            \\</require>----
        ;

        var parser: XmlParser = .init(text);
        const r = (try parse_extension_require(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);

        const expected: Extension.Require = .{
            .items = &.{
                .{ .comment = "C" },
                .{ .@"enum" = .{ .name = "A", .value = "1" } },
                .{ .@"enum" = .{ .name = "B", .value = "&quot;B&quot;" } },
                .{ .@"enum" = .{ .name = "C", .offset = 0, .extends = "E1", .negative = .{true} } },
                .{ .@"enum" = .{ .name = "D", .bitpos = 0, .extends = "E2", .alias = "F" } },
                .{ .type = .{ .name = "G" } },
                .{ .command = .{ .name = "E" } },
                .{ .feature = .{ .name = "F2", .@"struct" = "S" } },
            },
        };
        try std.testing.expectEqualDeep(expected, r);
    }
    {
        const text =
            \\<require depends="Y" comment="Z">
            \\    <comment>C</comment>
            \\    <enum value="1" name="A"/>
            \\    <enum value="&quot;B&quot;" name="B"/>
            \\    <enum offset="0" extends="E1" dir="-" name="C"/>
            \\    <enum bitpos="0" extends="E2" name="D" alias="F"/>
            \\    <type name="G"/>
            \\    <command name="E"/>
            \\    <feature name="F2" struct="S"/>
            \\</require>----
        ;

        var parser: XmlParser = .init(text);
        const r = (try parse_extension_require(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);

        const expected: Extension.Require = .{
            .depends = "Y",
            .comment = "Z",
            .items = &.{
                .{ .comment = "C" },
                .{ .@"enum" = .{ .name = "A", .value = "1" } },
                .{ .@"enum" = .{ .name = "B", .value = "&quot;B&quot;" } },
                .{ .@"enum" = .{ .name = "C", .offset = 0, .extends = "E1", .negative = .{true} } },
                .{ .@"enum" = .{ .name = "D", .bitpos = 0, .extends = "E2", .alias = "F" } },
                .{ .type = .{ .name = "G" } },
                .{ .command = .{ .name = "E" } },
                .{ .feature = .{ .name = "F2", .@"struct" = "S" } },
            },
        };
        try std.testing.expectEqualDeep(expected, r);
    }
    {
        const text =
            \\<require comment="A"/>----
        ;
        var parser: XmlParser = .init(text);
        const r = try parse_extension_require(alloc, &parser);
        try std.testing.expectEqual(null, r);
    }
}

pub fn parse_extension(alloc: Allocator, original_parser: *XmlParser) !?Extension {
    if (!original_parser.check_peek_element_start("extension") and
        !original_parser.check_peek_element_start("feature")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Extension = .{};
    parse_attributes("parse_extension_require", false, &parser, &result, &.{
        .{ "name", null },
        .{ "number", null },
        .{ "author", null },
        .{ "type", null },
        .{ "depends", null },
        .{ "platform", null },
        .{ "supported", null },
        .{ "promotedto", null },
        .{ "deprecatedby", null },
        .{ "obsoletedby", null },
        .{ "comment", null },
    });

    var fields: std.ArrayListUnmanaged(Extension.Require) = .empty;
    while (parser.peek_element_start()) |next_es| {
        if (std.mem.eql(u8, next_es, "require")) {
            if (try parse_extension_require(alloc, &parser)) |r|
                try fields.append(alloc, r)
            else
                parser.skip_current_element();
        } else {
            parser.skip_current_element();
        }
    }
    result.require = fields.items;
    _ = parser.element_end();

    original_parser.* = parser;
    return result;
}

test "parse_single_extension" {
    const text =
        \\<extension name="A" number="1" type="device" author="B" depends="C" platform="P" contact="D" supported="disabled" promotedto="E" ratified="F" deprecatedby="G">
        \\    <require>
        \\        <comment>C</comment>
        \\        <enum value="1" name="A"/>
        \\    </require>
        \\    <require depends="B">
        \\        <comment>C</comment>
        \\        <enum value="2" name="B"/>
        \\    </require>
        \\    <deprecate explanationlink="D">
        \\        <command name="D"/>
        \\    </deprecate>
        \\</extension>----
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var parser: XmlParser = .init(text);
    const e = (try parse_extension(alloc, &parser)).?;
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    const expected: Extension = .{
        .name = "A",
        .number = "1",
        .author = "B",
        .type = .device,
        .depends = "C",
        .platform = "P",
        .supported = .disabled,
        .promotedto = "E",
        .deprecatedby = "G",
        .require = &.{
            .{
                .items = &.{
                    .{ .comment = "C" },
                    .{ .@"enum" = .{ .name = "A", .value = "1" } },
                },
            },
            .{
                .depends = "B",
                .items = &.{
                    .{ .comment = "C" },
                    .{ .@"enum" = .{ .name = "B", .value = "2" } },
                },
            },
        },
    };
    try std.testing.expectEqualDeep(expected, e);
}

test "parse_single_feature" {
    const text =
        \\<feature api="vulkan,vulkansc,vulkanbase" apitype="internal" name="N" number="1.1" depends="D">
        \\    <require>
        \\        <type name="N"/>
        \\    </require>
        \\    <require comment="C">
        \\        <command name="Q"/>
        \\    </require>
        \\</feature>----
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var parser: XmlParser = .init(text);
    const e = (try parse_extension(alloc, &parser)).?;
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    const expected: Extension = .{
        .name = "N",
        .number = "1.1",
        .depends = "D",
        .require = &.{
            .{
                .items = &.{
                    .{ .type = .{ .name = "N" } },
                },
            },
            .{
                .comment = "C",
                .items = &.{
                    .{ .command = .{ .name = "Q" } },
                },
            },
        },
    };
    try std.testing.expectEqualDeep(expected, e);
}

pub fn parse_extensions(alloc: Allocator, parser: *XmlParser) !std.ArrayListUnmanaged(Extension) {
    if (!parser.check_peek_element_start("extensions")) return .{};

    _ = parser.element_start();
    _ = parser.skip_attributes();

    var extensions: std.ArrayListUnmanaged(Extension) = .empty;
    while (true) {
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "extensions")) break,
            else => {},
        }

        if (try parse_extension(alloc, parser)) |ext|
            try extensions.append(alloc, ext)
        else
            parser.skip_current_element();
    }
    _ = parser.next();
    return extensions;
}

test "parse_extensions" {
    const text =
        \\<extensions comment="Text">
        \\  <extension name="A" number="1" type="device" author="G" depends="B" contact="G" supported="S" promotedto="C" ratified="G">
        \\      <require>
        \\      </require>
        \\  </extension>
        \\  <extension name="D" number="2" type="instance" author="G" depends="E" contact="G" supported="S" promotedto="F" ratified="G">
        \\      <require>
        \\      </require>
        \\  </extension>
        \\</extensions>----
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var parser: XmlParser = .init(text);
    const e = try parse_extensions(alloc, &parser);
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    const expected: []const Extension = &.{
        .{
            .name = "A",
            .number = "1",
            .author = "G",
            .type = .device,
            .depends = "B",
            .supported = .supported,
            .promotedto = "C",
            .require = &.{.{}},
        },
        .{
            .name = "D",
            .number = "2",
            .author = "G",
            .type = .instance,
            .depends = "E",
            .supported = .supported,
            .promotedto = "F",
            .require = &.{.{}},
        },
    };
    try std.testing.expectEqualDeep(expected, e.items);
}

pub const Types = struct {
    basetypes: []const Basetype = &.{},
    handles: []const Handle = &.{},
    bitmasks: []const Bitmask = &.{},
    enum_aliases: []const EnumAlias = &.{},
    structs: []const Struct = &.{},
    unions: []const Union = &.{},
};

pub const Basetype = struct {
    name: []const u8 = &.{},
    type: []const u8 = &.{},
    pointer: bool = false,
};

pub fn parse_basetype(original_parser: *XmlParser) ?Basetype {
    if (!original_parser.check_peek_element_start("type")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    const first_attr = parser.attribute() orelse return null;
    if (!std.mem.eql(u8, first_attr.name, "category") or
        !std.mem.eql(u8, first_attr.value, "basetype"))
        return null;
    _ = parser.skip_attributes();

    var result: Basetype = .{};
    _ = parser.skip_text();
    const start = parser.element_start() orelse return null;
    if (std.mem.eql(u8, start, "type")) {
        result.type = parser.text() orelse return null;
        parser.skip_to_specific_element_end("type");

        // Special case just for VkRemoteAddressNV, since it defineds itself
        // over multiple `text` segments where the second one does not normally
        // exist, but just for NVIDIA there is an exception apparently.
        if (parser.peek_text()) |text2| {
            result.pointer = std.mem.indexOf(u8, text2, "*") != null;
        }

        parser.skip_to_specific_element_start("name");
        result.name = parser.text() orelse return null;
        parser.skip_to_specific_element_end("type");
    } else {
        return null;
    }

    original_parser.* = parser;
    return result;
}

test "parse_basetype" {
    {
        const text =
            \\<type category="basetype">#ifdef __OBJC__
            \\@class CAMetalLayer;
            \\#else
            \\typedef void <name>A</name>;
            \\#endif</type>----
        ;
        var parser: XmlParser = .init(text);
        const b = parse_basetype(&parser);
        try std.testing.expectEqual(null, b);
    }
    {
        const text =
            \\<type category="basetype">typedef <type>uint32_t</type> <name>A</name>;</type>----
        ;
        var parser: XmlParser = .init(text);
        const b = parse_basetype(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Basetype = .{
            .name = "A",
            .type = "uint32_t",
        };
        try std.testing.expectEqualDeep(expected, b);
    }
    {
        const text =
            \\<type category="basetype">typedef <type>void</type>* <name>A</name>;</type>----
        ;
        var parser: XmlParser = .init(text);
        const b = parse_basetype(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Basetype = .{
            .name = "A",
            .type = "void",
            .pointer = true,
        };
        try std.testing.expectEqualDeep(expected, b);
    }
}

pub const Handle = struct {
    name: []const u8 = &.{},
    alias: ?[]const u8 = null,
    parent: ?[]const u8 = null,
    objtypeenum: ?[]const u8 = null,
};

pub fn parse_handle(original_parser: *XmlParser) ?Handle {
    if (!original_parser.check_peek_element_start("type")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    const first_attr = parser.attribute() orelse return null;
    if (!std.mem.eql(u8, first_attr.name, "category") or
        !std.mem.eql(u8, first_attr.value, "handle"))
        return null;

    var result: Handle = .{};
    parse_attributes("parse_handle", false, &parser, &result, &.{
        .{ "name", null },
        .{ "alias", null },
        .{ "parent", null },
        .{ "objtypeenum", null },
    });

    if (result.alias == null) {
        parser.skip_to_specific_element_start("name");
        result.name = parser.text() orelse return null;
        parser.skip_to_specific_element_end("type");
    }

    original_parser.* = parser;
    return result;
}

test "parse_handle" {
    {
        const text =
            \\<type category="handle" parent="P" objtypeenum="O"><type>T</type>(<name>N</name>)</type>----
        ;
        var parser: XmlParser = .init(text);
        const b = parse_handle(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Handle = .{
            .name = "N",
            .parent = "P",
            .objtypeenum = "O",
        };
        try std.testing.expectEqualDeep(expected, b);
    }
    {
        const text =
            \\<type category="handle" name="N"   alias="A"/>----
        ;
        var parser: XmlParser = .init(text);
        const b = parse_handle(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Handle = .{
            .name = "N",
            .alias = "A",
        };
        try std.testing.expectEqualDeep(expected, b);
    }
}

pub const Bitmask = struct {
    name: []const u8 = &.{},
    value: union(enum) {
        invalid: void,
        enum_name: []const u8,
        type: []const u8,
        alias: []const u8,
    } = .invalid,
};

pub fn parse_bitmask(original_parser: *XmlParser) ?Bitmask {
    if (!original_parser.check_peek_element_start("type")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var found_category: bool = false;
    var result: Bitmask = .{};
    if (parser.state == .attribute) {
        while (parser.attribute()) |attr| {
            if (std.mem.eql(u8, attr.name, "requires")) {
                result.value = .{ .enum_name = attr.value };
            } else if (std.mem.eql(u8, attr.name, "bitvalues")) {
                result.value = .{ .enum_name = attr.value };
            } else if (std.mem.eql(u8, attr.name, "name")) {
                result.name = attr.value;
            } else if (std.mem.eql(u8, attr.name, "alias")) {
                result.value = .{ .alias = attr.value };
            } else if (std.mem.eql(u8, attr.name, "api")) {
                if (std.mem.eql(u8, attr.value, "vulkansc"))
                    return null;
            } else if (std.mem.eql(u8, attr.name, "category")) {
                if (!std.mem.eql(u8, attr.value, "bitmask"))
                    return null
                else
                    found_category = true;
            }
        }
    }
    if (!found_category) return null;

    if (result.value != .alias) {
        // Bitmasks not attached to enums need to parse <type>...</type> just in
        // case
        if (result.value == .invalid) {
            parser.skip_to_specific_element_start("type");
            const text = parser.text() orelse return null;
            result.value = .{ .type = text };
        }

        parser.skip_to_specific_element_start("name");
        result.name = parser.text() orelse return null;
        parser.skip_to_specific_element_end("type");
    }

    original_parser.* = parser;
    return result;
}

test "parse_bitmask" {
    {
        const text =
            \\<type requires="B" category="bitmask">typedef <type>VkFlags</type> <name>A</name>;</type>----
        ;
        var parser: XmlParser = .init(text);
        const b = parse_bitmask(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Bitmask = .{
            .name = "A",
            .value = .{ .enum_name = "B" },
        };
        try std.testing.expectEqualDeep(expected, b);
    }
    {
        const text =
            \\<type category="bitmask">typedef <type>VkFlags</type> <name>A</name>;</type>----
        ;
        var parser: XmlParser = .init(text);
        const b = parse_bitmask(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Bitmask = .{
            .name = "A",
            .value = .{ .type = "VkFlags" },
        };
        try std.testing.expectEqualDeep(expected, b);
    }
    {
        const text =
            \\<type category="bitmask" name="N" alias="A"/>----
        ;
        var parser: XmlParser = .init(text);
        const b = parse_bitmask(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Bitmask = .{
            .name = "N",
            .value = .{ .alias = "A" },
        };
        try std.testing.expectEqualDeep(expected, b);
    }
}

pub const EnumAlias = struct {
    name: []const u8 = &.{},
    alias: []const u8 = &.{},
};

pub fn parse_enum_alias(original_parser: *XmlParser) ?EnumAlias {
    if (!original_parser.check_peek_element_start("type")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var found_category: bool = false;
    var result: EnumAlias = .{};
    if (parser.state == .attribute) {
        while (parser.attribute()) |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                result.name = attr.value;
            } else if (std.mem.eql(u8, attr.name, "alias")) {
                result.alias = attr.value;
            } else if (std.mem.eql(u8, attr.name, "category")) {
                if (!std.mem.eql(u8, attr.value, "enum"))
                    return null
                else
                    found_category = true;
            }
        }
    }
    if (!found_category or result.alias.len == 0) return null;

    original_parser.* = parser;
    return result;
}

test "parse_enum_alias" {
    {
        const text =
            \\<type name="N" category="enum"/>----
        ;
        var parser: XmlParser = .init(text);
        const b = parse_enum_alias(&parser);
        try std.testing.expectEqual(null, b);
    }
    {
        const text =
            \\<type name="N" category="enum" alias="A"/>----
        ;
        var parser: XmlParser = .init(text);
        const b = parse_enum_alias(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: EnumAlias = .{
            .name = "N",
            .alias = "A",
        };
        try std.testing.expectEqualDeep(expected, b);
    }
}

pub const Struct = struct {
    name: []const u8 = &.{},
    alias: ?[]const u8 = null,
    comment: ?[]const u8 = null,
    returnedonly: bool = false,
    extends: ?[]const u8 = null,
    allowduplicate: bool = false,

    members: []const Member = &.{},

    pub const Member = struct {
        value: ?[]const u8 = null,
        api: ?[]const u8 = null,
        // Also known as altlen since actual `len` is a LaTex nonsence
        // How to determine the length of the array of array of arrays
        len: ?[]const u8 = null,
        stride: ?[]const u8 = null,
        deprecated: ?[]const u8 = null,
        externsync: bool = false,
        optional: bool = false,
        // If member is a union, what field selects the union value
        selector: ?[]const u8 = null,
        // If member is a raw u64 handle, which other member specifies what handle it is
        objecttype: ?[]const u8 = null,
        featurelink: ?[]const u8 = null,

        name: []const u8 = &.{},
        type: []const u8 = &.{},
        // In case the type is [4]f32 or [3][4]f32
        dimensions: ?[]const u8 = null,
        pointer: bool = false,
        multi_pointer: bool = false,
        constant: bool = false,
        multi_constant: bool = false,
        comment: ?[]const u8 = null,
    };

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

pub fn parse_struct_member(original_parser: *XmlParser) ?Struct.Member {
    if (!original_parser.check_peek_element_start("member")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Struct.Member = .{};
    if (parser.state == .attribute) {
        parse_attributes("parse_struct_member", false, &parser, &result, &.{
            .{ "values", "value" },
            .{ "api", null },
            .{ "len", "len" },
            .{ "altlen", "len" },
            .{ "stride", null },
            .{ "deprecated", null },
            .{ "externsync", null },
            .{ "optional", null },
            .{ "selector", null },
            .{ "objecttype", null },
            .{ "featurelink", null },
        });
    }
    // skip `vulkansc` members since they just duplicate existing fields for no reason
    if (result.api) |api| if (std.mem.eql(u8, api, "vulkansc")) return null;

    if (parser.peek_text()) |text|
        result.constant = std.mem.indexOf(u8, text, "const") != null;

    parser.skip_to_specific_element_start("type");
    result.type = parser.text() orelse return null;
    parser.skip_to_specific_element_end("type");

    if (parser.peek_text()) |text| {
        if (std.mem.indexOfScalar(u8, text, '*')) |first| {
            result.pointer = true;
            if (std.mem.lastIndexOfScalar(u8, text, '*')) |last| {
                if (first != last) result.multi_pointer = true;
            }
        }
        result.multi_constant = std.mem.indexOf(u8, text, "const") != null;
    }

    parser.skip_to_specific_element_start("name");
    result.name = parser.text() orelse return null;
    parser.skip_to_specific_element_end("name");

    if (parser.peek_text()) |text| {
        _ = parser.text();
        result.dimensions = text;
        // If the length of the array is determined by the CONSTANT, then
        // it is obviously needs to be inside ENUM element
        if (parser.peek_element_start()) |next| {
            if (std.mem.eql(u8, next, "enum")) {
                _ = parser.element_start();
                result.dimensions = parser.text();
                parser.skip_to_specific_element_end("enum");
            }
        }
    }

    if (parser.peek_element_start()) |next| {
        if (std.mem.eql(u8, next, "comment")) {
            _ = parser.element_start();
            result.comment = parser.text();
        }
    }

    parser.skip_to_specific_element_end("member");

    original_parser.* = parser;
    return result;
}

test "parse_struct_member" {
    {
        const text =
            \\<member><type>T</type> <name>N</name><comment>C</comment></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .comment = "C",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member values="V"><type>T</type> <name>N</name><comment>C</comment></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .value = "V",
            .comment = "C",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member noautovalidity="true" optional="true">const <type>T</type>* <name>N</name><comment>C</comment></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .optional = true,
            .pointer = true,
            .constant = true,
            .comment = "C",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member optional="true"><type>T</type> <name>N</name></member>----
        ;
        var parser: XmlParser = .init(text);
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
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .len = "null-terminated",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member len="L">B <type>T</type>* <name>N</name></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .len = "L",
            .pointer = true,
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member len="L,null-terminated">B <type>T</type>* <name>N</name></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .len = "L,null-terminated",
            .pointer = true,
        };
        try std.testing.expectEqualDeep(expected, m);
    }

    {
        const text =
            \\<member len="L,null-terminated" deprecated="I">const <type>T</type>* const*      <name>N</name><comment>C</comment></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .len = "L,null-terminated",
            .pointer = true,
            .multi_pointer = true,
            .constant = true,
            .multi_constant = true,
            .deprecated = "I",
            .comment = "C",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member><type>T</type> <name>N</name>[3][4]</member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .dimensions = "[3][4]",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member len="null-terminated"><type>T</type> <name>N</name>[<enum>L</enum>]</member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .len = "null-terminated",
            .dimensions = "L",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member selector="S"><type>T</type> <name>N</name></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct.Member = .{
            .name = "N",
            .type = "T",
            .selector = "S",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member api="vulkansc"><type>T</type> <name>N</name></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_struct_member(&parser);
        try std.testing.expectEqual(null, m);
    }
}

pub fn parse_struct(alloc: Allocator, original_parser: *XmlParser) !?Struct {
    if (!original_parser.check_peek_element_start("type")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();
    if (parser.state != .attribute) return null;

    var result: Struct = .{};
    const first_attr = parser.attribute().?;
    if (!std.mem.eql(u8, first_attr.name, "category") or
        !std.mem.eql(u8, first_attr.value, "struct"))
        return null;

    parse_attributes("parse_struct", true, &parser, &result, &.{
        .{ "name", null },
        .{ "alias", null },
        .{ "comment", null },
        .{ "returnedonly", null },
        .{ "structextends", "extends" },
        .{ "allowduplicate", null },
    });

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
        var parser: XmlParser = .init(text);
        const s = (try parse_struct(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Struct = .{
            .name = "N",
            .extends = "E",
            .alias = null,
            .members = &.{
                .{ .name = "N1", .type = "T1", .value = "V" },
                .{ .name = "N2", .type = "T2", .optional = true, .pointer = true },
                .{ .name = "N3", .type = "T3" },
                .{ .name = "N4", .type = "T4" },
            },
        };
        try std.testing.expectEqualDeep(expected, s);
    }

    {
        const text =
            \\<type category="struct" name="N" alias="A"/>----
        ;
        var parser: XmlParser = .init(text);
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

pub const Union = struct {
    name: []const u8 = &.{},
    alias: ?[]const u8 = null,
    comment: ?[]const u8 = null,

    members: []const Member = &.{},

    pub const Member = struct {
        len: ?[]const u8 = null,
        // If member is a union, what field selects the union value
        selection: ?[]const u8 = null,

        name: []const u8 = &.{},
        type: []const u8 = &.{},
        // In case the type is [4]f32 or [3][4]f32
        dimensions: ?[]const u8 = null,
        pointer: bool = false,
        constant: bool = false,
    };
};

pub fn parse_union_member(original_parser: *XmlParser) ?Union.Member {
    if (!original_parser.check_peek_element_start("member")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Union.Member = .{};
    if (parser.state == .attribute) {
        parse_attributes("parse_union_member", false, &parser, &result, &.{
            .{ "len", null },
            .{ "selection", null },
        });
    }

    if (parser.peek_text()) |text|
        result.constant = std.mem.indexOf(u8, text, "const") != null;

    parser.skip_to_specific_element_start("type");
    result.type = parser.text() orelse return null;
    parser.skip_to_specific_element_end("type");

    if (parser.peek_text()) |text|
        result.pointer = std.mem.indexOfScalar(u8, text, '*') != null;

    parser.skip_to_specific_element_start("name");
    result.name = parser.text() orelse return null;
    parser.skip_to_specific_element_end("name");

    if (parser.peek_text()) |text| {
        _ = parser.text();
        result.dimensions = text;
    }

    parser.skip_to_specific_element_end("member");

    original_parser.* = parser;
    return result;
}

test "parse_union_member" {
    {
        const text =
            \\<member noautovalidity="true"><type>T</type> <name>N</name></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_union_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Union.Member = .{
            .name = "N",
            .type = "T",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member noautovalidity="true">const <type>T</type>* <name>N</name></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_union_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Union.Member = .{
            .name = "N",
            .type = "T",
            .pointer = true,
            .constant = true,
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member selection="S"><type>T</type> <name>N</name></member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_union_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Union.Member = .{
            .name = "N",
            .type = "T",
            .selection = "S",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<member len="null-terminated"><type>T</type> <name>N</name>[4]</member>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_union_member(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Union.Member = .{
            .name = "N",
            .type = "T",
            .len = "null-terminated",
            .dimensions = "[4]",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
}

pub fn parse_union(alloc: Allocator, original_parser: *XmlParser) !?Union {
    if (!original_parser.check_peek_element_start("type")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();
    if (parser.state != .attribute) return null;

    var result: Union = .{};
    const first_attr = parser.attribute().?;
    if (!std.mem.eql(u8, first_attr.name, "category") or
        !std.mem.eql(u8, first_attr.value, "union"))
        return null;

    parse_attributes("parse_struct", false, &parser, &result, &.{
        .{ "name", null },
        .{ "comment", null },
    });

    var members: std.ArrayListUnmanaged(Union.Member) = .empty;
    while (parse_union_member(&parser)) |member|
        try members.append(alloc, member);
    parser.skip_to_specific_element_end("type");
    result.members = members.items;

    original_parser.* = parser;
    return result;
}

test "parse_single_union" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    {
        const text =
            \\<type category="union" name="N" comment="C">
            \\    <member><type>T1</type> <name>N1</name>[4]</member>
            \\    <member><type>T2</type> <name>N2</name>[4]</member>
            \\    <member><type>T3</type> <name>N3</name>[4]</member>
            \\</type>----
        ;
        var parser: XmlParser = .init(text);
        const s = (try parse_union(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Union = .{
            .name = "N",
            .comment = "C",
            .members = &.{
                .{ .name = "N1", .type = "T1", .dimensions = "[4]" },
                .{ .name = "N2", .type = "T2", .dimensions = "[4]" },
                .{ .name = "N3", .type = "T3", .dimensions = "[4]" },
            },
        };
        try std.testing.expectEqualDeep(expected, s);
    }
}

pub fn parse_types(alloc: Allocator, parser: *XmlParser) !Types {
    if (!parser.check_peek_element_start("types")) return .{};

    _ = parser.element_start();
    _ = parser.skip_attributes();

    var basetypes: std.ArrayListUnmanaged(Basetype) = .empty;
    var handles: std.ArrayListUnmanaged(Handle) = .empty;
    var bitmasks: std.ArrayListUnmanaged(Bitmask) = .empty;
    var enum_aliases: std.ArrayListUnmanaged(EnumAlias) = .empty;
    var structs: std.ArrayListUnmanaged(Struct) = .empty;
    var unions: std.ArrayListUnmanaged(Union) = .empty;
    while (true) {
        if (parse_basetype(parser)) |v| {
            try basetypes.append(alloc, v);
        } else if (parse_handle(parser)) |v| {
            try handles.append(alloc, v);
        } else if (parse_bitmask(parser)) |v| {
            try bitmasks.append(alloc, v);
        } else if (parse_enum_alias(parser)) |v| {
            try enum_aliases.append(alloc, v);
        } else if (try parse_struct(alloc, parser)) |v| {
            try structs.append(alloc, v);
        } else if (try parse_union(alloc, parser)) |v| {
            try unions.append(alloc, v);
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
        .handles = handles.items,
        .bitmasks = bitmasks.items,
        .enum_aliases = enum_aliases.items,
        .structs = structs.items,
        .unions = unions.items,
    };
}

test "parse_types" {
    const text =
        \\<types comment="AAAA">
        \\    <type name="a" category="include">A</type>
        \\        <comment>AAA</comment>
        \\    <type category="include" name="X11/Xlib.h"/>
        \\    <type category="struct" name="A" alias="A"/>
        \\    <type category="struct" name="S">
        \\        <member values="V"><type>T</type> <name>N</name></member>
        \\    </type>
        \\    <type category="union" name="U">
        \\        <member><type>T</type> <name>N</name>[4]</member>
        \\    </type>
        \\    <type requires="R" category="bitmask"><type>T</type><name>N</name>;</type>
        \\</types>----
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var parser: XmlParser = .init(text);
    const types = try parse_types(alloc, &parser);
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);

    const expected: Types = .{
        .basetypes = &.{},
        .bitmasks = &.{.{
            .name = "N",
            .value = .{ .enum_name = "R" },
        }},
        .structs = &.{
            .{
                .name = "A",
                .alias = "A",
                .members = &.{},
            },
            .{
                .name = "S",
                .members = &.{.{ .name = "N", .type = "T", .value = "V" }},
            },
        },
        .unions = &.{.{
            .name = "U",
            .members = &.{.{ .name = "N", .type = "T", .dimensions = "[4]" }},
        }},
    };
    try std.testing.expectEqualDeep(expected, types);
}

pub const Constants = struct {
    items: []const Item = &.{},

    pub const Item = struct {
        value: union(enum) {
            invalid: void,
            u32: u32,
            u64: u64,
            f32: f32,
        } = .invalid,
        name: []const u8 = &.{},
    };
};

pub fn parse_constants_item(original_parser: *XmlParser) !?Constants.Item {
    if (!original_parser.check_peek_element_start("enum")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Constants.Item = .{};
    var type_str: []const u8 = &.{};
    while (parser.attribute()) |attr| {
        if (std.mem.eql(u8, attr.name, "type")) {
            type_str = attr.value;
        } else if (std.mem.eql(u8, attr.name, "value")) {
            if (std.mem.eql(u8, type_str, "uint32_t")) {
                var s = attr.value;
                var inversed: bool = false;
                if (std.mem.startsWith(u8, attr.value, "(~")) {
                    inversed = true;
                    s = s["(~".len .. s.len - "U)".len];
                }
                var value = std.fmt.parseInt(u32, s, 10) catch |e| {
                    std.log.err("Error parsing u32 constant: {s}: {t}", .{ s, e });
                    return e;
                };
                if (inversed) value = ~value;
                result.value = .{ .u32 = value };
            } else if (std.mem.eql(u8, type_str, "uint64_t")) {
                var s = attr.value;
                var inversed: bool = false;
                if (std.mem.startsWith(u8, attr.value, "(~")) {
                    inversed = true;
                    s = s["(~".len .. s.len - "ULL)".len];
                }
                var value = std.fmt.parseInt(u64, s, 10) catch |e| {
                    std.log.err("Error parsing u64 constant: {s}: {t}", .{ s, e });
                    return e;
                };
                if (inversed) value = ~value;
                result.value = .{ .u64 = value };
            } else if (std.mem.eql(u8, type_str, "float")) {
                const value = std.fmt.parseFloat(
                    f32,
                    attr.value[0 .. attr.value.len - 1],
                ) catch |e| {
                    std.log.err("Error parsing f32 constant: {s}: {t}", .{ attr.value, e });
                    return e;
                };
                result.value = .{ .f32 = value };
            } else {
                return null;
            }
        } else if (std.mem.eql(u8, attr.name, "name")) {
            result.name = attr.value;
        }
    }

    original_parser.* = parser;
    return result;
}

test "parse_single_constants_item" {
    {
        const text =
            \\<enum type="uint32_t" value="256" name="A"/>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_constants_item(&parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Constants.Item = .{
            .value = .{ .u32 = 256 },
            .name = "A",
        };
        try std.testing.expectEqualDeep(expected, e);
    }

    {
        const text =
            \\<enum type="uint32_t" value="(~0U)" name="A"/>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_constants_item(&parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Constants.Item = .{
            .value = .{ .u32 = ~@as(u32, 0) },
            .name = "A",
        };
        try std.testing.expectEqualDeep(expected, e);
    }

    {
        const text =
            \\<enum type="float" value="1000.0F" name="A"/>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_constants_item(&parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Constants.Item = .{
            .value = .{ .f32 = 1000.0 },
            .name = "A",
        };
        try std.testing.expectEqualDeep(expected, e);
    }

    {
        const text =
            \\<enum type="uint64_t" value="(~0ULL)" name="A"/>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_constants_item(&parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Constants.Item = .{
            .value = .{ .u64 = ~@as(u64, 0) },
            .name = "A",
        };
        try std.testing.expectEqualDeep(expected, e);
    }
}

pub fn parse_constants(alloc: Allocator, original_parser: *XmlParser) !?Constants {
    if (!original_parser.check_peek_element_start("enums")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();
    if (!parser.skip_to_attribute(.{ .name = "type", .value = "constants" })) return null;

    var result: Constants = undefined;
    _ = parser.skip_attributes();

    var values: std.ArrayListUnmanaged(Constants.Item) = .empty;
    while (true) {
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "enums")) break,
            else => {},
        }
        if (try parse_constants_item(&parser)) |t| {
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

test "parse_constants" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    {
        const text =
            \\<enums name="N" type="constants" comment="C">
            \\    <enum type="uint32_t" value="256"       name="32"/>
            \\    <enum type="uint64_t" value="512"       name="64"/>
            \\    <enum type="uint32_t" value="(~0U)"     name="~32"/>
            \\    <enum type="uint64_t" value="(~0ULL)"   name="~64"/>
            \\    <enum type="float"    value="1000.0F"   name="F"/>
            \\</enums>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_constants(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Constants = .{
            .items = &.{
                .{ .value = .{ .u32 = 256 }, .name = "32" },
                .{ .value = .{ .u64 = 512 }, .name = "64" },
                .{ .value = .{ .u32 = ~@as(u32, 0) }, .name = "~32" },
                .{ .value = .{ .u64 = ~@as(u64, 0) }, .name = "~64" },
                .{ .value = .{ .f32 = 1000.0 }, .name = "F" },
            },
        };
        try std.testing.expectEqualDeep(expected, e);
    }
}

pub const Enum = struct {
    name: []const u8 = &.{},
    type: enum { invalid, @"enum", bitmask } = .invalid,
    comment: ?[]const u8 = null,
    bitwidth: u32 = 0,

    items: []const Item = &.{},

    pub const Item = struct {
        value: union(enum) {
            invalid: void,
            value: i32,
            bitpos: u32,
        } = .invalid,
        name: []const u8 = &.{},
        comment: ?[]const u8 = null,
    };
};

pub fn parse_enum_item(original_parser: *XmlParser) !?Enum.Item {
    if (!original_parser.check_peek_element_start("enum")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Enum.Item = .{};
    while (parser.attribute()) |attr| {
        // if theres is an `api="vulkan"` then this value is deprecated/aliased, so useless
        if (std.mem.eql(u8, attr.name, "api")) {
            return null;
        } else if (std.mem.eql(u8, attr.name, "value")) {
            const value = if (std.mem.startsWith(u8, attr.value, "0x"))
                std.fmt.parseInt(i32, attr.value[2..], 16) catch |e| {
                    std.log.err(
                        "Error parsing enum item value as hext: {s}: {t}",
                        .{ attr.value, e },
                    );
                    return e;
                }
            else
                std.fmt.parseInt(i32, attr.value, 10) catch |e| {
                    std.log.err(
                        "Error parsing enum item value as dec: {s}: {t}",
                        .{ attr.value, e },
                    );
                    return e;
                };
            result.value = .{ .value = value };
        } else if (std.mem.eql(u8, attr.name, "bitpos")) {
            const bitpos = std.fmt.parseInt(u32, attr.value, 10) catch |e| {
                std.log.err("Error parsing enum item bitpos as dec: {s}: {t}", .{ attr.value, e });
                return e;
            };
            result.value = .{ .bitpos = bitpos };
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
        var parser: XmlParser = .init(text);
        const e = (try parse_enum_item(&parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Enum.Item = .{
            .value = .{ .value = 8 },
            .name = "A",
            .comment = null,
        };
        try std.testing.expectEqualDeep(expected, e);
    }
    {
        const text =
            \\<enum value="8" name="A" comment="C"/>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_enum_item(&parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Enum.Item = .{
            .value = .{ .value = 8 },
            .name = "A",
            .comment = "C",
        };
        try std.testing.expectEqualDeep(expected, e);
    }
    {
        const text =
            \\<enum value="0x8" name="A" comment="C"/>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_enum_item(&parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Enum.Item = .{
            .value = .{ .value = 0x8 },
            .name = "A",
            .comment = "C",
        };
        try std.testing.expectEqualDeep(expected, e);
    }
    {
        const text =
            \\<enum bitpos="8" name="A" comment="C"/>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_enum_item(&parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Enum.Item = .{
            .value = .{ .bitpos = 8 },
            .name = "A",
            .comment = "C",
        };
        try std.testing.expectEqualDeep(expected, e);
    }

    {
        const text =
            \\<enum api="vulkan" name="A" alias="B" deprecated="aliased"/>
        ;
        var parser: XmlParser = .init(text);
        const e = try parse_enum_item(&parser);
        try std.testing.expectEqualSlices(u8, text, parser.buffer);
        try std.testing.expectEqual(null, e);
    }
}

pub fn parse_enum(alloc: Allocator, original_parser: *XmlParser) !?Enum {
    if (!original_parser.check_peek_element_start("enums")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Enum = .{};
    result.bitwidth = 32;
    while (parser.attribute()) |attr| {
        if (std.mem.eql(u8, attr.name, "name")) {
            result.name = attr.value;
        } else if (std.mem.eql(u8, attr.name, "type")) {
            if (std.mem.eql(u8, attr.value, "enum"))
                result.type = .@"enum"
            else if (std.mem.eql(u8, attr.value, "bitmask"))
                result.type = .bitmask
            else {
                std.log.warn("Skipping enums block with type: {s}", .{attr.value});
                return null;
            }
        } else if (std.mem.eql(u8, attr.name, "comment")) {
            result.comment = attr.value;
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
        if (try parse_enum_item(&parser)) |t| {
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
            \\<enums name="A" type="bitmask" bitwidth="64">
            \\    <enum bitpos="0" name="B" comment="C"/>
            \\    <enum bitpos="1" name="D" comment="E"/>
            \\    <enum value="3" name="F" comment="G"/>
            \\    <enum value="0x00000069" name="H" comment="I"/>
            \\    <enum api="vulkan"  name="N" alias="T" deprecated="Q"/>
            \\</enums>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_enum(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Enum = .{
            .type = .bitmask,
            .name = "A",
            .bitwidth = 64,
            .items = &.{
                .{ .value = .{ .bitpos = 0 }, .name = "B", .comment = "C" },
                .{ .value = .{ .bitpos = 1 }, .name = "D", .comment = "E" },
                .{ .value = .{ .value = 3 }, .name = "F", .comment = "G" },
                .{ .value = .{ .value = 0x69 }, .name = "H", .comment = "I" },
            },
        };
        try std.testing.expectEqualDeep(expected, e);
    }

    {
        const text =
            \\<enums name="A" type="bitmask">
            \\</enums>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_enum(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Enum = .{
            .type = .bitmask,
            .name = "A",
            .bitwidth = 32,
            .items = &.{},
        };
        try std.testing.expectEqualDeep(expected, e);
    }
}

pub const Command = struct {
    name: []const u8 = &.{},
    alias: ?[]const u8 = null,
    return_type: []const u8 = &.{},

    // tasks
    queues: ?[]const u8 = null,
    successcodes: ?[]const u8 = null,
    errorcodes: ?[]const u8 = null,
    renderpass: ?[]const u8 = null,
    videocoding: ?[]const u8 = null,
    cmdbufferlevel: ?[]const u8 = null,
    // only valid for `vkCmd..`
    conditionalrendering: ?bool = null,
    allownoqueues: bool = false,
    // export
    comment: ?[]const u8 = null,

    parameters: []const Parameter = &.{},

    pub const Parameter = struct {
        name: []const u8 = &.{},
        type: []const u8 = &.{},
        len: ?[]const u8 = null,
        // In case the type is [4]f32 or [3][4]f32
        dimensions: ?[]const u8 = null,
        // If parameter is a pointer to the base type (VkBaseOutStruct), what types can this
        // pointer point to
        valid_structs: ?[]const u8 = null,
        optional: bool = false,
        pointer: bool = false,
        constant: bool = false,
    };
};

pub fn parse_command_parameter(original_parser: *XmlParser) ?Command.Parameter {
    if (!original_parser.check_peek_element_start("param")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Command.Parameter = .{};
    if (parser.state == .attribute) {
        parse_attributes("parse_command_parameter", false, &parser, &result, &.{
            .{ "len", "len" },
            .{ "altlen", "len" },
            .{ "optional", null },
            .{ "validstructs", "valid_structs" },
        });
    }

    if (parser.peek_text()) |text|
        result.constant = std.mem.indexOf(u8, text, "const") != null;

    parser.skip_to_specific_element_start("type");
    result.type = parser.text() orelse return null;
    parser.skip_to_specific_element_end("type");

    if (parser.peek_text()) |text|
        result.pointer = std.mem.indexOfScalar(u8, text, '*') != null;

    parser.skip_to_specific_element_start("name");
    result.name = parser.text() orelse return null;
    parser.skip_to_specific_element_end("name");

    if (parser.peek_text()) |text| {
        _ = parser.text();
        result.dimensions = text;
    }

    parser.skip_to_specific_element_end("param");

    original_parser.* = parser;
    return result;
}

test "parse_command_parameter" {
    {
        const text =
            \\<param><type>T</type> <name>N</name></param>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_command_parameter(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Command.Parameter = .{
            .name = "N",
            .type = "T",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
    {
        const text =
            \\<param len="L">const <type>T</type>* <name>N</name></param>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_command_parameter(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Command.Parameter = .{
            .name = "N",
            .type = "T",
            .len = "L",
            .pointer = true,
            .constant = true,
        };
        try std.testing.expectEqualDeep(expected, m);
    }

    {
        const text =
            \\<param noautovalidity="true" validstructs="S"><type>T</type>* <name>N</name></param>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_command_parameter(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Command.Parameter = .{
            .name = "N",
            .type = "T",
            .valid_structs = "S",
            .pointer = true,
        };
        try std.testing.expectEqualDeep(expected, m);
    }

    {
        const text =
            \\<param><type>T</type> <name>N</name>[4]</param>----
        ;
        var parser: XmlParser = .init(text);
        const m = parse_command_parameter(&parser).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Command.Parameter = .{
            .name = "N",
            .type = "T",
            .dimensions = "[4]",
        };
        try std.testing.expectEqualDeep(expected, m);
    }
}

pub fn parse_command(alloc: Allocator, original_parser: *XmlParser) !?Command {
    if (!original_parser.check_peek_element_start("command")) return null;

    var parser = original_parser.*;
    _ = parser.element_start();

    var result: Command = .{};
    while (parser.attribute()) |attr| {
        if (std.mem.eql(u8, attr.name, "name")) {
            result.name = attr.value;
        } else if (std.mem.eql(u8, attr.name, "alias")) {
            result.alias = attr.value;
        } else if (std.mem.eql(u8, attr.name, "queues")) {
            result.queues = attr.value;
        } else if (std.mem.eql(u8, attr.name, "successcodes")) {
            result.successcodes = attr.value;
        } else if (std.mem.eql(u8, attr.name, "errorcodes")) {
            result.errorcodes = attr.value;
        } else if (std.mem.eql(u8, attr.name, "renderpass")) {
            result.renderpass = attr.value;
        } else if (std.mem.eql(u8, attr.name, "videocoding")) {
            result.videocoding = attr.value;
        } else if (std.mem.eql(u8, attr.name, "cmdbufferlevel")) {
            result.cmdbufferlevel = attr.value;
        } else if (std.mem.eql(u8, attr.name, "conditionalrendering")) {
            result.conditionalrendering = std.mem.eql(u8, attr.value, "true");
        } else if (std.mem.eql(u8, attr.name, "allownoqueues")) {
            result.allownoqueues = std.mem.eql(u8, attr.value, "true");
        } else if (std.mem.eql(u8, attr.name, "comment")) {
            result.comment = attr.value;
        }
    }

    // If definition is not an alias
    if (result.alias == null) {
        parser.skip_to_specific_element_start("type");
        result.return_type = parser.text() orelse return null;
        parser.skip_to_specific_element_start("name");
        result.name = parser.text() orelse return null;
        parser.skip_to_specific_element_end("proto");

        var values: std.ArrayListUnmanaged(Command.Parameter) = .empty;
        while (true) {
            switch (parser.peek_next() orelse break) {
                .element_end => |es| if (std.mem.eql(u8, es, "command")) break,
                else => {},
            }
            if (parse_command_parameter(&parser)) |t| {
                try values.append(alloc, t);
            } else {
                parser.skip_current_element();
            }
        }
        _ = parser.next();
        result.parameters = values.items;
    }

    original_parser.* = parser;
    return result;
}

test "parse_command" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    {
        const text =
            \\<command export="E" successcodes="S" errorcodes="E">
            \\    <proto><type>R</type> <name>A</name></proto>
            \\    <param><type>T1</type> <name>B</name></param>
            \\    <param><type>T2</type> <name>C</name></param>
            \\    <implicitexternsyncparams>
            \\        <param>P</param>
            \\    </implicitexternsyncparams>
            \\</command>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_command(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Command = .{
            .name = "A",
            .return_type = "R",
            .successcodes = "S",
            .errorcodes = "E",
            .parameters = &.{
                .{ .name = "B", .type = "T1" },
                .{ .name = "C", .type = "T2" },
            },
        };
        try std.testing.expectEqualDeep(expected, e);
    }

    {
        const text =
            \\<command name="N" alias="A"/>----
        ;
        var parser: XmlParser = .init(text);
        const e = (try parse_command(alloc, &parser)).?;
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
        const expected: Command = .{
            .name = "N",
            .alias = "A",
        };
        try std.testing.expectEqualDeep(expected, e);
    }
}

pub fn parse_commands(alloc: Allocator, parser: *XmlParser) !std.ArrayListUnmanaged(Command) {
    if (!parser.check_peek_element_start("commands")) return .{};

    _ = parser.element_start();
    _ = parser.skip_attributes();

    var commands: std.ArrayListUnmanaged(Command) = .empty;
    while (true) {
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "commands")) break,
            else => {},
        }

        if (try parse_command(alloc, parser)) |ext|
            try commands.append(alloc, ext)
        else
            parser.skip_current_element();
    }
    _ = parser.next();
    return commands;
}

test "parse_commands" {
    const text =
        \\<commands comment="C">
        \\    <command export="E1" successcodes="S" errorcodes="E">
        \\        <proto><type>T1</type> <name>N1</name></proto>
        \\        <param><type>T2</type>* <name>N2</name></param>
        \\        <param>const <type>T3</type>* <name>N3</name></param>
        \\    </command>
        \\    <command export="E2">
        \\        <proto><type>T4</type> <name>N4</name></proto>
        \\        <param optional="true" externsync="true"><type>T5</type> <name>N5</name></param>
        \\        <implicitexternsyncparams>
        \\            <param>P</param>
        \\        </implicitexternsyncparams>
        \\    </command>
        \\</commands>----
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    var parser: XmlParser = .init(text);
    const e = try parse_commands(alloc, &parser);
    try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    const expected: []const Command = &.{
        .{
            .name = "N1",
            .return_type = "T1",
            .successcodes = "S",
            .errorcodes = "E",
            .parameters = &.{
                .{ .name = "N2", .type = "T2", .pointer = true },
                .{ .name = "N3", .type = "T3", .pointer = true, .constant = true },
            },
        },
        .{
            .name = "N4",
            .return_type = "T4",
            .parameters = &.{
                .{ .name = "N5", .type = "T5", .optional = true },
            },
        },
    };
    try std.testing.expectEqualDeep(expected, e.items);
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

pub fn parse_spirv_extension(original_parser: *XmlParser) ?Spirv.Extension {
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
        var parser: XmlParser = .init(text);
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
        var parser: XmlParser = .init(text);
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

pub fn parse_spirv_capability(alloc: Allocator, original_parser: *XmlParser) !?Spirv.Capability {
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
        var parser: XmlParser = .init(text);
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
        var parser: XmlParser = .init(text);
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
        var parser: XmlParser = .init(text);
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
        var parser: XmlParser = .init(text);
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

pub fn parse_spirv(alloc: Allocator, parser: *XmlParser) !Spirv {
    if (!parser.check_peek_element_start("spirvextensions")) return .{};
    _ = parser.element_start();
    _ = parser.skip_attributes();

    var extensions: std.ArrayListUnmanaged(Spirv.Extension) = .empty;
    while (true) {
        switch (parser.peek_next() orelse break) {
            .element_end => |es| if (std.mem.eql(u8, es, "spirvextensions")) break,
            else => {},
        }

        if (parse_spirv_extension(parser)) |v|
            try extensions.append(alloc, v)
        else
            parser.skip_current_element();
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

        if (try parse_spirv_capability(alloc, parser)) |v|
            try capabilities.append(alloc, v)
        else
            parser.skip_current_element();
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

    var parser: XmlParser = .init(text);
    const s = try parse_spirv(alloc, &parser);
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
