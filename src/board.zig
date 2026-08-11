const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

pub const GameError = error{
    InvalidMove,
    IllegalMove,
    InvalidFEN,
};

// LSB (bit 0) - a1, MSB (bit 63) - h8.
pub const Bitboard = u64;

inline fn idx_to_bitboard(idx: u8) Bitboard {
    return @as(Bitboard, 1) << @intCast(idx);
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
        return idx_to_bitboard(self.value());
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

pub const Piece = enum(u3) {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,

    fn symbol(self: Piece, color: Color) u21 {
        return switch (color) {
            .Black => switch (self) {
                Piece.Pawn => 0x2659,
                Piece.Knight => 0x2658,
                Piece.Bishop => 0x2657,
                Piece.Rook => 0x2656,
                Piece.Queen => 0x2655,
                Piece.King => 0x2654,
            },
            .White => switch (self) {
                Piece.Pawn => 0x265F,
                Piece.Knight => 0x265E,
                Piece.Bishop => 0x265D,
                Piece.Rook => 0x265C,
                Piece.Queen => 0x265B,
                Piece.King => 0x265A,
            },
        };
    }

    pub fn idx(self: Piece) usize {
        return @intFromEnum(self);
    }
};

pub const PromotionPieces = [_]Piece{
    Piece.Knight,
    Piece.Bishop,
    Piece.Rook,
    Piece.Queen,
};

pub const MoveType = enum {
    NORMAL,
    CAPTURE,
    CASTLE,
};

pub const Move = struct {
    from: Square,
    to: Square,
    move_type: MoveType = .NORMAL,
    promotion_piece: ?Piece = null,

    pub fn str(self: Move) [4]u8 {
        return [4]u8{
            self.from.file_str(),
            self.from.rank_str(),
            self.to.file_str(),
            self.to.rank_str(),
        };
    }
};

const CastleSide = enum(u1) {
    short,
    long,

    fn idx(self: CastleSide) u1 {
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

    fn revoke(self: *CastlingRights, color: Color, side: CastleSide) bool {
        const _bit = bit(color, side);
        if (self.bits & _bit == 0) return false;
        self.bits &= ~_bit;

        return true;
    }

    // for fen parsing only
    fn grant(self: *CastlingRights, color: Color, side: CastleSide) void {
        self.bits |= bit(color, side);
    }
};

const ZobristT = struct {
    piece_boards: [2][6][64]u64,
    castling_rights: [2][2]u64,
    side_to_move: u64,
    en_passant_targets: [8]u64,
};

fn make_zobrist_table() ZobristT {
    @setEvalBranchQuota(100_000);

    var PRNG = std.Random.DefaultPrng.init(123);
    var rand = PRNG.random();

    var z: ZobristT = undefined;

    for (0..2) |ci| {
        for (0..6) |pi| {
            for (0..64) |si| {
                z.piece_boards[ci][pi][si] = rand.int(u64);
            }
        }
    }

    for (0..2) |ci| {
        for (0..2) |si| {
            z.castling_rights[ci][si] = rand.int(u64);
        }
    }

    z.side_to_move = rand.int(u64);

    for (0..8) |fi| {
        z.en_passant_targets[fi] = rand.int(u64);
    }

    return z;
}

const ZOBRIST_TABLE = make_zobrist_table();

pub const Position = struct {
    // [color][piece type] bitmasks
    piece_boards: [2][6]Bitboard,
    // [piece][short, long]
    castling_rights: CastlingRights = .{},
    side_to_move: Color,
    en_passant_targets: Bitboard = 0,

    history: [101]u64 = @splat(0),
    history_len: u8 = 0,
    hash: u64 = 0,
    half_move_counter: u8 = 0,

    // the enemy (opposite) of the current side_to_move
    pub fn sideEnemy(self: *const Position) Color {
        return self.side_to_move.opp();
    }

    pub fn init(side_to_move: Color) Position {
        var pos = Position{
            .side_to_move = side_to_move,
            .piece_boards = .{
                @splat(0),
                @splat(0),
            },
        };

        pos.hash = pos.calculateHash();
        return pos;
    }

    pub fn put(self: *Position, color: Color, piece: Piece, square: Square) void {
        assert(self.occupied() & square.mask() == 0);

        self.piece_boards[color.idx()][piece.idx()] |= square.mask();
        self.hash ^= ZOBRIST_TABLE.piece_boards[color.idx()][piece.idx()][square.as_usize()];
    }

    pub fn parseMove(self: *Position, input: []const u8) GameError!Move {
        const occupied_self = self.occupiedBy(self.side_to_move);
        const occupied_enemy = self.occupiedBy(self.sideEnemy());

        if (input.len < 4 or input.len > 5) return GameError.InvalidMove;

        var move: Move = .{
            .from = std.meta.stringToEnum(Square, input[0..2]) orelse return GameError.InvalidMove,
            .to = std.meta.stringToEnum(Square, input[2..4]) orelse return GameError.InvalidMove,
        };
        if (move.from.mask() & occupied_self == 0) return GameError.InvalidMove;
        if (move.to.mask() & occupied_self != 0) return GameError.InvalidMove;

        const piece = self.getPieceAt(move.from).?;
        if (piece == .King) {
            if (input.len != 4) return GameError.InvalidMove;
            switch (self.side_to_move) {
                .White => {
                    if (move.from == Square.e1) {
                        if (move.to == Square.c1 or move.to == Square.g1) move.move_type = .CASTLE;
                    }
                },
                .Black => {
                    if (move.from == Square.e8) {
                        if (move.to == Square.c8 or move.to == Square.g8) move.move_type = .CASTLE;
                    }
                },
            }
        } else if (move.to.mask() & occupied_enemy != 0 or move.to.mask() & self.en_passant_targets != 0) {
            if (input.len != 4) return GameError.InvalidMove;
            move.move_type = .CAPTURE;
        } else if (piece == .Pawn and move.to.rank() == self.side_to_move.end_rank()) {
            if (input.len != 5) return GameError.InvalidMove;
            move.promotion_piece = switch (input[4]) {
                'q' => .Queen,
                'r' => .Rook,
                'b' => .Bishop,
                'n' => .Knight,
                else => return GameError.InvalidMove,
            };
        } else if (input.len != 4) return GameError.InvalidMove;

        return move;
    }

    pub fn go(self: *Position, input: []const u8) !void {
        const move = try self.parseMove(input);

        self.apply(move);
    }

    fn resetEnPassantTargets(self: *Position, side: Color) void {
        var mask: u64 = (1 << 32) - 1;
        if (side == .White) mask = ~mask;

        var removed_targets = self.en_passant_targets & ~mask;
        while (removed_targets != 0) : (removed_targets &= removed_targets - 1) {
            const square = Square.from_int(@ctz(removed_targets));
            self.hash ^= ZOBRIST_TABLE.en_passant_targets[square.file()];
        }
        self.en_passant_targets &= mask;
    }

    fn revokeCastlingRight(self: *Position, color: Color, side: CastleSide) void {
        if (self.castling_rights.revoke(color, side)) {
            self.hash ^= ZOBRIST_TABLE.castling_rights[color.idx()][side.idx()];
        }
    }

    fn revokeCastlingRightAt(self: *Position, square: Square) void {
        switch (square) {
            .h1 => self.revokeCastlingRight(.White, .short),
            .a1 => self.revokeCastlingRight(.White, .long),
            .h8 => self.revokeCastlingRight(.Black, .short),
            .a8 => self.revokeCastlingRight(.Black, .long),
            else => {},
        }
    }

    pub fn apply(self: *Position, move: Move) void {
        const from_mask = move.from.mask();
        const to_mask = move.to.mask();

        self.resetEnPassantTargets(self.side_to_move);

        var piece: Piece = undefined;

        inline for (std.enums.values(Piece)) |p| {
            const bitmask = &self.piece_boards[self.side_to_move.idx()][p.idx()];

            if (bitmask.* & from_mask != 0) {
                bitmask.* ^= from_mask;
                self.hash ^= ZOBRIST_TABLE.piece_boards[self.side_to_move.idx()][p.idx()][move.from.as_usize()];

                if (move.promotion_piece == null) {
                    bitmask.* |= to_mask;
                    self.hash ^= ZOBRIST_TABLE.piece_boards[self.side_to_move.idx()][p.idx()][move.to.as_usize()];
                }
                piece = p;

                break;
            }
        } else unreachable;

        switch (piece) {
            .Pawn => {
                // en passant
                if (@abs(@as(i8, move.to.rank()) - @as(i8, move.from.rank())) == 2) {
                    const en_passant_square: ?Square = switch (self.side_to_move) {
                        .White => move.to.rel(0, -1),
                        .Black => move.to.rel(0, 1),
                    };

                    self.en_passant_targets |= en_passant_square.?.mask();
                    self.hash ^= ZOBRIST_TABLE.en_passant_targets[en_passant_square.?.file()];
                }
            },
            .King => {
                self.revokeCastlingRight(self.side_to_move, .long);
                self.revokeCastlingRight(self.side_to_move, .short);
            },
            else => {},
        }

        self.revokeCastlingRightAt(move.to);
        self.revokeCastlingRightAt(move.from);

        switch (move.move_type) {
            .CAPTURE => {
                for (std.enums.values(Piece)) |p| {
                    const bitmask = &self.piece_boards[self.sideEnemy().idx()][p.idx()];
                    if (bitmask.* & to_mask != 0) {
                        bitmask.* ^= to_mask;
                        self.hash ^= ZOBRIST_TABLE.piece_boards[self.sideEnemy().idx()][p.idx()][@ctz(to_mask)];

                        break;
                    }
                } else if (self.en_passant_targets & move.to.mask() != 0) {
                    // en passant
                    const pawn_to_capture = switch (self.side_to_move) {
                        .White => move.to.rel(0, -1),
                        .Black => move.to.rel(0, 1),
                    };

                    assert(self.piece_boards[self.sideEnemy().idx()][Piece.Pawn.idx()] & pawn_to_capture.?.mask() != 0);
                    self.piece_boards[self.sideEnemy().idx()][Piece.Pawn.idx()] ^= pawn_to_capture.?.mask();
                    self.hash ^= ZOBRIST_TABLE.piece_boards[self.sideEnemy().idx()][Piece.Pawn.idx()][pawn_to_capture.?.as_usize()];
                } else unreachable;
            },
            .CASTLE => {
                var old_rook_square: Square = undefined;
                var new_rook_square: Square = undefined;

                switch (move.to.file()) {
                    // long castle
                    2 => {
                        switch (self.side_to_move) {
                            .White => {
                                old_rook_square = Square.a1;
                                new_rook_square = Square.d1;
                            },
                            .Black => {
                                old_rook_square = Square.a8;
                                new_rook_square = Square.d8;
                            },
                        }
                    },
                    // short castle
                    6 => {
                        switch (self.side_to_move) {
                            .White => {
                                old_rook_square = Square.h1;
                                new_rook_square = Square.f1;
                            },
                            .Black => {
                                old_rook_square = Square.h8;
                                new_rook_square = Square.f8;
                            },
                        }
                    },
                    else => unreachable,
                }

                self.piece_boards[self.side_to_move.idx()][Piece.Rook.idx()] ^= old_rook_square.mask();
                self.piece_boards[self.side_to_move.idx()][Piece.Rook.idx()] |= new_rook_square.mask();
                self.hash ^= ZOBRIST_TABLE.piece_boards[self.side_to_move.idx()][Piece.Rook.idx()][old_rook_square.as_usize()];
                self.hash ^= ZOBRIST_TABLE.piece_boards[self.side_to_move.idx()][Piece.Rook.idx()][new_rook_square.as_usize()];

                self.revokeCastlingRight(self.side_to_move, .long);
                self.revokeCastlingRight(self.side_to_move, .short);
            },
            .NORMAL => {},
        }

        if (move.promotion_piece != null) {
            self.piece_boards[self.side_to_move.idx()][move.promotion_piece.?.idx()] |= to_mask;
            self.hash ^= ZOBRIST_TABLE.piece_boards[self.side_to_move.idx()][move.promotion_piece.?.idx()][move.to.as_usize()];
        }

        self.side_to_move = self.side_to_move.opp();
        self.hash ^= ZOBRIST_TABLE.side_to_move;

        // is the move irreversible
        if (piece == .Pawn or move.move_type != .NORMAL) {
            self.history_len = 0;
            self.half_move_counter = 0;
        } else {
            self.half_move_counter += 1;
        }
        self.saveHash();
    }

    fn saveHash(self: *Position) void {
        self.history[self.history_len] = self.hash;
        self.history_len += 1;
    }

    pub fn isRepetition(self: *const Position, limit: u8) bool {
        assert(limit >= 1);

        var counter: u8 = 0;

        var i: usize = 2;
        while (i < self.history_len) : (i += 2) {
            if (self.history[self.history_len - 1] == self.history[self.history_len - 1 - i]) counter += 1;
            if (counter >= (limit - 1)) return true;
        }

        return false;
    }

    pub fn start() Position {
        var pos = Position{
            .piece_boards = .{
                .{
                    0x000000000000ff00,
                    0x0000000000000042,
                    0x0000000000000024,
                    0x0000000000000081,
                    0x0000000000000008,
                    0x0000000000000010,
                },
                .{
                    0x00ff000000000000,
                    0x4200000000000000,
                    0x2400000000000000,
                    0x8100000000000000,
                    0x0800000000000000,
                    0x1000000000000000,
                },
            },
            .side_to_move = Color.White,
        };

        pos.hash = pos.calculateHash();
        pos.saveHash();

        return pos;
    }

    pub fn print(self: *const Position) void {
        var piece_mask: [64]u21 = @splat(32);
        var color_mask: [64]u8 = @splat(32);

        inline for (std.enums.values(Color), 0..) |col, ci| {
            inline for (std.enums.values(Piece), 0..) |piece, pi| {
                const bitmask = self.piece_boards[ci][pi];

                for (0..64) |i| {
                    if ((bitmask >> @truncate(i)) & 1 == 1) {
                        piece_mask[i] = piece.symbol(col);
                        color_mask[i] = col.symbol();
                    }
                }
            }
        }

        std.debug.print("-" ** 33, .{});
        std.debug.print("\n", .{});
        for (0..8) |r| {
            std.debug.print("|", .{});
            for (0..8) |f| {
                const idx = (7 - r) * 8 + f;
                std.debug.print(" {u} |", .{piece_mask[idx]});
            }
            std.debug.print("\n", .{});
            std.debug.print("-" ** 33, .{});
            std.debug.print("\n", .{});
        }
    }

    pub fn occupied(self: *const Position) Bitboard {
        return self.occupiedBy(.White) | self.occupiedBy(.Black);
    }

    pub fn occupiedBy(self: *const Position, color: Color) Bitboard {
        var result: Bitboard = 0;
        inline for (std.enums.values(Piece)) |piece| {
            result |= self.piece_boards[color.idx()][piece.idx()];
        }

        return result;
    }

    fn getPieceAt(self: *const Position, square: Square) ?Piece {
        for (0..2) |ci| {
            for (std.enums.values(Piece)) |piece| {
                if (self.piece_boards[ci][piece.idx()] & square.mask() != 0) return piece;
            }
        }

        return null;
    }

    pub fn fromFEN(input: []const u8) !Position {
        var pos = Position.init(.White);

        var rank: u8 = 7;
        var idx: u8 = 0;

        var i: u8 = 0;
        while (i < input.len and idx < 64) : (i += 1) {
            const char = input[i];
            if (char >= '1' and char <= '9') {
                idx += char - '1' + 1;
                continue;
            }

            if (char == '/') {
                if (rank == 0) break;
                rank -= 1;
                continue;
            }

            const square: Square = @enumFromInt(rank * 8 + (idx % 8));

            var color: Color = undefined;

            if (char >= 'b' and char <= 'r') {
                color = .Black;
            } else if (char >= 'B' and char <= 'R') {
                color = .White;
            } else {
                std.debug.print("i: {}, idx: {}, char: {c}\n", .{ i, idx, char });
                return GameError.InvalidFEN;
            }

            const piece: Piece = switch (char) {
                'p', 'P' => .Pawn,
                'b', 'B' => .Bishop,
                'k', 'K' => .King,
                'n', 'N' => .Knight,
                'r', 'R' => .Rook,
                'q', 'Q' => .Queen,
                else => return GameError.InvalidFEN,
            };

            pos.piece_boards[color.idx()][piece.idx()] |= square.mask();
            idx += 1;
            if (idx >= 64) break;
        }

        // side to move

        i += 1;
        while (input[i] == ' ') i += 1;

        pos.side_to_move = switch (input[i]) {
            'w' => .White,
            'b' => .Black,
            else => {
                std.debug.print("i: {}, char: {d}\n", .{ i, input[i] });
                return GameError.InvalidFEN;
            },
        };

        i += 2;

        pos.castling_rights.bits = 0;

        while (i < input.len) : (i += 1) {
            switch (input[i]) {
                'k' => pos.castling_rights.grant(.Black, .short),
                'q' => pos.castling_rights.grant(.Black, .long),
                'K' => pos.castling_rights.grant(.White, .short),
                'Q' => pos.castling_rights.grant(.White, .long),
                else => break,
            }
        }

        pos.hash = pos.calculateHash();
        pos.saveHash();

        return pos;

        // TODO moves counters
    }

    pub fn calculateHash(self: *const Position) u64 {
        // TODO: incremental updates

        var result: u64 = 0;

        for (0..2) |ci| {
            for (std.enums.values(Piece)) |piece| {
                var bitboard = self.piece_boards[ci][piece.idx()];
                while (bitboard != 0) : (bitboard &= bitboard - 1) {
                    const idx = @ctz(bitboard);
                    result ^= ZOBRIST_TABLE.piece_boards[ci][piece.idx()][idx];
                }
            }
        }

        if (self.side_to_move == .Black) {
            result ^= ZOBRIST_TABLE.side_to_move;
        }

        for (std.enums.values(Color)) |color| {
            if (self.castling_rights.has(color, .short)) {
                result ^= ZOBRIST_TABLE.castling_rights[color.idx()][CastleSide.short.idx()];
            }
            if (self.castling_rights.has(color, .long)) {
                result ^= ZOBRIST_TABLE.castling_rights[color.idx()][CastleSide.long.idx()];
            }
        }

        var en_passant_board = self.en_passant_targets;
        while (en_passant_board != 0) : (en_passant_board &= en_passant_board - 1) {
            const square = Square.from_int(@ctz(en_passant_board));

            result ^= ZOBRIST_TABLE.en_passant_targets[square.file()];
        }

        return result;
    }
};

test "position_apply" {
    var pos = Position.start();

    const move = Move{ .from = .e2, .to = .e4, .move_type = .NORMAL };

    try t.expect(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.from.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.to.mask(), 0);

    pos.apply(move);

    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.from.mask(), 0);
    try t.expect(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.to.mask() != 0);
}

test "position_apply_capture" {
    var pos = Position.init(.White);

    pos.put(.White, .Pawn, .e4);
    pos.put(.Black, .Pawn, .d5);

    const move = Move{ .from = .e4, .to = .d5, .move_type = .NORMAL };

    try t.expect(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.from.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.to.mask(), 0);

    pos.apply(move);

    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.from.mask(), 0);
    try t.expect(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.to.mask() != 0);
}

test "position_apply_castle" {
    var pos = Position.init(.White);

    pos.put(.White, .King, .e1);
    pos.put(.White, .Rook, .h1);

    const move = Move{ .from = .e1, .to = .g1, .move_type = .CASTLE };
    pos.apply(move);

    try t.expect(pos.piece_boards[Color.White.idx()][Piece.King.idx()] & move.to.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.King.idx()] & move.from.mask(), 0);

    try t.expect(pos.piece_boards[Color.White.idx()][Piece.Rook.idx()] & Square.f1.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.Rook.idx()] & Square.h1.mask(), 0);
}

test "position_apply_en_passant_push" {
    var pos = Position.init(.Black);

    pos.put(.White, .Pawn, .e5);
    pos.put(.Black, .Pawn, .f7);

    try pos.go("f7f5");

    try t.expect(pos.en_passant_targets & Square.f6.mask() != 0);
}

test "position_apply_en_passant_capture" {
    var pos = Position.init(.White);

    pos.put(.Black, .Pawn, .c4);
    pos.put(.White, .Pawn, .b2);
    pos.put(.White, .Pawn, .a2);

    pos.put(.White, .Pawn, .e5);
    pos.put(.Black, .Pawn, .f7);

    try pos.go("b2b4");
    try pos.go("c4b3");

    try pos.go("a2b3");

    try pos.go("f7f5");
    try pos.go("e5f6");

    try t.expectEqual(Piece.Pawn, pos.getPieceAt(.b3));
    try t.expectEqual(null, pos.getPieceAt(.b4));
}

test "position_apply_castling_rights_king_moved" {
    var pos = Position.start();

    try pos.go("e2e4");
    try pos.go("e7e5");

    try pos.go("e1e2");

    try t.expect(!pos.castling_rights.has(.White, .short));
    try t.expect(!pos.castling_rights.has(.White, .long));
    try t.expect(pos.castling_rights.has(.Black, .short));
    try t.expect(pos.castling_rights.has(.Black, .long));

    try pos.go("e8e7");

    try t.expect(!pos.castling_rights.has(.Black, .short));
    try t.expect(!pos.castling_rights.has(.Black, .long));
}

test "position_apply_castling_rights_rook_moved" {
    var pos = Position.init(.White);

    pos.put(.White, .King, .e1);
    pos.put(.White, .Rook, .a1);
    pos.put(.White, .Rook, .h1);

    pos.put(.Black, .King, .e8);
    pos.put(.Black, .Rook, .a8);
    pos.put(.Black, .Rook, .h8);

    try pos.go("a1a4");
    try t.expect(!pos.castling_rights.has(.White, .long));
    try t.expect(pos.castling_rights.has(.White, .short));

    try pos.go("h8h4");
    try t.expect(!pos.castling_rights.has(.Black, .short));
    try t.expect(pos.castling_rights.has(.Black, .long));

    try pos.go("h1h2");
    try t.expect(!pos.castling_rights.has(.White, .short));

    try pos.go("a8a7");
    try t.expect(!pos.castling_rights.has(.Black, .long));
}

test "position_apply_rook_captured" {
    var pos = Position.init(.White);

    pos.put(.White, .King, .e1);
    pos.put(.White, .Knight, .b1);
    pos.put(.White, .Knight, .g1);
    pos.put(.White, .Rook, .a1);
    pos.put(.White, .Rook, .h1);

    pos.put(.Black, .King, .e8);
    pos.put(.White, .Knight, .b8);
    pos.put(.White, .Knight, .g8);
    pos.put(.Black, .Rook, .a8);
    pos.put(.Black, .Rook, .h8);

    try pos.go("a1a8");
    try t.expect(!pos.castling_rights.has(.Black, .long));
    try t.expect(pos.castling_rights.has(.Black, .short));

    try pos.go("h8h1");
    try t.expect(!pos.castling_rights.has(.White, .long));
    try t.expect(!pos.castling_rights.has(.White, .short));
}

test "parse_move" {
    var pos = Position.init(.White);

    pos.put(.White, .Pawn, .e4);
    pos.put(.Black, .Pawn, .d5);

    var move: Move = undefined;
    move = try pos.parseMove("e4e5");

    try t.expectEqualStrings("e4", &move.from.str());
    try t.expectEqualStrings("e5", &move.to.str());
    try t.expectEqual(MoveType.NORMAL, move.move_type);

    move = try pos.parseMove("e4d5");

    try t.expectEqualStrings("e4", &move.from.str());
    try t.expectEqualStrings("d5", &move.to.str());
    try t.expectEqual(MoveType.CAPTURE, move.move_type);

    pos.put(.White, .King, .e1);
    pos.put(.White, .Rook, .a1);
    pos.put(.White, .Rook, .h1);

    move = try pos.parseMove("e1g1");

    try t.expectEqualStrings("e1", &move.from.str());
    try t.expectEqualStrings("g1", &move.to.str());
    try t.expectEqual(MoveType.CASTLE, move.move_type);

    pos.put(.White, .Pawn, .b7);

    move = try pos.parseMove("b7b8q");

    try t.expectEqualStrings("b7", &move.from.str());
    try t.expectEqualStrings("b8", &move.to.str());
    try t.expectEqual(Piece.Queen, move.promotion_piece);
}

test "from_fen" {
    const pos = try Position.fromFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    const start = Position.start();

    for (0..2) |ci| {
        for (std.enums.values(Piece)) |piece| {
            try t.expectEqual(start.piece_boards[ci][piece.idx()], pos.piece_boards[ci][piece.idx()]);
        }
    }
}

test "hash" {
    const pos1 = try Position.fromFEN("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1");
    const pos2 = try Position.fromFEN("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1");

    try t.expect(pos1.calculateHash() != pos2.calculateHash());
}

test "incremental hash matches full hash" {
    var position = Position.start();
    try t.expectEqual(position.hash, position.calculateHash());

    const moves = [_][]const u8{
        "e2e4", "d7d5", "e4d5", "g8f6", "d5d6", "h7h6", "d6d7", "h6h5",
    };
    for (moves) |move| {
        try position.go(move);
        try t.expectEqual(position.hash, position.calculateHash());
    }

    var promotion = try Position.fromFEN("4k3/P7/8/8/8/8/8/4K3 w - - 0 1");
    try promotion.go("a7a8q");
    try t.expectEqual(position.hash, position.calculateHash());

    var en_passant = try Position.fromFEN("4k3/5p2/8/4P3/8/8/8/4K3 b - - 0 1");
    try en_passant.go("f7f5");
    try t.expectEqual(position.hash, position.calculateHash());
    try en_passant.go("e5f6");
    try t.expectEqual(position.hash, position.calculateHash());

    var castling = try Position.fromFEN("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    try castling.go("e1g1");
    try t.expectEqual(position.hash, position.calculateHash());
    try castling.go("e8c8");
    try t.expectEqual(position.hash, position.calculateHash());

    var repeated_rook_move = try Position.fromFEN("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    const rook_moves = [_][]const u8{ "h1h2", "h8h7", "h2h1", "h7h8" };
    for (rook_moves) |move| {
        try repeated_rook_move.go(move);
        try t.expectEqual(position.hash, position.calculateHash());
    }
}

test "threefold repetition" {
    var pos = Position.start();
    const moves = [_][]const u8{ "g1f3", "g8f6", "f3g1", "f6g8" };

    for (moves) |m| try pos.go(m);
    try t.expect(!pos.isRepetition(3));

    for (moves) |m| try pos.go(m);
    try t.expect(pos.isRepetition(3));
}

fn print_bitboard(board: Bitboard) void {
    std.debug.print("-" ** 33, .{});
    std.debug.print("\n", .{});
    for (0..8) |r| {
        std.debug.print("|", .{});
        for (0..8) |f| {
            const idx: u8 = @intCast((7 - r) * 8 + f);
            const mask = idx_to_bitboard(idx);
            const c: u8 = if (board & mask == 0) ' ' else 'X';
            std.debug.print(" {c} |", .{c});
        }
        std.debug.print("\n", .{});
        std.debug.print("-" ** 33, .{});
        std.debug.print("\n", .{});
    }
}
