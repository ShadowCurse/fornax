// Copyright (c) 2025 Egor Lazarchuk
// SPDX-License-Identifier: MIT

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const RemainingArgs = struct { values: []const [*:0]const u8 = &.{} };

pub fn parse(comptime T: type, alloc: Allocator) !T {
    const type_fields = @typeInfo(T).@"struct".fields;

    var t: T = .{};
    // Track which args were consumed, including the 0th arg.
    var consumed_args: u64 = 0;
    inline for (type_fields, 0..) |field, field_idx| {
        if (field.type == RemainingArgs) {
            if (field_idx != type_fields.len - 1)
                @compileError("The LastArgs valum must be last in the args type definition");
            const remaining_args_len = std.os.argv.len - 1 - @popCount(consumed_args);
            const remaining_args = try alloc.alloc([*:0]const u8, remaining_args_len);
            var remaining_args_idx: u32 = 0;
            for (std.os.argv[1..], 1..) |arg, i| {
                if (consumed_args & @as(u64, 1) << @truncate(i) == 0) {
                    remaining_args[remaining_args_idx] = arg;
                    remaining_args_idx += 1;
                }
            }
            @field(t, field.name).values = remaining_args;
        } else if (find_arg(field)) |r| {
            const i, const arg = r;
            switch (field.type) {
                void => {
                    consumed_args |= @as(u64, 1) << @truncate(i);
                },
                bool => {
                    consumed_args |= @as(u64, 1) << @truncate(i);
                    @field(t, field.name) = true;
                },
                ?i32 => {
                    consumed_args |= @as(u64, 1) << @truncate(i);
                    consumed_args |= @as(u64, 1) << @truncate(i + 1);
                    @field(t, field.name) = try std.fmt.parseInt(i32, arg, 10);
                },
                ?u32 => {
                    consumed_args |= @as(u64, 1) << @truncate(i);
                    consumed_args |= @as(u64, 1) << @truncate(i + 1);
                    @field(t, field.name) = try std.fmt.parseInt(u32, arg, 10);
                },
                ?[]const u8 => {
                    consumed_args |= @as(u64, 1) << @truncate(i);
                    consumed_args |= @as(u64, 1) << @truncate(i + 1);
                    @field(t, field.name) = arg;
                },
                else => unreachable,
            }
        }
    }
    return t;
}

fn find_arg(comptime field: std.builtin.Type.StructField) ?struct { u32, []const u8 } {
    const name = std.fmt.comptimePrint("--{s}", .{field.name});
    var arg_name: [name.len]u8 = undefined;
    _ = std.mem.replace(u8, name, "_", "-", &arg_name);

    var args_iter = std.process.args();
    // skip the binary name
    _ = args_iter.next();
    var i: u32 = 1;
    while (args_iter.next()) |arg| : (i += 1) {
        if (std.mem.eql(u8, arg, &arg_name)) {
            return switch (field.type) {
                void, bool => .{ i, field.name },
                else => if (args_iter.next()) |next| .{ i, next } else null,
            };
        }
    }
    return null;
}

pub fn print_help(comptime T: type) !void {
    const type_fields = comptime @typeInfo(T).@"struct".fields;

    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const writer = &stdout_writer.interface;
    defer writer.flush() catch unreachable;
    try writer.print("Usage:\n", .{});

    inline for (type_fields) |field| {
        const name = std.fmt.comptimePrint("--{s}", .{field.name});
        var arg_name: [name.len]u8 = undefined;
        _ = std.mem.replace(u8, name, "_", "-", &arg_name);
        try writer.print("\t{s}\n", .{arg_name});
    }
}
