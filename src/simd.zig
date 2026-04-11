// Copyright (c) 2026 Egor Lazarchuk
// SPDX-License-Identifier: MIT

const std = @import("std");

pub const m128i = @Vector(2, u64);
pub const u8x16 = @Vector(16, u8);
pub const u8x32 = @Vector(32, u8);
pub const u8x64 = @Vector(64, u8);

// PCLMULQDQ - Carry-less multiplication
pub inline fn pclmulqdq(a: m128i, b: m128i, comptime mask: u64) m128i {
    const assembly = std.fmt.comptimePrint("pclmulqdq ${d}, %[b], %[a]", .{mask});
    return asm volatile (assembly
        : [ret] "=x" (-> m128i),
        : [a] "0" (a),
          [b] "x" (b),
    );
}

// Shift the whole 16 bytes right by `bytes` nuber of bytes
pub inline fn shift_right(a: m128i, comptime bytes: u8) m128i {
    const b: @Vector(16, u8) = @bitCast(a);
    // The `shift left` is because shift is done with a @shuffle
    // with selection mask shifted by `bytes` to the left
    // orig:      0 [ 0 0 0 0 a b c   d ]
    // shuffle: [ 0   0 0 0 0 a b c ] d
    // final:   [0 0 0 0 0 a b c]
    const c = std.simd.shiftElementsLeft(b, bytes, 0);
    return @bitCast(c);
}

// VPSHUFB - Packed Shuffle Bytes
pub inline fn vpshufb_128(table: u8x16, indices: u8x16) u8x16 {
    return asm volatile ("vpshufb %[indices], %[table], %[ret]"
        : [ret] "=x" (-> u8x16),
        : [table] "x" (table),
          [indices] "x" (indices),
    );
}

/// VPSHUFB - Packed Shuffle Bytes
pub inline fn vpshufb_256(table: u8x32, indices: u8x32) u8x32 {
    return asm volatile ("vpshufb %[indices], %[table], %[ret]"
        : [ret] "=x" (-> u8x32),
        : [table] "x" (table),
          [indices] "x" (indices),
    );
}

/// VPMOVMSKB - Move byte mask to integer
pub inline fn vpmovmskb_256(v: u8x32) u32 {
    return asm volatile ("vpmovmskb %[v], %[ret]"
        : [ret] "=r" (-> u32),
        : [v] "x" (v),
    );
}

/// Prefix XOR using CLMUL
/// Each bit in result = XOR of all bits at positions <= i in input
pub inline fn prefix_xor(mask: u64) u64 {
    const all_ones = m128i{ 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF };
    const input = m128i{ mask, 0 };
    const result = pclmulqdq(input, all_ones, 0x00);
    return result[0];
}

test "prefix_xor" {
    const mask: u64 = 0b100001;
    const result = prefix_xor(mask);
    try std.testing.expectEqual(@as(u64, 0b011111), result);
}

test "prefix_xor_multiple_strings" {
    const mask: u64 = 0b100100101;
    const result = prefix_xor(mask);
    try std.testing.expectEqual(@as(u64, 0b011100011), result);
}
