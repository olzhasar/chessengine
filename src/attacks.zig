const board = @import("board.zig");
const Bitboard = board.Bitboard;
const Square = board.Square;
const Color = board.Color;
const Piece = board.Piece;

fn precomputeAttacksKnight() [64]Bitboard {
    @setEvalBranchQuota(3000);

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

    for (0..64) |idx| {
        const from = Square.get(idx);

        for (&directions) |dir| {
            const target = from.rel(dir.x, dir.y);
            if (target != null) result[idx] |= target.?.mask();
        }
    }

    return result;
}

fn precomputeAttacksKing() [64]Bitboard {
    @setEvalBranchQuota(4000);

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

    for (0..64) |idx| {
        const from = Square.get(idx);

        for (&directions) |dir| {
            const target = from.rel(dir.x, dir.y);
            if (target != null) result[idx] |= target.?.mask();
        }
    }

    return result;
}

fn precomputeAttacksPawn() [2][64]Bitboard {
    @setEvalBranchQuota(4000);
    var result: [2][64]Bitboard = .{ @splat(0), @splat(0) };

    // WHITE
    for (0..64) |idx| {
        const from = Square.get(idx);

        const left = from.rel(-1, 1);
        if (left != null) result[Color.White.idx()][idx] |= left.?.mask();

        const right = from.rel(1, 1);
        if (right != null) result[Color.White.idx()][idx] |= right.?.mask();
    }

    // BLACK
    for (0..64) |idx| {
        const from = Square.get(idx);
        const left = from.rel(1, -1);
        if (left != null) result[Color.Black.idx()][idx] |= left.?.mask();

        const right = from.rel(-1, -1);
        if (right != null) result[Color.Black.idx()][idx] |= right.?.mask();
    }

    return result;
}

const ATTACKS_KNIGHT: [64]Bitboard = precomputeAttacksKnight();
const ATTACKS_KING: [64]Bitboard = precomputeAttacksKing();
const ATTACKS_PAWN: [2][64]Bitboard = precomputeAttacksPawn();

inline fn getAttacksPawn(from: Square, side: Color) Bitboard {
    return ATTACKS_PAWN[side.idx()][from.idx];
}

inline fn getAttacksKnight(from: Square) Bitboard {
    return ATTACKS_KNIGHT[from.idx];
}

inline fn getAttacksBishop(from: Square, occupied: Bitboard) Bitboard {
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

fn getAttacksRook(from: Square, occupied: Bitboard) Bitboard {
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

fn getAttacksQueen(from: Square, occupied: Bitboard) Bitboard {
    return getAttacksBishop(from, occupied) | getAttacksRook(from, occupied);
}

fn getAttacksKing(from: Square) Bitboard {
    return ATTACKS_KING[from.idx];
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
