const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

const types = @import("types.zig");
const Bitboard = types.Bitboard;
const Move = types.Move;
const PieceTypes = types.PieceTypes;
const PieceType = types.PieceType;
const Color = types.Color;

const Position = @import("Position.zig");
const attacks = @import("attacks.zig");
const movegen = @import("movegen.zig");

const PIECE_WORTH = [_]i8{ 1, 3, 3, 5, 9, 0 };

inline fn pieceWorth(piece: PieceType) i8 {
    return PIECE_WORTH[piece.idx()];
}

fn materialScore(piece_boards: [6]Bitboard) f16 {
    var score: f16 = 0;

    inline for (PieceTypes) |piece| {
        score += @popCount(piece_boards[piece.idx()]) * pieceWorth(piece);
    }

    return score;
}

fn controlScoreInner(pos: *const Position, side: Color, occupied: Bitboard, occupied_self: Bitboard) f16 {
    const controlled = attacks.attackedMask(pos, side, occupied);

    return @as(f16, @popCount(controlled & ~occupied_self));
}

fn controlScore(pos: *const Position) f16 {
    const occupied_white = pos.occupiedBy(.White);
    const occupied_black = pos.occupiedBy(.Black);
    const occupied = occupied_white | occupied_black;

    const score_white = controlScoreInner(pos, .White, occupied, occupied_white);
    const score_black = controlScoreInner(pos, .Black, occupied, occupied_black);

    return score_white - score_black;
}

inline fn staticEval(pos: *const Position) f16 {
    const material = materialScore(pos.piece_boards[Color.White.idx()]) - materialScore(pos.piece_boards[Color.Black.idx()]);
    const control = controlScore(pos);

    return material + 0.05 * control;
}

fn movePriority(move: Move) i8 {
    if (move.move_type == .CAPTURE) {
        // https://chessprogramming.org/MVV-LVA
        // TODO: this should somehow account for protected pieces
        return pieceWorth(move.captured_piece) - pieceWorth(move.piece) + 10;
    }

    if (move.promotion_piece != .NO_PIECE_TYPE) return pieceWorth(move.promotion_piece);

    return 0;
}

fn moveCmp(prior_best_move: ?Move, lhs: Move, rhs: Move) bool {
    if (prior_best_move != null) {
        if (prior_best_move.?.equals(lhs)) return true;
        if (prior_best_move.?.equals(rhs)) return false;
    }

    return movePriority(lhs) > movePriority(rhs);
}

// https://chessprogramming.org/Node_Types
const EntryType = enum(u2) {
    EXACT,
    LOWERBOUND,
    UPPERBOUND,
};

const TranspositionEntry = struct {
    score: f16 = 0,
    depth: u8,
    best_move: ?Move = null,
    entry_type: EntryType = .EXACT,
};

// https://chessprogramming.org/Transposition_Table
pub const TranspositionTable = std.AutoHashMap(u64, TranspositionEntry);

const MinimaxResult = struct {
    score: f16,
    best_move: ?Move = null,
};

inline fn losingScore(maximize: bool) f16 {
    return if (maximize) -std.math.floatMax(f16) else std.math.floatMax(f16);
}

inline fn gameOverScore(pos: *const Position, maximize: bool) f16 {
    if (attacks.isInCheck(pos, pos.side_to_move)) {
        return losingScore(maximize);
    } else return 0;
}

const QUIESCENCE_MAX_DEPTH: u8 = 8;

// https://chessprogramming.org/Quiescence_Search
fn quiescence(pos: *const Position, a: f16, b: f16, depth: u8) f16 {
    var alpha = a;
    var beta = b;

    const maximize = pos.side_to_move == .White;

    if (depth >= QUIESCENCE_MAX_DEPTH) {
        if (!movegen.hasMoves(pos)) return gameOverScore(pos, maximize);
        return staticEval(pos);
    }

    var move_list = movegen.MoveList{};
    var score: f16 = undefined;

    const in_check = attacks.isInCheck(pos, pos.side_to_move);

    if (in_check) {
        score = losingScore(maximize);
        movegen.findAllPseudoLegal(pos, &move_list);
    } else {
        score = staticEval(pos);

        if (maximize) {
            if (score >= beta) return if (movegen.hasMoves(pos)) score else 0;
            alpha = @max(alpha, score);
        } else {
            if (score <= alpha) return if (movegen.hasMoves(pos)) score else 0;
            beta = @min(beta, score);
        }

        movegen.findCaptures(pos, &move_list);
    }

    std.sort.insertion(Move, move_list.moves[0..move_list.len], @as(?Move, null), moveCmp);

    var legal_move_exists = false;

    for (0..move_list.len) |i| {
        var pos_copy = pos.*;
        pos_copy.apply(move_list.moves[i]);
        if (attacks.isInCheck(&pos_copy, pos.side_to_move)) continue;

        legal_move_exists = true;

        const current = quiescence(&pos_copy, alpha, beta, depth + 1);

        if (maximize) {
            score = @max(score, current);
            alpha = @max(alpha, score);
        } else {
            score = @min(score, current);
            beta = @min(beta, score);
        }

        if (alpha >= beta) break;
    }

    if (!legal_move_exists) {
        if (in_check) return score;
        return if (movegen.hasMoves(pos)) score else 0;
    }

    return score;
}

fn minimax(pos: *const Position, depth: u8, a: ?f16, b: ?f16, table: *TranspositionTable) !MinimaxResult {
    var alpha = a orelse -std.math.floatMax(f16);
    var beta = b orelse std.math.floatMax(f16);

    const existing = table.get(pos.hash);
    if (existing != null and existing.?.depth >= depth) {
        const ex = existing.?;
        const existing_result = MinimaxResult{ .score = existing.?.score, .best_move = existing.?.best_move };

        switch (ex.entry_type) {
            .EXACT => return existing_result,
            .LOWERBOUND => alpha = @max(alpha, ex.score),
            .UPPERBOUND => beta = @min(beta, ex.score),
        }

        if (alpha >= beta) return existing_result;
    }

    if (depth == 0) return MinimaxResult{ .score = quiescence(pos, alpha, beta, 0) };

    const prior_best_move = if (existing != null) existing.?.best_move else null;
    var entry: TranspositionEntry = .{ .depth = depth, .entry_type = .EXACT };
    const maximize: bool = pos.side_to_move == .White;

    var move_list = movegen.MoveList{};
    movegen.findAllPseudoLegal(pos, &move_list);
    std.sort.insertion(Move, move_list.moves[0..move_list.len], prior_best_move, moveCmp);

    entry.score = losingScore(maximize);
    var legal_move_exists = false;

    for (0..move_list.len) |i| {
        var pos_copy = pos.*;
        const move = move_list.moves[i];
        pos_copy.apply(move);

        if (attacks.isInCheck(&pos_copy, pos.side_to_move)) continue;
        legal_move_exists = true;

        const current = try minimax(&pos_copy, depth - 1, alpha, beta, table);

        if (maximize) {
            if (entry.best_move == null or current.score > entry.score) {
                entry.score = current.score;
                entry.best_move = move;
            }
            alpha = @max(alpha, entry.score);
        } else {
            if (entry.best_move == null or current.score < entry.score) {
                entry.score = current.score;
                entry.best_move = move;
            }
            beta = @min(beta, entry.score);
        }

        if (alpha >= beta) {
            entry.entry_type = if (maximize) .LOWERBOUND else .UPPERBOUND;
            break;
        }
    }

    if (!legal_move_exists) entry.score = gameOverScore(pos, maximize);

    try table.put(pos.hash, entry);
    return MinimaxResult{ .score = entry.score, .best_move = entry.best_move };
}

test "minimax_static" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e1);
    pos.put(.White, .Pawn, .e2);
    pos.put(.White, .Pawn, .d2);
    pos.put(.White, .Pawn, .c2);
    pos.put(.White, .Rook, .a1);
    pos.put(.White, .Knight, .b1);
    pos.put(.White, .Bishop, .c1);
    pos.put(.Black, .King, .e8);
    pos.put(.Black, .Queen, .d8);
    pos.put(.Black, .Pawn, .e7);

    var table: TranspositionTable = .init(t.allocator);
    defer table.deinit();

    const result = try minimax(&pos, 0, null, null, &table);
    try t.expect(result.score > 0);
}

test "minimax quiescence ignores illegal capture" {
    var pos = Position.init(.Black);
    pos.put(.Black, .King, .h8);
    pos.put(.Black, .Pawn, .g7);
    pos.put(.White, .King, .f7);
    pos.put(.White, .Queen, .g6);
    pos.put(.White, .Knight, .h6);
    pos.put(.White, .Bishop, .c3);

    var captures = movegen.MoveList{};
    movegen.findCaptures(&pos, &captures);
    try t.expect(captures.has("g7h6", .CAPTURE));
    try t.expect(!attacks.isInCheck(&pos, .Black));
    try t.expect(!movegen.hasMoves(&pos));

    var table: TranspositionTable = .init(t.allocator);
    defer table.deinit();

    const result = try minimax(&pos, 0, null, null, &table);
    try t.expectEqual(@as(f16, 0), result.score);
    try t.expectEqual(null, result.best_move);
}

test "minimax ignores illegal move" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e1);
    pos.put(.White, .Rook, .e2);
    pos.put(.Black, .King, .c3);
    pos.put(.Black, .Queen, .d2);
    pos.put(.Black, .Rook, .e8);

    var pseudo_legal_moves = movegen.MoveList{};
    movegen.findAllPseudoLegal(&pos, &pseudo_legal_moves);
    try t.expect(pseudo_legal_moves.has("e2d2", .CAPTURE));

    var table: TranspositionTable = .init(t.allocator);
    defer table.deinit();

    const result = try minimax(&pos, 1, null, null, &table);
    try t.expect(result.best_move != null);
    try t.expect(!result.best_move.?.equalsUci("e2d2"));

    var next = pos;
    next.apply(result.best_move.?);
    try t.expect(!attacks.isInCheck(&next, .White));
}

test "minimax_stalemate" {
    var pos = Position.init(.Black);
    pos.put(.Black, .King, .h8);
    pos.put(.White, .King, .g6);
    pos.put(.White, .Queen, .f7);

    var table: TranspositionTable = .init(t.allocator);
    defer table.deinit();

    const result = try minimax(&pos, 0, null, null, &table);
    try t.expectEqual(0, result.score);

    table.clearRetainingCapacity();
    const result_2 = try minimax(&pos, 1, null, null, &table);
    try t.expectEqual(0, result_2.score);
}

test "minimax_checkmate" {
    const checkmate_score = std.math.floatMax(f16);

    var table: TranspositionTable = .init(t.allocator);
    defer table.deinit();

    {
        var pos = Position.init(.Black);
        pos.put(.Black, .King, .h8);
        pos.put(.White, .Queen, .g7);
        pos.put(.White, .King, .f6);

        const result = try minimax(&pos, 0, null, null, &table);
        try t.expectEqual(checkmate_score, result.score);

        table.clearRetainingCapacity();
        const result_2 = try minimax(&pos, 1, null, null, &table);
        try t.expectEqual(checkmate_score, result_2.score);
    }

    {
        var pos = Position.init(.White);
        pos.put(.Black, .King, .h8);
        pos.put(.White, .Queen, .g1);
        pos.put(.White, .King, .f6);

        table.clearRetainingCapacity();
        const result = try minimax(&pos, 1, null, null, &table);
        try t.expectEqual(checkmate_score, result.score);
    }
}

pub fn findBestMove(pos: *const Position, depth: u8, table: *TranspositionTable) !?Move {
    assert(depth > 0);

    var result: MinimaxResult = undefined;
    var current_depth: u8 = 1;
    while (current_depth <= depth) : (current_depth += 1) {
        result = try minimax(pos, current_depth, null, null, table);
    }

    return result.best_move;
}

test "find_best_move" {
    var pos = try Position.fromFEN("rnbqkbnr/pp3ppp/2pp4/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 0 4");

    var table: TranspositionTable = .init(t.allocator);
    defer table.deinit();

    const best_move = try findBestMove(&pos, 1, &table);
    try t.expectEqual(types.Square.f7, best_move.?.to);
    try t.expectEqual(types.Square.f3, best_move.?.from);
}
