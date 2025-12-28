const std = @import("std");

buffer: []const u8,
state: State,

const State = enum {
    element,
    attribute,
};

pub const Token = union(enum) {
    // text
    text: []const u8,
    // <element/>
    element_empty: []const u8,
    // <element>
    element_start: []const u8,
    // </element>
    element_end: []const u8,
    // name="value"
    attribute: Attribute,
    // ... >
    attribute_list_end: void,
    // ... />
    attribute_list_end_contained: void,
};

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
};

const Self = @This();
pub fn init(buffer: []const u8) Self {
    return .{
        .buffer = buffer,
        .state = .element,
    };
}

pub fn trim_attribute_value(buffer: []const u8) []const u8 {
    const open_quote = buffer[0];
    const end_quote_index =
        std.mem.indexOfScalar(u8, buffer[1..], open_quote) orelse unreachable;
    return buffer[1 .. end_quote_index + 1];
}

pub fn peek_next(self: *const Self) ?Token {
    if (self.peek_next_internal()) |tuple| {
        const token, _ = tuple;
        return token;
    } else return null;
}

pub fn next(self: *Self) ?Token {
    if (self.peek_next_internal()) |tuple| {
        const token, const new_self = tuple;
        self.* = new_self;
        return token;
    } else return null;
}

fn skip_whitespace(self: *Self) void {
    while (self.buffer.len != 0 and std.ascii.isWhitespace(self.buffer[0]))
        self.buffer = self.buffer[1..];
}

fn peek(self: *const Self, advance: usize) ?u8 {
    if (self.buffer.len < advance + 1) return null;
    return self.buffer[advance];
}

fn peek_next_internal(self: *const Self) ?struct { Token, Self } {
    var new_self = self.*;
    while (true) {
        new_self.skip_whitespace();
        switch (new_self.state) {
            .element => {
                switch (new_self.peek(0) orelse return null) {
                    '<' => {
                        switch (new_self.peek(1) orelse return null) {
                            '?' => {
                                const buffer = new_self.buffer[2..];
                                const index =
                                    std.mem.indexOf(u8, buffer, "?>") orelse return null;
                                new_self.buffer = buffer[index + 2 ..];
                            },
                            '/' => {
                                const buffer = new_self.buffer[2..];
                                const index =
                                    std.mem.indexOfScalar(u8, buffer, '>') orelse return null;
                                const token: Token =
                                    .{ .element_end = buffer[0..index] };
                                new_self.buffer = buffer[index + 1 ..];
                                return .{ token, new_self };
                            },
                            '!' => {
                                const buffer = new_self.buffer[4..];
                                const index =
                                    std.mem.indexOf(u8, buffer, "-->") orelse return null;
                                new_self.buffer = buffer[index + 3 ..];
                            },
                            else => {
                                const buffer = new_self.buffer[1..];
                                const buffer_end =
                                    std.mem.indexOfScalar(u8, buffer, '>') orelse return null;
                                const element_buffer = buffer[0..buffer_end];

                                if (std.mem.indexOfScalar(u8, element_buffer, ' ')) |index| {
                                    const token: Token =
                                        .{ .element_start = element_buffer[0..index] };
                                    new_self.buffer = buffer[index + 1 ..];
                                    new_self.state = .attribute;
                                    return .{ token, new_self };
                                }
                                if (std.mem.indexOfScalar(u8, element_buffer, '/')) |index| {
                                    const token: Token =
                                        .{ .element_empty = buffer[0..index] };
                                    new_self.buffer = buffer[index + 1 ..];
                                    return .{ token, new_self };
                                }

                                const token: Token =
                                    .{ .element_start = element_buffer };
                                new_self.buffer = buffer[buffer_end + 1 ..];
                                return .{ token, new_self };
                            },
                        }
                    },
                    '>' => {
                        const buffer = new_self.buffer[1..];
                        const index = std.mem.indexOfScalar(u8, buffer, '>') orelse
                            return null;
                        const token: Token =
                            .{ .element_end = buffer[0..index] };
                        new_self.buffer = buffer[index + 1 ..];
                        return .{ token, new_self };
                    },
                    else => {
                        const index = std.mem.indexOfScalar(u8, new_self.buffer[1..], '<') orelse
                            return null;
                        const token: Token =
                            .{ .text = new_self.buffer[0 .. index + 1] };
                        new_self.buffer = new_self.buffer[index + 1 ..];
                        return .{ token, new_self };
                    },
                }
            },
            .attribute => {
                switch (new_self.peek(0) orelse return null) {
                    '/' => {
                        new_self.buffer = new_self.buffer[2..];
                        new_self.state = .element;
                        return .{ .attribute_list_end_contained, new_self };
                    },
                    '>' => {
                        new_self.buffer = new_self.buffer[1..];
                        new_self.state = .element;
                        return .{ .attribute_list_end, new_self };
                    },
                    else => {},
                }
                const eq_index =
                    std.mem.indexOfScalar(u8, new_self.buffer, '=') orelse return null;
                const name = new_self.buffer[0..eq_index];
                const value = trim_attribute_value(new_self.buffer[eq_index + 1 ..]);
                const token: Token =
                    .{ .attribute = .{ .name = name, .value = value } };
                new_self.buffer = new_self.buffer[name.len + 1 + value.len + 2 ..];
                return .{ token, new_self };
            },
        }
    }
}

pub fn peek_text(self: *Self) ?[]const u8 {
    switch (self.peek_next() orelse return null) {
        .text => |v| return v,
        else => return null,
    }
}

pub fn text(self: *Self) ?[]const u8 {
    switch (self.next() orelse return null) {
        .text => |v| return v,
        else => return null,
    }
}

pub fn skip_text(self: *Self) ?[]const u8 {
    switch (self.peek_next() orelse return null) {
        .text => switch (self.next().?) {
            .text => |v| return v,
            else => unreachable,
        },
        else => return null,
    }
}

pub fn peek_element_start(self: *Self) ?[]const u8 {
    switch (self.peek_next() orelse return null) {
        .element_start => |v| return v,
        else => return null,
    }
}

pub fn check_peek_element_start(self: *Self, start: []const u8) bool {
    const es = self.peek_element_start() orelse return false;
    if (!std.mem.eql(u8, es, start)) return false;
    return true;
}

pub fn element_start(self: *Self) ?[]const u8 {
    switch (self.next() orelse return null) {
        .element_start => |v| return v,
        else => return null,
    }
}

pub fn peek_element_end(self: *Self) ?[]const u8 {
    switch (self.peek_next() orelse return null) {
        .element_end => |v| return v,
        else => return null,
    }
}

pub fn element_end(self: *Self) ?[]const u8 {
    switch (self.next() orelse return null) {
        .element_end => |v| return v,
        else => return null,
    }
}

pub fn peek_attribute(self: *Self) ?Attribute {
    switch (self.peek_next() orelse return null) {
        .attribute => |attr| return attr,
        else => return null,
    }
}

pub fn skip_to_attribute(self: *Self, searh_attr: Attribute) bool {
    while (self.attribute()) |attr| {
        if (std.mem.eql(u8, attr.name, searh_attr.name) and
            std.mem.eql(u8, attr.value, searh_attr.value))
            return true;
    }
    return false;
}

pub fn attribute(self: *Self) ?Attribute {
    switch (self.next() orelse return null) {
        .attribute => |attr| return attr,
        else => return null,
    }
}

pub fn skip_current_element(self: *Self) void {
    const es = self.element_start() orelse return;
    self.skip_element(es);
}

pub fn skip_element(self: *Self, element: []const u8) void {
    if (self.skip_attributes()) |sa|
        if (sa == .attribute_list_end_contained)
            return;
    var depth: u32 = 0;
    while (self.next()) |n| {
        switch (n) {
            .element_start => |es| {
                if (self.skip_attributes()) |sa| {
                    if (sa == .attribute_list_end)
                        depth += 1;
                } else {
                    depth += 1;
                }
                _ = es;
            },
            .element_end => |ee| {
                if (std.mem.eql(u8, ee, element) and depth == 0) return;
                depth -= 1;
            },
            else => {},
        }
    }
}

pub fn skip_to_specific_element_start(self: *Self, element: []const u8) void {
    while (self.next()) |n| {
        switch (n) {
            .element_start => |v| if (std.mem.eql(u8, v, element)) return,
            else => {},
        }
    }
}

pub fn skip_to_specific_element_end(self: *Self, element: []const u8) void {
    while (self.next()) |n| {
        switch (n) {
            .element_end => |v| if (std.mem.eql(u8, v, element)) return,
            else => {},
        }
    }
}

pub fn skip_attributes(self: *Self) ?Token {
    if (self.state != .attribute) return null;
    while (self.next()) |n| {
        switch (n) {
            .attribute_list_end, .attribute_list_end_contained => return n,
            else => {},
        }
    }
    return null;
}

test "skip_element" {
    {
        const xml =
            \\<element smth="smth">
            \\    <other a="b" c="d"/>
            \\    some text
            \\    <other a="b" c="d">
            \\        some other text
            \\    </other>
            \\</element>----
        ;
        var parser: Self = .init(xml);
        parser.skip_element("element");
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    }
    {
        const xml =
            \\<element>
            \\    some text
            \\</element>----
        ;
        var parser: Self = .init(xml);
        parser.skip_element("element");
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    }
    {
        const xml =
            \\<element a="b" c="d"/>----
        ;
        var parser: Self = .init(xml);
        parser.skip_element("element");
        try std.testing.expectEqualSlices(u8, "----", parser.buffer);
    }
}
