const std = @import("std");

const Position = @import("Position.zig");

const types = @import("types.zig");
const Bitboard = types.Bitboard;
const Square = types.Square;
const Color = types.Color;
const Piece = types.Piece;

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

pub inline fn getAttacks(piece: Piece, side: Color, from: Square, occupied: Bitboard) Bitboard {
    return switch (piece) {
        Piece.Pawn => getAttacksPawn(from, side),
        Piece.Knight => getAttacksKnight(from),
        Piece.Bishop => getAttacksBishop(from, occupied),
        Piece.Rook => getAttacksRook(from, occupied),
        Piece.Queen => getAttacksQueen(from, occupied),
        Piece.King => getAttacksKing(from),
    };
}

pub fn attackedMask(pos: *const Position, side: Color, occupied: Bitboard) Bitboard {
    var result: Bitboard = 0;

    inline for (std.enums.values(Piece)) |piece| {
        var placements = pos.piece_boards[side.idx()][piece.idx()];

        while (placements != 0) : (placements &= placements - 1) {
            const from = Square.from_int(@ctz(placements));

            result |= getAttacks(piece, side, from, occupied);
        }
    }

    return result;
}
