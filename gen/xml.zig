const std = @import("std");

pub const Parser = struct {
    buffer: []const u8,
    state: State,

    const State = enum {
        element,
        attribute,
    };

    const Token = union(enum) {
        text: []const u8,
        element_empty: []const u8,
        element_start: []const u8,
        element_end: []const u8,
        attribute: struct { name: []const u8, value: []const u8 },
    };

    const Self = @This();
    pub fn init(buffer: []const u8) Self {
        return .{
            .buffer = buffer,
            .state = .element,
        };
    }

    pub fn skip_whitespace(self: *Self) void {
        while (self.buffer.len != 0 and std.ascii.isWhitespace(self.buffer[0]))
            self.buffer = self.buffer[1..];
    }

    pub fn peek(self: *const Self, advance: usize) ?u8 {
        if (self.buffer.len < advance + 1) return null;
        return self.buffer[advance];
    }

    pub fn trim_attribute_value(buffer: []const u8) []const u8 {
        const open_quote = buffer[0];
        const end_quote_index =
            std.mem.indexOfScalar(u8, buffer[1..], open_quote) orelse unreachable;
        return buffer[1 .. end_quote_index + 1];
    }

    pub fn next(self: *Self) ?Token {
        while (true) {
            self.skip_whitespace();
            switch (self.state) {
                .element => {
                    switch (self.peek(0) orelse return null) {
                        '<' => {
                            switch (self.peek(1) orelse return null) {
                                '?' => {
                                    const buffer = self.buffer[2..];
                                    const index =
                                        std.mem.indexOf(u8, buffer, "?>") orelse return null;
                                    self.buffer = buffer[index + 2 ..];
                                },
                                '/' => {
                                    const buffer = self.buffer[2..];
                                    const index =
                                        std.mem.indexOfScalar(u8, buffer, '>') orelse return null;
                                    const token: Token =
                                        .{ .element_end = buffer[0..index] };
                                    self.buffer = buffer[index + 1 ..];
                                    return token;
                                },
                                '!' => {
                                    const buffer = self.buffer[4..];
                                    const index =
                                        std.mem.indexOf(u8, buffer, "-->") orelse return null;
                                    self.buffer = buffer[index + 3 ..];
                                },
                                else => {
                                    const buffer = self.buffer[1..];
                                    const buffer_end =
                                        std.mem.indexOfScalar(u8, buffer, '>') orelse return null;
                                    const element_buffer = buffer[0..buffer_end];

                                    if (std.mem.indexOfScalar(u8, element_buffer, ' ')) |index| {
                                        const token: Token =
                                            .{ .element_start = element_buffer[0..index] };
                                        self.buffer = buffer[index + 1 ..];
                                        self.state = .attribute;
                                        return token;
                                    }
                                    if (std.mem.indexOfScalar(u8, element_buffer, '/')) |index| {
                                        const token: Token =
                                            .{ .element_empty = buffer[0..index] };
                                        self.buffer = buffer[index + 1 ..];
                                        return token;
                                    }

                                    const token: Token =
                                        .{ .element_start = element_buffer };
                                    self.buffer = buffer[buffer_end + 1 ..];
                                    return token;
                                },
                            }
                        },
                        '>' => {
                            const buffer = self.buffer[1..];
                            const index = std.mem.indexOfScalar(u8, buffer, '>') orelse return null;
                            const token: Token =
                                .{ .element_end = buffer[0..index] };
                            self.buffer = buffer[index + 1 ..];
                            return token;
                        },
                        else => {
                            const index =
                                std.mem.indexOfScalar(u8, self.buffer[1..], '<') orelse return null;
                            const token: Token =
                                .{ .text = self.buffer[0 .. index + 1] };
                            self.buffer = self.buffer[index + 1 ..];
                            return token;
                        },
                    }
                },
                .attribute => {
                    switch (self.peek(0) orelse return null) {
                        '/' => {
                            self.buffer = self.buffer[2..];
                            self.state = .element;
                            continue;
                        },
                        '>' => {
                            self.buffer = self.buffer[1..];
                            self.state = .element;
                            continue;
                        },
                        else => {},
                    }
                    const eq_index =
                        std.mem.indexOfScalar(u8, self.buffer, '=') orelse return null;
                    const name = self.buffer[0..eq_index];
                    const value = trim_attribute_value(self.buffer[eq_index + 1 ..]);
                    const token: Token =
                        .{ .attribute = .{ .name = name, .value = value } };
                    self.buffer = self.buffer[name.len + 1 + value.len + 2 ..];
                    return token;
                },
            }
        }
    }
};
