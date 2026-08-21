const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

const types = @import("types.zig");
const zobrist = @import("zobrist.zig");

const Bitboard = types.Bitboard;
const CastlingRights = types.CastlingRights;
const Color = types.Color;
const PieceType = types.PieceType;
const PieceTypes = types.PieceTypes;
const Square = types.Square;
const Move = types.Move;
const MoveType = types.MoveType;
const CastleSide = types.CastleSide;

pub const PositionError = error{
    InvalidMove,
    IllegalMove,
    InvalidFEN,
};

const Position = @This();

// [color][piece type] bitmasks
piece_boards: [2][6]Bitboard,
en_passant_targets: Bitboard = 0,

castling_rights: CastlingRights = .{},

side_to_move: Color,

full_move_counter: u32 = 0,
half_move_counter: u8 = 0,

hash: u64 = 0,

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
        .full_move_counter = 1,
    };

    pos.hash = pos.calculateHash();

    return pos;
}

pub fn put(self: *Position, color: Color, piece: PieceType, square: Square) void {
    assert(self.occupied() & square.mask() == 0);

    self.piece_boards[color.idx()][piece.idx()] |= square.mask();
    self.hash ^= zobrist.TABLE.piece_boards[color.idx()][piece.idx()][square.as_usize()];
}

fn resetEnPassantTargets(self: *Position, side: Color) void {
    var mask: u64 = (1 << 32) - 1;
    if (side == .White) mask = ~mask;

    var removed_targets = self.en_passant_targets & ~mask;
    while (removed_targets != 0) : (removed_targets &= removed_targets - 1) {
        const square = Square.from_int(@ctz(removed_targets));
        self.hash ^= zobrist.TABLE.en_passant_targets[square.file()];
    }
    self.en_passant_targets &= mask;
}

fn revokeCastlingRight(self: *Position, color: Color, side: CastleSide) void {
    if (self.castling_rights.revoke(color, side)) {
        self.hash ^= zobrist.TABLE.castling_rights[color.idx()][side.idx()];
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

pub fn occupied(self: *const Position) Bitboard {
    return self.occupiedBy(.White) | self.occupiedBy(.Black);
}

pub fn occupiedBy(self: *const Position, color: Color) Bitboard {
    var result: Bitboard = 0;
    inline for (PieceTypes) |piece| {
        result |= self.piece_boards[color.idx()][piece.idx()];
    }

    return result;
}

pub fn getPieceAt(self: *const Position, square: Square) PieceType {
    const white = self.getPieceAtForSide(square, .White);
    if (white != .NO_PIECE_TYPE) return white;
    return self.getPieceAtForSide(square, .Black);
}

pub fn getPieceAtForSide(self: *const Position, square: Square, side: Color) PieceType {
    inline for (PieceTypes) |piece| {
        if (self.piece_boards[side.idx()][piece.idx()] & square.mask() != 0) return piece;
    }

    return .NO_PIECE_TYPE;
}

fn calculateHash(self: *const Position) u64 {
    var result: u64 = 0;

    for (0..2) |ci| {
        for (PieceTypes) |piece_type| {
            var bitboard = self.piece_boards[ci][piece_type.idx()];
            while (bitboard != 0) : (bitboard &= bitboard - 1) {
                const idx = @ctz(bitboard);
                result ^= zobrist.TABLE.piece_boards[ci][piece_type.idx()][idx];
            }
        }
    }

    if (self.side_to_move == .Black) {
        result ^= zobrist.TABLE.side_to_move;
    }

    for (std.enums.values(Color)) |color| {
        if (self.castling_rights.has(color, .short)) {
            result ^= zobrist.TABLE.castling_rights[color.idx()][CastleSide.short.idx()];
        }
        if (self.castling_rights.has(color, .long)) {
            result ^= zobrist.TABLE.castling_rights[color.idx()][CastleSide.long.idx()];
        }
    }

    var en_passant_board = self.en_passant_targets;
    while (en_passant_board != 0) : (en_passant_board &= en_passant_board - 1) {
        const square = Square.from_int(@ctz(en_passant_board));

        result ^= zobrist.TABLE.en_passant_targets[square.file()];
    }

    return result;
}

test "hash" {
    const pos1 = try Position.fromFEN("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1");
    const pos2 = try Position.fromFEN("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1");

    try t.expect(pos1.calculateHash() != pos2.calculateHash());
}

pub fn parseMove(self: *Position, input: []const u8) PositionError!Move {
    const occupied_self = self.occupiedBy(self.side_to_move);
    const occupied_enemy = self.occupiedBy(self.sideEnemy());

    if (input.len < 4 or input.len > 5) return PositionError.InvalidMove;

    const from = std.meta.stringToEnum(Square, input[0..2]) orelse return PositionError.InvalidMove;
    const to = std.meta.stringToEnum(Square, input[2..4]) orelse return PositionError.InvalidMove;
    if (from.mask() & occupied_self == 0) return PositionError.InvalidMove;
    if (to.mask() & occupied_self != 0) return PositionError.InvalidMove;

    var move: Move = .{
        .piece = self.getPieceAt(from),
        .from = from,
        .to = to,
    };

    const is_castle = move.piece == .King and switch (self.side_to_move) {
        .White => move.from == Square.e1 and (move.to == Square.c1 or move.to == Square.g1),
        .Black => move.from == Square.e8 and (move.to == Square.c8 or move.to == Square.g8),
    };

    if (is_castle) {
        if (input.len != 4) return PositionError.InvalidMove;
        move.move_type = .CASTLE;
        return move;
    }

    if (move.to.mask() & occupied_enemy != 0) {
        move.captured_piece = self.getPieceAtForSide(move.to, self.sideEnemy());
        move.move_type = .CAPTURE;
    } else if (move.piece == .Pawn and move.to.mask() & self.en_passant_targets != 0) {
        move.captured_piece = .Pawn;
        move.move_type = .CAPTURE;
    }

    if (move.piece == .Pawn and move.to.rank() == self.side_to_move.end_rank()) {
        if (input.len != 5) return PositionError.InvalidMove;
        move.promotion_piece = switch (input[4]) {
            'q' => .Queen,
            'r' => .Rook,
            'b' => .Bishop,
            'n' => .Knight,
            else => return PositionError.InvalidMove,
        };
    } else if (input.len != 4) return PositionError.InvalidMove;

    return move;
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
    try t.expectEqual(PieceType.Queen, move.promotion_piece);

    var black_pos = Position.init(.Black);
    black_pos.put(.Black, .Pawn, .b2);
    black_pos.put(.White, .Knight, .c1);

    move = try black_pos.parseMove("b2c1r");

    try t.expectEqual(MoveType.CAPTURE, move.move_type);
    try t.expectEqual(PieceType.Knight, move.captured_piece);
    try t.expectEqual(PieceType.Rook, move.promotion_piece);
}

test "parse_move castle" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e1);
    pos.put(.White, .Rook, .a1);
    pos.put(.White, .Rook, .h1);

    const short = try pos.parseMove("e1c1");

    try t.expectEqual(MoveType.CASTLE, short.move_type);
    try t.expectEqual(PieceType.King, short.piece);

    const long = try pos.parseMove("e1g1");

    try t.expectEqual(MoveType.CASTLE, long.move_type);
    try t.expectEqual(PieceType.King, long.piece);
}

test "parse_move king capture" {
    var pos = Position.init(.Black);
    pos.put(.Black, .King, .g5);
    pos.put(.White, .Pawn, .f4);
    pos.put(.White, .King, .g1);

    const move = try pos.parseMove("g5f4");

    try t.expectEqual(MoveType.CAPTURE, move.move_type);
    try t.expectEqual(PieceType.Pawn, move.captured_piece);
}

pub fn apply(self: *Position, move: Move) void {
    const from_mask = move.from.mask();
    const to_mask = move.to.mask();

    self.resetEnPassantTargets(self.side_to_move);

    self.piece_boards[self.side_to_move.idx()][move.piece.idx()] ^= from_mask;
    self.hash ^= zobrist.TABLE.piece_boards[self.side_to_move.idx()][move.piece.idx()][move.from.as_usize()];

    if (move.promotion_piece == .NO_PIECE_TYPE) {
        self.piece_boards[self.side_to_move.idx()][move.piece.idx()] |= to_mask;
        self.hash ^= zobrist.TABLE.piece_boards[self.side_to_move.idx()][move.piece.idx()][move.to.as_usize()];
    }

    switch (move.piece) {
        .Pawn => {
            // en passant
            if (@abs(@as(i8, move.to.rank()) - @as(i8, move.from.rank())) == 2) {
                const en_passant_square: ?Square = switch (self.side_to_move) {
                    .White => move.to.rel(0, -1),
                    .Black => move.to.rel(0, 1),
                };

                self.en_passant_targets |= en_passant_square.?.mask();
                self.hash ^= zobrist.TABLE.en_passant_targets[en_passant_square.?.file()];
            } else if (move.promotion_piece != .NO_PIECE_TYPE) {
                self.piece_boards[self.side_to_move.idx()][move.promotion_piece.idx()] |= to_mask;
                self.hash ^= zobrist.TABLE.piece_boards[self.side_to_move.idx()][move.promotion_piece.idx()][move.to.as_usize()];
            }
        },
        .King => {
            self.revokeCastlingRight(self.side_to_move, .long);
            self.revokeCastlingRight(self.side_to_move, .short);
        },
        .Rook => {
            self.revokeCastlingRightAt(move.from);
        },
        else => {},
    }

    switch (move.move_type) {
        .CAPTURE => {
            if (self.en_passant_targets & move.to.mask() != 0) {
                // en passant
                const pawn_to_capture = switch (self.side_to_move) {
                    .White => move.to.rel(0, -1),
                    .Black => move.to.rel(0, 1),
                };

                assert(self.piece_boards[self.sideEnemy().idx()][PieceType.Pawn.idx()] & pawn_to_capture.?.mask() != 0);
                self.piece_boards[self.sideEnemy().idx()][PieceType.Pawn.idx()] ^= pawn_to_capture.?.mask();
                self.hash ^= zobrist.TABLE.piece_boards[self.sideEnemy().idx()][PieceType.Pawn.idx()][pawn_to_capture.?.as_usize()];
            } else {
                assert(move.captured_piece != .NO_PIECE_TYPE);
                self.piece_boards[self.sideEnemy().idx()][move.captured_piece.idx()] ^= to_mask;
                self.hash ^= zobrist.TABLE.piece_boards[self.sideEnemy().idx()][move.captured_piece.idx()][@ctz(to_mask)];

                if (move.captured_piece == .Rook) {
                    self.revokeCastlingRightAt(move.to);
                }
            }
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

            self.piece_boards[self.side_to_move.idx()][PieceType.Rook.idx()] ^= old_rook_square.mask();
            self.piece_boards[self.side_to_move.idx()][PieceType.Rook.idx()] |= new_rook_square.mask();
            self.hash ^= zobrist.TABLE.piece_boards[self.side_to_move.idx()][PieceType.Rook.idx()][old_rook_square.as_usize()];
            self.hash ^= zobrist.TABLE.piece_boards[self.side_to_move.idx()][PieceType.Rook.idx()][new_rook_square.as_usize()];

            self.revokeCastlingRight(self.side_to_move, .long);
            self.revokeCastlingRight(self.side_to_move, .short);
        },
        .NORMAL => {},
    }

    if (self.side_to_move == .Black) self.full_move_counter += 1;

    self.side_to_move = self.side_to_move.opp();
    self.hash ^= zobrist.TABLE.side_to_move;

    // is the move irreversible
    if (move.piece == .Pawn or move.move_type != .NORMAL) {
        self.half_move_counter = 0;
    } else {
        self.half_move_counter += 1;
    }
}

pub fn go(self: *Position, input: []const u8) !void {
    const move = try self.parseMove(input);

    self.apply(move);
}

test "apply" {
    var pos = Position.start();

    const move = Move{ .piece = .Pawn, .from = .e2, .to = .e4, .move_type = .NORMAL };

    try t.expect(pos.piece_boards[Color.White.idx()][PieceType.Pawn.idx()] & move.from.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][PieceType.Pawn.idx()] & move.to.mask(), 0);

    pos.apply(move);

    try t.expectEqual(pos.piece_boards[Color.White.idx()][PieceType.Pawn.idx()] & move.from.mask(), 0);
    try t.expect(pos.piece_boards[Color.White.idx()][PieceType.Pawn.idx()] & move.to.mask() != 0);
}

test "apply capture" {
    var pos = Position.init(.White);

    pos.put(.White, .Pawn, .e4);
    pos.put(.Black, .Pawn, .d5);

    const move = Move{ .piece = .Pawn, .from = .e4, .to = .d5, .move_type = .NORMAL };

    try t.expect(pos.piece_boards[Color.White.idx()][PieceType.Pawn.idx()] & move.from.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][PieceType.Pawn.idx()] & move.to.mask(), 0);

    pos.apply(move);

    try t.expectEqual(pos.piece_boards[Color.White.idx()][PieceType.Pawn.idx()] & move.from.mask(), 0);
    try t.expect(pos.piece_boards[Color.White.idx()][PieceType.Pawn.idx()] & move.to.mask() != 0);
}

test "apply castle" {
    var pos = Position.init(.White);

    pos.put(.White, .King, .e1);
    pos.put(.White, .Rook, .h1);

    const move = Move{ .piece = .King, .from = .e1, .to = .g1, .move_type = .CASTLE };
    pos.apply(move);

    try t.expect(pos.piece_boards[Color.White.idx()][PieceType.King.idx()] & move.to.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][PieceType.King.idx()] & move.from.mask(), 0);

    try t.expect(pos.piece_boards[Color.White.idx()][PieceType.Rook.idx()] & Square.f1.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][PieceType.Rook.idx()] & Square.h1.mask(), 0);
}

test "apply move counters" {
    var pos = Position.start();

    try t.expectEqual(1, pos.full_move_counter);
    try t.expectEqual(0, pos.half_move_counter);

    try pos.go("e2e4");

    try t.expectEqual(1, pos.full_move_counter);
    try t.expectEqual(0, pos.half_move_counter);

    try pos.go("d7d5");

    try t.expectEqual(2, pos.full_move_counter);
    try t.expectEqual(0, pos.half_move_counter);

    try pos.go("b1c3");

    try t.expectEqual(2, pos.full_move_counter);
    try t.expectEqual(1, pos.half_move_counter);

    try pos.go("b8c6");

    try t.expectEqual(3, pos.full_move_counter);
    try t.expectEqual(2, pos.half_move_counter);
}

test "apply en_passant push" {
    var pos = Position.init(.Black);

    pos.put(.White, .Pawn, .e5);
    pos.put(.Black, .Pawn, .f7);

    try pos.go("f7f5");

    try t.expect(pos.en_passant_targets & Square.f6.mask() != 0);
}

test "apply en_passant capture" {
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

    try t.expectEqual(PieceType.Pawn, pos.getPieceAt(.b3));
    try t.expectEqual(PieceType.NO_PIECE_TYPE, pos.getPieceAt(.b4));
}

test "apply castling rights king moved" {
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

test "apply castling rights rook moved" {
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

test "apply rook captured" {
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

pub fn fromFEN(input: []const u8) !Position {
    var fields: [6][]const u8 = undefined;
    var field_count: usize = 0;
    var tokens = std.mem.tokenizeAny(u8, input, " \t\r\n");
    while (tokens.next()) |field| {
        if (field_count == fields.len) return PositionError.InvalidFEN;
        fields[field_count] = field;
        field_count += 1;
    }
    if (field_count != fields.len) return PositionError.InvalidFEN;

    var pos = Position.init(.White);

    var rank: u8 = 7;
    var idx: u8 = 0;

    var i: u8 = 0;
    while (i < fields[0].len and idx < 64) : (i += 1) {
        if (idx >= 64) break;

        const char = fields[0][i];
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
            return PositionError.InvalidFEN;
        }

        const piece: PieceType = switch (char) {
            'p', 'P' => .Pawn,
            'b', 'B' => .Bishop,
            'k', 'K' => .King,
            'n', 'N' => .Knight,
            'r', 'R' => .Rook,
            'q', 'Q' => .Queen,
            else => return PositionError.InvalidFEN,
        };

        pos.piece_boards[color.idx()][piece.idx()] |= square.mask();
        idx += 1;
    }

    // side to move
    if (fields[1].len != 1) return PositionError.InvalidFEN;

    pos.side_to_move = switch (fields[1][0]) {
        'w' => .White,
        'b' => .Black,
        else => return PositionError.InvalidFEN,
    };

    pos.castling_rights.bits = 0;

    i = 0;
    while (i < fields[2].len) : (i += 1) {
        switch (fields[2][i]) {
            'k' => pos.castling_rights.grant(.Black, .short),
            'q' => pos.castling_rights.grant(.Black, .long),
            'K' => pos.castling_rights.grant(.White, .short),
            'Q' => pos.castling_rights.grant(.White, .long),
            else => break,
        }
    }

    // en passant target
    if (fields[3].len == 2) {
        const target = std.meta.stringToEnum(Square, fields[3]) orelse return PositionError.InvalidFEN;
        pos.en_passant_targets |= target.mask();
    } else if (fields[3].len != 1 or fields[3][0] != '-') return PositionError.InvalidFEN;

    pos.half_move_counter = std.fmt.parseInt(u8, fields[4], 10) catch return PositionError.InvalidFEN;
    pos.full_move_counter = std.fmt.parseInt(u32, fields[5], 10) catch return PositionError.InvalidFEN;

    if (pos.full_move_counter == 0) return PositionError.InvalidFEN;

    pos.hash = pos.calculateHash();

    return pos;
}

test "from_fen" {
    const pos = try Position.fromFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 3 10");
    const pos_start = Position.start();

    for (0..2) |ci| {
        for (PieceTypes) |piece| {
            try t.expectEqual(pos_start.piece_boards[ci][piece.idx()], pos.piece_boards[ci][piece.idx()]);
        }
    }

    try t.expectEqual(3, pos.half_move_counter);
    try t.expectEqual(10, pos.full_move_counter);
}

test "from_fen_en_passant" {
    const pos = try Position.fromFEN("rnbqkbnr/pppppppp/8/8/4p3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1");

    try t.expectEqual(Square.e3.mask(), pos.en_passant_targets);
}

pub fn print(self: *const Position) void {
    var piece_mask: [64]u21 = @splat(32);
    var color_mask: [64]u8 = @splat(32);

    inline for (std.enums.values(Color), 0..) |col, ci| {
        inline for (PieceTypes, 0..) |piece, pi| {
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
