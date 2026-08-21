const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

const types = @import("types.zig");
const Bitboard = types.Bitboard;
const Move = types.Move;
const PromotionPieceTypes = types.PromotionPieceTypes;
const PieceTypes = types.PieceTypes;
const MoveType = types.MoveType;
const Square = types.Square;
const Color = types.Color;
const PieceType = types.PieceType;

const Position = @import("Position.zig");

const attacks = @import("attacks.zig");

pub const MoveList = struct {
    moves: [255]Move = undefined,
    len: u8 = 0,

    fn append(self: *MoveList, move: Move) void {
        self.moves[self.len] = move;
        self.len += 1;
    }

    pub fn has(self: *MoveList, uci: []const u8, move_type: MoveType) bool {
        for (0..self.len) |i| {
            if (self.moves[i].equalsUci(uci)) {
                assert(self.moves[i].move_type == move_type);
                return true;
            }
        }
        return false;
    }

    fn draw(self: *const MoveList) void {
        var buf: [64]u8 = @splat(32);

        for (0..self.len) |i| {
            buf[self.moves[i].to.idx] = 'X';
        }

        std.debug.print("-" ** 33, .{});
        std.debug.print("\n", .{});
        for (0..8) |r| {
            std.debug.print("|", .{});
            for (0..8) |f| {
                const idx = (7 - r) * 8 + f;
                std.debug.print(" {c} |", .{buf[idx]});
            }
            std.debug.print("\n", .{});
            std.debug.print("-" ** 33, .{});
            std.debug.print("\n", .{});
        }
    }

    fn print(self: *const MoveList) void {
        var buffer: [5]u8 = undefined;
        for (0..self.len) |i| {
            const move = self.moves[i];
            std.debug.print("{s}\n", .{move.uci(&buffer)});
        }
    }

    fn reset(self: *MoveList) void {
        self.len = 0;
    }
};

fn getPawnPushes(square: Square, side: Color, occupied: Bitboard) Bitboard {
    var result: Bitboard = 0;

    // push single
    var target = square.rel(0, side.pawn_direction());
    if (target == null or occupied & target.?.mask() != 0) return result;

    result |= target.?.mask();

    // push double
    if (side == .White and square.rank() != 1) return result;
    if (side == .Black and square.rank() != 6) return result;

    target = square.rel(0, side.pawn_direction() * 2);

    if (target != null and occupied & target.?.mask() == 0) {
        result |= target.?.mask();
    }

    return result;
}

fn getEnPassantMoves(from: Square, side: Color, pos: *const Position, out: *MoveList) bool {
    const expected_rank: u3 = if (side == .White) 4 else 3;
    if (from.rank() != expected_rank) return false;

    var found: bool = false;

    const targets = [2]?Square{ from.rel(1, side.pawn_direction()), from.rel(-1, side.pawn_direction()) };

    for (targets) |target| {
        if (target == null) continue;

        if (target.?.mask() & pos.en_passant_targets != 0) {
            out.append(.{
                .piece = .Pawn,
                .from = from,
                .to = target.?,
                .move_type = .CAPTURE,
                .captured_piece = .Pawn,
            });
            found = true;
        }
    }

    return found;
}

fn getCastleMoves(from: Square, side: Color, pos: *const Position, occupied: Bitboard, out: *MoveList) bool {
    var found: bool = false;

    if (side == .White and from != Square.e1) return false;
    if (side == .Black and from != Square.e8) return false;
    if (!pos.castling_rights.has(side, .long) and !pos.castling_rights.has(side, .short)) return false;

    if (attacks.isInCheck(pos, side)) return false;

    if (pos.castling_rights.has(side, .short)) blk: {
        const squares: [2]Square = switch (side) {
            .White => [2]Square{ .f1, .g1 },
            .Black => [2]Square{ .f8, .g8 },
        };

        const mask = squares[0].mask() | squares[1].mask();

        if (mask & occupied != 0) break :blk;
        if (attacks.isAttacked(mask, side.opp(), pos)) break :blk;

        out.append(.{ .piece = .King, .from = from, .to = squares[1], .move_type = .CASTLE });
        found = true;
    }

    if (pos.castling_rights.has(side, .long)) blk: {
        const squares: [3]Square = switch (side) {
            .White => [3]Square{ .d1, .c1, .b1 },
            .Black => [3]Square{ .d8, .c8, .b8 },
        };

        const mask = squares[0].mask() | squares[1].mask();

        if ((mask | squares[2].mask()) & occupied != 0) break :blk;
        if (attacks.isAttacked(mask, side.opp(), pos)) break :blk; // only the king path should be free from checks

        out.append(.{
            .piece = .King,
            .from = from,
            .to = squares[1],
            .move_type = .CASTLE,
        });
        found = true;
    }

    return found;
}

fn getMoveSquares(piece: PieceType, from: Square, pos: *const Position, occupied: Bitboard, occupied_self: Bitboard, occupied_enemy: Bitboard) Bitboard {
    var squares = attacks.getAttacks(piece, pos.side_to_move, from, occupied) & ~occupied_self;

    if (piece == .Pawn) {
        squares &= occupied_enemy;
        squares |= getPawnPushes(from, pos.side_to_move, occupied);
    }

    return squares;
}

fn findInner(
    piece: PieceType,
    from: Square,
    pos: *const Position,
    occupied: Bitboard,
    occupied_self: Bitboard,
    occupied_enemy: Bitboard,
    out: *MoveList,
    stop_at_first: bool,
    captures_only: bool,
) void {
    var squares = getMoveSquares(piece, from, pos, occupied, occupied_self, occupied_enemy);
    if (captures_only) squares &= occupied_enemy;

    if (piece == .Pawn and getEnPassantMoves(from, pos.side_to_move, pos, out) and stop_at_first) return;
    if (!captures_only and piece == .King and getCastleMoves(from, pos.side_to_move, pos, occupied, out) and stop_at_first) return;

    while (squares != 0) : (squares &= squares - 1) {
        const target = Square.from_int(@ctz(squares));
        const captured_piece = pos.getPieceAtForSide(target, pos.sideEnemy());

        const mask = target.mask();

        if (piece == .Pawn) {
            if ((pos.side_to_move == .White and target.rank() == 7) or (pos.side_to_move == .Black and target.rank() == 0)) {
                inline for (PromotionPieceTypes) |prom_piece| {
                    const move_type: MoveType = if (occupied_enemy & target.mask() != 0) .CAPTURE else .NORMAL;
                    out.append(.{
                        .piece = piece,
                        .from = from,
                        .to = target,
                        .promotion_piece = prom_piece,
                        .move_type = move_type,
                        .captured_piece = captured_piece,
                    });
                    if (stop_at_first) return;
                }
                continue;
            }
        }
        const move_type: MoveType = if (mask & occupied_enemy == 0) .NORMAL else .CAPTURE;
        out.append(.{
            .piece = piece,
            .from = from,
            .to = target,
            .move_type = move_type,
            .captured_piece = captured_piece,
        });
        if (stop_at_first) return;
    }
}

fn findForPiece(
    piece: PieceType,
    from: Square,
    pos: *const Position,
    out: *MoveList,
) void {
    const occupied = pos.occupied();
    const occupied_self = pos.occupiedBy(pos.side_to_move);
    const occupied_enemy = pos.occupiedBy(pos.sideEnemy());

    return findInner(piece, from, pos, occupied, occupied_self, occupied_enemy, out, false, false);
}

test "pawn_moves" {
    const pos = Position.start();
    const square = Square.e2;

    var move_list: MoveList = .{};

    findForPiece(.Pawn, square, &pos, &move_list);
    try t.expectEqual(2, move_list.len);

    try t.expect(move_list.moves[0].equalsUci("e2e3"));
    try t.expect(move_list.moves[1].equalsUci("e2e4"));
}

test "pawn_step_starting" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, .e2);

    var move_list = MoveList{};
    findForPiece(.Pawn, .e2, &pos, &move_list);

    try t.expectEqual(2, move_list.len);

    try t.expect(move_list.has("e2e3", .NORMAL));
    try t.expect(move_list.has("e2e4", .NORMAL));
}

test "pawn_step_not_starting" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, .e3);

    var move_list = MoveList{};
    findForPiece(.Pawn, .e3, &pos, &move_list);

    try t.expectEqual(1, move_list.len);

    try t.expect(move_list.has("e3e4", .NORMAL));
}

test "pawn_step_blocked" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, .e2);
    pos.put(.Black, .Pawn, .e3);

    var move_list = MoveList{};
    findForPiece(.Pawn, .e2, &pos, &move_list);

    try t.expectEqual(0, move_list.len);
}

test "pawn_capture" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, .e2);
    pos.put(.Black, .Bishop, .d3);
    pos.put(.Black, .Bishop, .f3);

    var move_list = MoveList{};
    findForPiece(.Pawn, .e2, &pos, &move_list);

    try t.expectEqual(4, move_list.len);

    try t.expect(move_list.has("e2e3", .NORMAL));
    try t.expect(move_list.has("e2e4", .NORMAL));
    try t.expect(move_list.has("e2d3", .CAPTURE));
    try t.expect(move_list.has("e2f3", .CAPTURE));
}

test "pawn_capture_2" {
    var pos = Position.init(.Black);
    pos.put(.Black, .Pawn, .d5);
    pos.put(.Black, .Bishop, .d4);
    pos.put(.White, .Bishop, .c6);
    pos.put(.White, .Queen, .c4);

    var move_list = MoveList{};
    findForPiece(.Pawn, .d5, &pos, &move_list);

    try t.expectEqual(1, move_list.len);

    try t.expect(move_list.has("d5c4", .CAPTURE));
}

test "pawn_promotions" {
    var pos = Position.init(.White);

    pos.put(.White, .Pawn, .e7);

    var move_list = MoveList{};

    findForPiece(.Pawn, .e7, &pos, &move_list);

    try t.expectEqual(4, move_list.len);

    for (0..move_list.len) |i| {
        const move = move_list.moves[i];
        try t.expect(move.promotion_piece != .NO_PIECE_TYPE);
        try t.expectEqual(Square.e7, move.from);
        try t.expectEqual(Square.e8, move.to);
    }
}

test "pawn_en_passant" {
    var pos = Position.init(.White);

    pos.put(.White, .Pawn, .e2);
    pos.put(.Black, .Pawn, .d4);

    pos.put(.White, .Pawn, .e5);
    pos.put(.Black, .Pawn, .f7);

    try pos.go("e2e4");

    var move_list = MoveList{};

    findForPiece(.Pawn, .d4, &pos, &move_list);

    try t.expectEqual(2, move_list.len);
    try t.expect(move_list.has("d4e3", .CAPTURE));

    try pos.go("f7f5");

    move_list.reset();
    findForPiece(.Pawn, .e5, &pos, &move_list);

    try t.expectEqual(2, move_list.len);
    try t.expect(move_list.has("e5f6", .CAPTURE));
}

test "knight" {
    var pos = Position.init(.White);
    pos.put(.White, .Knight, .e4);

    var move_list = MoveList{};
    findForPiece(.Knight, .e4, &pos, &move_list);

    try t.expectEqual(8, move_list.len);

    try t.expect(move_list.has("e4d6", .NORMAL));
    try t.expect(move_list.has("e4f6", .NORMAL));
    try t.expect(move_list.has("e4c5", .NORMAL));
    try t.expect(move_list.has("e4g5", .NORMAL));
    try t.expect(move_list.has("e4c5", .NORMAL));
    try t.expect(move_list.has("e4g5", .NORMAL));
    try t.expect(move_list.has("e4c3", .NORMAL));
    try t.expect(move_list.has("e4g3", .NORMAL));
    try t.expect(move_list.has("e4d2", .NORMAL));
    try t.expect(move_list.has("e4f2", .NORMAL));
}

test "knight_2" {
    var pos = Position.init(.White);
    pos.put(.White, .Knight, .g4);
    pos.put(.White, .Queen, .f2);
    pos.put(.White, .King, .h2);
    pos.put(.Black, .Bishop, .f6);

    var move_list = MoveList{};
    findForPiece(.Knight, .g4, &pos, &move_list);

    try t.expectEqual(4, move_list.len);

    try t.expect(move_list.has("g4f6", .CAPTURE));
    try t.expect(move_list.has("g4h6", .NORMAL));
    try t.expect(move_list.has("g4e5", .NORMAL));
    try t.expect(move_list.has("g4e3", .NORMAL));
}

test "bishop" {
    var pos = Position.init(.White);
    pos.put(.White, .Bishop, .e4);

    var move_list = MoveList{};
    findForPiece(.Bishop, .e4, &pos, &move_list);

    try t.expectEqual(13, move_list.len);

    try t.expect(move_list.has("e4f5", .NORMAL));
    try t.expect(move_list.has("e4g6", .NORMAL));
    try t.expect(move_list.has("e4h7", .NORMAL));
    try t.expect(move_list.has("e4f3", .NORMAL));
    try t.expect(move_list.has("e4g2", .NORMAL));
    try t.expect(move_list.has("e4h1", .NORMAL));
    try t.expect(move_list.has("e4d5", .NORMAL));
    try t.expect(move_list.has("e4c6", .NORMAL));
    try t.expect(move_list.has("e4b7", .NORMAL));
    try t.expect(move_list.has("e4a8", .NORMAL));
    try t.expect(move_list.has("e4d3", .NORMAL));
    try t.expect(move_list.has("e4c2", .NORMAL));
    try t.expect(move_list.has("e4b1", .NORMAL));
}

test "bishop_2" {
    var pos = Position.init(.White);
    pos.put(.White, .Bishop, .g2);

    pos.put(.Black, .Knight, .f3);
    pos.put(.White, .Rook, .h1);

    var move_list = MoveList{};
    findForPiece(.Bishop, .g2, &pos, &move_list);

    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("g2h3", .NORMAL));
    try t.expect(move_list.has("g2f1", .NORMAL));
    try t.expect(move_list.has("g2f3", .CAPTURE));
}

test "rook" {
    var pos = Position.init(.White);
    pos.put(.White, .Rook, .e4);

    var move_list = MoveList{};
    findForPiece(.Rook, .e4, &pos, &move_list);

    try t.expectEqual(14, move_list.len);

    try t.expect(move_list.has("e4e5", .NORMAL));
    try t.expect(move_list.has("e4e6", .NORMAL));
    try t.expect(move_list.has("e4e7", .NORMAL));
    try t.expect(move_list.has("e4e8", .NORMAL));
    try t.expect(move_list.has("e4e3", .NORMAL));
    try t.expect(move_list.has("e4e2", .NORMAL));
    try t.expect(move_list.has("e4e1", .NORMAL));
    try t.expect(move_list.has("e4d4", .NORMAL));
    try t.expect(move_list.has("e4c4", .NORMAL));
    try t.expect(move_list.has("e4b4", .NORMAL));
    try t.expect(move_list.has("e4a4", .NORMAL));
    try t.expect(move_list.has("e4f4", .NORMAL));
    try t.expect(move_list.has("e4g4", .NORMAL));
    try t.expect(move_list.has("e4h4", .NORMAL));
}

test "rook_2" {
    var pos = Position.init(.White);
    pos.put(.White, .Rook, .g2);

    pos.put(.Black, .Knight, .g3);
    pos.put(.White, .Pawn, .f2);

    var move_list = MoveList{};
    findForPiece(.Rook, .g2, &pos, &move_list);

    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("g2g3", .CAPTURE));
    try t.expect(move_list.has("g2h2", .NORMAL));
    try t.expect(move_list.has("g2g1", .NORMAL));
}

test "queen" {
    var pos = Position.init(.White);
    pos.put(.White, .Queen, .d1);

    pos.put(.White, .Pawn, .d3);
    pos.put(.Black, .Pawn, .c2);
    pos.put(.White, .Bishop, .c1);
    pos.put(.White, .King, .e1);

    var move_list = MoveList{};
    findForPiece(.Queen, .d1, &pos, &move_list);

    try t.expectEqual(6, move_list.len);
}

test "king" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e4);

    var move_list = MoveList{};
    findForPiece(.King, .e4, &pos, &move_list);

    try t.expectEqual(8, move_list.len);

    try t.expect(move_list.has("e4e5", .NORMAL));
    try t.expect(move_list.has("e4d5", .NORMAL));
    try t.expect(move_list.has("e4f5", .NORMAL));
    try t.expect(move_list.has("e4d4", .NORMAL));
    try t.expect(move_list.has("e4f4", .NORMAL));
    try t.expect(move_list.has("e4d3", .NORMAL));
    try t.expect(move_list.has("e4e3", .NORMAL));
    try t.expect(move_list.has("e4f3", .NORMAL));
}

test "king_2" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e1);

    pos.put(.White, .Queen, .d1);
    pos.put(.White, .Pawn, .e2);

    pos.put(.Black, .Pawn, .d2);

    var move_list = MoveList{};
    findForPiece(.King, .e1, &pos, &move_list);

    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("e1f1", .NORMAL));
    try t.expect(move_list.has("e1f2", .NORMAL));
    try t.expect(move_list.has("e1d2", .CAPTURE));
}

test "castle_short" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e1);
    pos.put(.White, .Rook, .h1);
    pos.put(.White, .Pawn, .e2);
    pos.put(.White, .Pawn, .d2);
    pos.put(.White, .Pawn, .f2);
    pos.put(.White, .Queen, .d1);

    var move_list = MoveList{};
    findForPiece(.King, .e1, &pos, &move_list);

    try t.expect(move_list.has("e1g1", .CASTLE));
    try t.expect(!move_list.has("e1c1", .CASTLE));
}

test "castle_long_short" {
    var pos = Position.init(.Black);
    pos.put(.Black, .King, .e8);
    pos.put(.Black, .Rook, .a8);

    var move_list = MoveList{};
    findForPiece(.King, .e8, &pos, &move_list);

    try t.expect(move_list.has("e8c8", .CASTLE));
    try t.expect(move_list.has("e8g8", .CASTLE));
}

test "castle_king_in_check" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e1);
    pos.put(.White, .Rook, .a1);
    pos.put(.White, .Rook, .h1);

    pos.put(.Black, .Rook, .e8);

    var move_list = MoveList{};
    findForPiece(.King, .e1, &pos, &move_list);

    try t.expect(!move_list.has("e1c1", .CASTLE));
    try t.expect(!move_list.has("e1g1", .CASTLE));
}

test "castle_king_path_in_check" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e1);
    pos.put(.White, .Rook, .a1);
    pos.put(.White, .Rook, .h1);

    pos.put(.Black, .Rook, .b8);
    pos.put(.Black, .Rook, .g8);

    var move_list = MoveList{};
    findForPiece(.King, .e1, &pos, &move_list);

    try t.expect(!move_list.has("e1g1", .CASTLE));
    try t.expect(move_list.has("e1c1", .CASTLE));
}

fn findAllInner(pos: *const Position, out: *MoveList, captures_only: bool) void {
    const occupied = pos.occupied();
    const occupied_self = pos.occupiedBy(pos.side_to_move);
    const occupied_enemy = pos.occupiedBy(pos.sideEnemy());

    inline for (PieceTypes) |piece| {
        var placements = pos.piece_boards[pos.side_to_move.idx()][piece.idx()];

        while (placements != 0) : (placements &= placements - 1) {
            const square = Square.from_int(@ctz(placements));

            findInner(piece, square, pos, occupied, occupied_self, occupied_enemy, out, false, captures_only);
        }
    }
}

pub fn findAll(pos: *const Position, out: *MoveList) void {
    var move_list = MoveList{};

    findAllInner(pos, &move_list, false);

    for (0..move_list.len) |i| {
        const move = move_list.moves[i];
        var pos_copy = pos.*;
        pos_copy.apply(move);
        if (!attacks.isInCheck(&pos_copy, pos.side_to_move)) out.append(move);
    }
}

// pseudo-legal
pub fn findCaptures(pos: *const Position, out: *MoveList) void {
    findAllInner(pos, out, true);
}

pub fn findAllPseudoLegal(pos: *const Position, out: *MoveList) void {
    findAllInner(pos, out, false);
}

test "find captures" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e1);
    pos.put(.White, .Queen, .d4);
    pos.put(.White, .Pawn, .e5);
    pos.put(.Black, .King, .e8);
    pos.put(.Black, .Rook, .d5);
    pos.put(.Black, .Pawn, .f6);

    var move_list = MoveList{};
    findCaptures(&pos, &move_list);

    try t.expectEqual(2, move_list.len);
    try t.expect(move_list.has("d4d5", .CAPTURE));
    try t.expect(move_list.has("e5f6", .CAPTURE));
}

test "find captures en passant" {
    var pos = Position.init(.White);
    pos.put(.White, .King, .e1);
    pos.put(.White, .Pawn, .e5);
    pos.put(.Black, .King, .e8);
    pos.put(.Black, .Pawn, .d5);
    pos.en_passant_targets = Square.d6.mask();

    var move_list = MoveList{};
    findCaptures(&pos, &move_list);

    try t.expectEqual(1, move_list.len);
    try t.expect(move_list.has("e5d6", .CAPTURE));
}

pub fn hasMoves(pos: *const Position) bool {
    var move_list = MoveList{};

    const occupied = pos.occupied();
    const occupied_self = pos.occupiedBy(pos.side_to_move);
    const occupied_enemy = pos.occupiedBy(pos.sideEnemy());

    var idx: usize = 0;

    inline for (PieceTypes) |piece| {
        var placements = pos.piece_boards[pos.side_to_move.idx()][piece.idx()];

        while (placements != 0) : (placements &= placements - 1) {
            const square = Square.from_int(@ctz(placements));

            findInner(piece, square, pos, occupied, occupied_self, occupied_enemy, &move_list, true, false);
            for (idx..move_list.len) |i| {
                const move = move_list.moves[i];
                var pos_copy = pos.*;
                pos_copy.apply(move);
                if (!attacks.isInCheck(&pos_copy, pos.side_to_move)) return true;
                idx += 1;
            }
        }
    }

    return false;
}

test "starting_moves" {
    var position = Position.start();

    var move_list: MoveList = .{};

    findAll(&position, &move_list);
    try t.expectEqual(20, move_list.len);

    position.side_to_move = .Black;
    move_list = .{};

    findAll(&position, &move_list);
    try t.expectEqual(20, move_list.len);
}

test "skips_moves_exposing_king" {
    var position = Position.start();

    position.put(.Black, .Bishop, .b4);

    var move_list: MoveList = .{};

    findAll(&position, &move_list);

    try t.expectEqual(17, move_list.len);

    try t.expect(!move_list.has("d2d3", .NORMAL));
    try t.expect(!move_list.has("d2d4", .NORMAL));
    try t.expect(!move_list.has("b2b4", .NORMAL));
}

pub fn isMoveLegal(pos: *const Position, move: Move) bool {
    var legal_moves = MoveList{};
    findAll(pos, &legal_moves);

    for (0..legal_moves.len) |i| {
        const candidate = legal_moves.moves[i];
        if (candidate.move_type == move.move_type and candidate.from == move.from and candidate.to == move.to) return true;
    }

    return false;
}
