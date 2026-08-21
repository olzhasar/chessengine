const std = @import("std");
const t = std.testing;

const Position = @import("Position.zig");

const types = @import("types.zig");
const Bitboard = types.Bitboard;
const Square = types.Square;
const Color = types.Color;
const PieceType = types.PieceType;
const PieceTypes = types.PieceTypes;

fn precomputeAttacksKnight() [64]Bitboard {
    @setEvalBranchQuota(5000);

    var result: [64]Bitboard = @splat(0);

    const directions = [_]struct { x: i8, y: i8 }{
        .{ .x = -1, .y = 2 },
        .{ .x = 1, .y = 2 },
        .{ .x = -1, .y = -2 },
        .{ .x = 1, .y = -2 },
        .{ .x = -2, .y = 1 },
        .{ .x = -2, .y = -1 },
        .{ .x = 2, .y = 1 },
        .{ .x = 2, .y = -1 },
    };

    for (0..64) |i| {
        const from = Square.from_int(i);

        for (&directions) |dir| {
            const target = from.rel(dir.x, dir.y);
            if (target != null) result[i] |= target.?.mask();
        }
    }

    return result;
}

fn precomputeAttacksKing() [64]Bitboard {
    @setEvalBranchQuota(5000);

    var result: [64]Bitboard = @splat(0);

    const directions = [_]struct { x: i8, y: i8 }{
        .{ .x = 1, .y = 0 },
        .{ .x = -1, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = 0, .y = -1 },
        .{ .x = 1, .y = -1 },
        .{ .x = 1, .y = 1 },
        .{ .x = -1, .y = 1 },
        .{ .x = -1, .y = -1 },
    };

    for (0..64) |i| {
        const from = Square.from_int(i);

        for (&directions) |dir| {
            const target = from.rel(dir.x, dir.y);
            if (target != null) result[i] |= target.?.mask();
        }
    }

    return result;
}

fn precomputeAttacksPawn() [2][64]Bitboard {
    @setEvalBranchQuota(5000);
    var result: [2][64]Bitboard = .{ @splat(0), @splat(0) };

    // WHITE
    for (0..64) |i| {
        const from = Square.from_int(i);

        const left = from.rel(-1, 1);
        if (left != null) result[Color.White.idx()][i] |= left.?.mask();

        const right = from.rel(1, 1);
        if (right != null) result[Color.White.idx()][i] |= right.?.mask();
    }

    // BLACK
    for (0..64) |i| {
        const from = Square.from_int(i);

        const left = from.rel(1, -1);
        if (left != null) result[Color.Black.idx()][i] |= left.?.mask();

        const right = from.rel(-1, -1);
        if (right != null) result[Color.Black.idx()][i] |= right.?.mask();
    }

    return result;
}

const ATTACKS_KNIGHT: [64]Bitboard = precomputeAttacksKnight();
const ATTACKS_KING: [64]Bitboard = precomputeAttacksKing();
const ATTACKS_PAWN: [2][64]Bitboard = precomputeAttacksPawn();

inline fn getAttacksPawn(from: Square, side: Color) Bitboard {
    return ATTACKS_PAWN[side.idx()][from.as_usize()];
}

pub inline fn getAttacksKnight(from: Square) Bitboard {
    return ATTACKS_KNIGHT[from.as_usize()];
}

pub fn getAttacksBishop(from: Square, occupied: Bitboard) Bitboard {
    // TODO use magic bitboards instead

    var result: Bitboard = 0;

    const not_a_file: Bitboard = 0xfefefefefefefefe;
    const not_h_file: Bitboard = 0x7f7f7f7f7f7f7f7f;

    // NE
    var current = from.mask();
    inline for (0..7) |_| {
        current = (current & not_h_file) << 9;
        if (current == 0) break;
        result |= current;

        if (current & occupied != 0) break;
    }

    // SW
    current = from.mask();
    inline for (0..7) |_| {
        current = (current & not_a_file) >> 9;
        if (current == 0) break;
        result |= current;

        if (current & occupied != 0) break;
    }

    // NW
    current = from.mask();
    inline for (0..7) |_| {
        current = (current & not_a_file) << 7;
        if (current == 0) break;
        result |= current;

        if (current & occupied != 0) break;
    }

    // SE
    current = from.mask();
    inline for (0..7) |_| {
        current = (current & not_h_file) >> 7;
        if (current == 0) break;
        result |= current;

        if (current & occupied != 0) break;
    }

    return result;
}

pub fn getAttacksRook(from: Square, occupied: Bitboard) Bitboard {
    // TODO use magic bitboards instead

    var result: Bitboard = 0;

    const not_a_file: Bitboard = 0xfefefefefefefefe;
    const not_h_file: Bitboard = 0x7f7f7f7f7f7f7f7f;
    const not_1_rank: Bitboard = 0xffffffffffffff00;
    const not_8_rank: Bitboard = 0x00ffffffffffffff;

    // N
    var current = from.mask();
    inline for (0..7) |_| {
        current = (current & not_8_rank) << 8;
        if (current == 0) break;
        result |= current;
        if (current & occupied != 0) break;
    }

    // S
    current = from.mask();
    inline for (0..7) |_| {
        current = (current & not_1_rank) >> 8;
        if (current == 0) break;
        result |= current;
        if (current & occupied != 0) break;
    }

    // E
    current = from.mask();
    inline for (0..7) |_| {
        current = (current & not_h_file) << 1;
        if (current == 0) break;
        result |= current;
        if (current & occupied != 0) break;
    }

    // W
    current = from.mask();
    inline for (0..7) |_| {
        current = (current & not_a_file) >> 1;
        if (current == 0) break;
        result |= current;
        if (current & occupied != 0) break;
    }

    return result;
}

inline fn getAttacksQueen(from: Square, occupied: Bitboard) Bitboard {
    return getAttacksBishop(from, occupied) | getAttacksRook(from, occupied);
}

pub fn getAttacksKing(from: Square) Bitboard {
    return ATTACKS_KING[from.as_usize()];
}

pub inline fn getAttacks(piece: PieceType, side: Color, from: Square, occupied: Bitboard) Bitboard {
    return switch (piece) {
        PieceType.Pawn => getAttacksPawn(from, side),
        PieceType.Knight => getAttacksKnight(from),
        PieceType.Bishop => getAttacksBishop(from, occupied),
        PieceType.Rook => getAttacksRook(from, occupied),
        PieceType.Queen => getAttacksQueen(from, occupied),
        PieceType.King => getAttacksKing(from),
        else => unreachable,
    };
}

pub fn attackedMask(pos: *const Position, side: Color, occupied: Bitboard) Bitboard {
    var result: Bitboard = 0;

    inline for (PieceTypes) |piece| {
        var placements = pos.piece_boards[side.idx()][piece.idx()];

        while (placements != 0) : (placements &= placements - 1) {
            const from = Square.from_int(@ctz(placements));

            result |= getAttacks(piece, side, from, occupied);
        }
    }

    return result;
}

fn isAttackedBy(area_mask: Bitboard, piece: PieceType, attacker: Color, pos: *const Position, occupied: Bitboard) bool {
    var pieces = pos.piece_boards[attacker.idx()][piece.idx()];
    while (pieces != 0) : (pieces &= pieces - 1) {
        const square = Square.from_int(@ctz(pieces));
        if (getAttacks(piece, attacker, square, occupied) & area_mask != 0) return true;
    }

    return false;
}

pub fn isAttacked(area: Bitboard, attacker: Color, pos: *const Position) bool {
    const occupied = pos.occupied();

    inline for (PieceTypes) |piece| {
        if (isAttackedBy(area, piece, attacker, pos, occupied)) return true;
    }

    return false;
}

fn isSquareAttacked(square: Square, defender: Color, pos: *const Position) bool {
    var pawn_attacks: Bitboard = 0;
    const pawn1 = square.rel(1, defender.pawn_direction());
    if (pawn1 != null) pawn_attacks |= pawn1.?.mask();
    const pawn2 = square.rel(-1, defender.pawn_direction());
    if (pawn2 != null) pawn_attacks |= pawn2.?.mask();

    if (pawn_attacks & pos.piece_boards[defender.opp().idx()][PieceType.Pawn.idx()] != 0) return true;

    const knight_attacks = getAttacksKnight(square);
    if (knight_attacks & pos.piece_boards[defender.opp().idx()][PieceType.Knight.idx()] != 0) return true;

    const king_attacks = getAttacksKing(square);
    if (king_attacks & pos.piece_boards[defender.opp().idx()][PieceType.King.idx()] != 0) return true;

    const occupied = pos.occupied();
    const attacker_pieces = pos.piece_boards[defender.opp().idx()];

    const rook_attacks = getAttacksRook(square, occupied);
    if (rook_attacks & (attacker_pieces[PieceType.Rook.idx()] | attacker_pieces[PieceType.Queen.idx()]) != 0) return true;

    const bishop_attacks = getAttacksBishop(square, occupied);
    return bishop_attacks & (attacker_pieces[PieceType.Bishop.idx()] | attacker_pieces[PieceType.Queen.idx()]) != 0;
}

pub fn isInCheck(pos: *const Position, side: Color) bool {
    const king_mask = pos.piece_boards[side.idx()][PieceType.King.idx()];
    if (king_mask == 0) return false;

    const king_square = Square.from_int(@ctz(king_mask));
    return isSquareAttacked(king_square, side, pos);
}

test "is_check_no" {
    const pos = Position.start();

    try t.expect(!isInCheck(&pos, .White));
    try t.expect(!isInCheck(&pos, .Black));
}

test "is_check_pawn" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .d1);
    pos.put(.Black, .Pawn, .c2);

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, .e8);
    pos.put(.White, .Pawn, .d7);

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_knight" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .d1);
    pos.put(.Black, .Knight, .e3);

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, .h8);
    pos.put(.White, .Knight, .g6);

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_bishop" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .d1);
    pos.put(.Black, .Bishop, .a4);

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, .h8);
    pos.put(.White, .Bishop, .a1);

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_rook" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .d1);
    pos.put(.Black, .Rook, .d8);

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, .h8);
    pos.put(.White, .Rook, .h1);

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_queen" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .d1);
    pos.put(.Black, .Queen, .a4);

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, .h8);
    pos.put(.White, .Queen, .h1);

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_king" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e4);
    pos.put(.Black, .King, .d4);

    try t.expect(isInCheck(&pos, .White));
    try t.expect(isInCheck(&pos, .Black));
}
