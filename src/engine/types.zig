const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

// LSB (bit 0) - a1, MSB (bit 63) - h8.
pub const Bitboard = u64;

inline fn bitboard_from_idx(idx: u8) Bitboard {
    return @as(Bitboard, 1) << @intCast(idx);
}

pub fn print_bitboard(board: Bitboard) void {
    std.debug.print("-" ** 33, .{});
    std.debug.print("\n", .{});
    for (0..8) |r| {
        std.debug.print("|", .{});
        for (0..8) |f| {
            const idx: u8 = @intCast((7 - r) * 8 + f);
            const mask = bitboard_from_idx(idx);
            const c: u8 = if (board & mask == 0) ' ' else 'X';
            std.debug.print(" {c} |", .{c});
        }
        std.debug.print("\n", .{});
        std.debug.print("-" ** 33, .{});
        std.debug.print("\n", .{});
    }
}

pub const Color = enum(u1) {
    White,
    Black,

    pub fn idx(self: Color) usize {
        return @intFromEnum(self);
    }

    // get the opposite color
    pub fn opp(self: Color) Color {
        if (self == .White) return .Black;
        return .White;
    }

    pub fn pawn_direction(self: Color) i3 {
        return if (self == .White) 1 else -1;
    }

    pub fn start_rank(self: Color) u3 {
        return if (self == .White) 0 else 7;
    }

    pub fn end_rank(self: Color) u3 {
        return if (self == .White) 7 else 0;
    }

    pub fn symbol(self: Color) u8 {
        if (self == .White) return 'W' else return 'B';
    }
};

// square address 0-63
pub const Square = enum(u8) {
    // zig fmt: off
    a1, b1, c1, d1, e1, f1, g1, h1,
    a2, b2, c2, d2, e2, f2, g2, h2,
    a3, b3, c3, d3, e3, f3, g3, h3,
    a4, b4, c4, d4, e4, f4, g4, h4,
    a5, b5, c5, d5, e5, f5, g5, h5,
    a6, b6, c6, d6, e6, f6, g6, h6,
    a7, b7, c7, d7, e7, f7, g7, h7,
    a8, b8, c8, d8, e8, f8, g8, h8,
    // zig fmt: on

    pub fn from_int(val: anytype) Square {
        return @enumFromInt(val);
    }

    pub fn as_usize(self: Square) usize {
        return @as(usize, @intFromEnum(self));
    }

    pub fn value(self: Square) u8 {
        return @intFromEnum(self);
    }

    pub fn file(self: Square) u3 {
        return @truncate(self.value() % 8);
    }

    pub fn rank(self: Square) u3 {
        return @truncate(self.value() / 8);
    }

    pub fn file_str(self: Square) u8 {
        return @as(u8, 'a') + self.file();
    }

    pub fn rank_str(self: Square) u8 {
        return @as(u8, '1') + self.rank();
    }

    pub fn str(self: Square) [2]u8 {
        return .{
            self.file_str(),
            self.rank_str(),
        };
    }

    // locate a square shifted relative to the current one, null if out of bounds
    pub fn rel(self: Square, file_shift: i8, rank_shift: i8) ?Square {
        const target_rank: i16 = self.rank() + rank_shift;
        if (target_rank < 0 or target_rank > 7) return null;

        const target_file: i16 = self.file() + file_shift;
        if (target_file < 0 or target_file > 7) return null;

        return @enumFromInt(target_rank * 8 + target_file);
    }

    // get bitmask for bitwise operations with bitboard
    pub fn mask(self: Square) Bitboard {
        return bitboard_from_idx(self.value());
    }
};

test "square values" {
    const cases = [_]struct { square: Square, expected: u8, expected_str: *const [2]u8 }{
        .{ .square = .a1, .expected = 0, .expected_str = "a1" },
        .{ .square = .h8, .expected = 63, .expected_str = "h8" },
        .{ .square = .c2, .expected = 10, .expected_str = "c2" },
    };

    for (cases) |case| {
        try t.expectEqual(case.expected, case.square.value());
        try t.expectEqualStrings(case.expected_str, &case.square.str());
    }
}

pub const PieceType = enum(u3) {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,
    NO_PIECE_TYPE,

    pub fn symbol(self: PieceType, color: Color) u21 {
        return switch (color) {
            .Black => switch (self) {
                PieceType.Pawn => 0x2659,
                PieceType.Knight => 0x2658,
                PieceType.Bishop => 0x2657,
                PieceType.Rook => 0x2656,
                PieceType.Queen => 0x2655,
                PieceType.King => 0x2654,
                else => unreachable,
            },
            .White => switch (self) {
                PieceType.Pawn => 0x265F,
                PieceType.Knight => 0x265E,
                PieceType.Bishop => 0x265D,
                PieceType.Rook => 0x265C,
                PieceType.Queen => 0x265B,
                PieceType.King => 0x265A,
                else => unreachable,
            },
        };
    }

    fn char(self: PieceType) u8 {
        return switch (self) {
            .Knight => 'n',
            .Bishop => 'b',
            .Rook => 'r',
            .Queen => 'q',
            else => unreachable,
        };
    }

    pub fn idx(self: PieceType) usize {
        return @intFromEnum(self);
    }
};

pub const PieceTypes = [_]PieceType{
    PieceType.Pawn,
    PieceType.Knight,
    PieceType.Bishop,
    PieceType.Rook,
    PieceType.Queen,
    PieceType.King,
};

pub const PromotionPieceTypes = [_]PieceType{
    PieceType.Knight,
    PieceType.Bishop,
    PieceType.Rook,
    PieceType.Queen,
};

pub const MoveType = enum(u2) {
    NORMAL,
    CAPTURE,
    CASTLE,
};

pub const Move = struct {
    piece: PieceType,
    from: Square,
    to: Square,
    move_type: MoveType = .NORMAL,
    captured_piece: PieceType = .NO_PIECE_TYPE,
    promotion_piece: PieceType = .NO_PIECE_TYPE,

    pub fn uci(self: Move, buffer: *[5]u8) []const u8 {
        buffer[0] = self.from.file_str();
        buffer[1] = self.from.rank_str();
        buffer[2] = self.to.file_str();
        buffer[3] = self.to.rank_str();

        if (self.promotion_piece == .NO_PIECE_TYPE) return buffer[0..4];

        buffer[4] = self.promotion_piece.char();
        return buffer[0..5];
    }

    pub fn equals(self: Move, other: Move) bool {
        // move_type and pieces can probably be omitted here
        return (self.from == other.from and self.to == other.to and self.promotion_piece == other.promotion_piece);
    }

    pub fn equalsUci(self: Move, val: []const u8) bool {
        if (val.len != 4 and val.len != 5) std.debug.panic("invalid uci: {s}\n", .{val});

        if (!std.mem.eql(u8, val[0..2], &self.from.str())) return false;
        if (!std.mem.eql(u8, val[2..4], &self.to.str())) return false;

        if (self.promotion_piece != .NO_PIECE_TYPE) {
            if (val.len != 5) return false;
            if (val[4] != self.promotion_piece.char()) return false;
        } else if (val.len != 4) {
            return false;
        }

        return true;
    }
};

pub const CastleSide = enum(u1) {
    short,
    long,

    pub fn idx(self: CastleSide) u1 {
        return @intFromEnum(self);
    }
};

pub const CastlingRights = struct {
    bits: u4 = 0b1111,

    fn bit(color: Color, side: CastleSide) u4 {
        return @as(u4, 1) << @intCast(color.idx() * 2 + side.idx());
    }

    pub fn has(self: CastlingRights, color: Color, side: CastleSide) bool {
        return self.bits & bit(color, side) != 0;
    }

    pub fn revoke(self: *CastlingRights, color: Color, side: CastleSide) bool {
        const _bit = bit(color, side);
        if (self.bits & _bit == 0) return false;
        self.bits &= ~_bit;

        return true;
    }

    // for fen parsing only
    pub fn grant(self: *CastlingRights, color: Color, side: CastleSide) void {
        self.bits |= bit(color, side);
    }
};
