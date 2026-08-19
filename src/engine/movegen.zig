const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

const board = @import("board.zig");
const Bitboard = board.Bitboard;
const Move = board.Move;
const PromotionPieces = board.PromotionPieces;
const MoveType = board.MoveType;
const Position = board.Position;
const Square = board.Square;
const Color = board.Color;
const Piece = board.Piece;

const attacks = @import("attacks.zig");

pub const MoveList = struct {
    moves: [255]Move = undefined,
    len: u8 = 0,

    fn append(self: *MoveList, move: Move) void {
        self.moves[self.len] = move;
        self.len += 1;
    }

    fn has(self: *MoveList, uci: []const u8, move_type: MoveType) bool {
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

    if (isInCheck(pos, side)) return false;

    if (pos.castling_rights.has(side, .short)) blk: {
        const squares: [2]Square = switch (side) {
            .White => [2]Square{ .f1, .g1 },
            .Black => [2]Square{ .f8, .g8 },
        };

        const mask = squares[0].mask() | squares[1].mask();

        if (mask & occupied != 0) break :blk;
        if (isAttacked(mask, side.opp(), pos)) break :blk;

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
        if (isAttacked(mask, side.opp(), pos)) break :blk; // only the king path should be free from checks

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

fn getMoveSquares(piece: Piece, from: Square, pos: *const Position, occupied: Bitboard, occupied_self: Bitboard, occupied_enemy: Bitboard) Bitboard {
    var squares = attacks.getAttacks(piece, pos.side_to_move, from, occupied) & ~occupied_self;

    if (piece == .Pawn) {
        squares &= occupied_enemy;
        squares |= getPawnPushes(from, pos.side_to_move, occupied);
    }

    return squares;
}

fn findInner(
    piece: Piece,
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
                inline for (PromotionPieces) |prom_piece| {
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
    piece: Piece,
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
        try t.expect(move.promotion_piece != null);
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

    inline for (std.enums.values(Piece)) |piece| {
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
        if (!isInCheck(&pos_copy, pos.side_to_move)) out.append(move);
    }
}

// pseudo-legal
fn findCaptures(pos: *const Position, out: *MoveList) void {
    findAllInner(pos, out, true);
}

fn findAllPseudoLegal(pos: *const Position, out: *MoveList) void {
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

    inline for (std.enums.values(Piece)) |piece| {
        var placements = pos.piece_boards[pos.side_to_move.idx()][piece.idx()];

        while (placements != 0) : (placements &= placements - 1) {
            const square = Square.from_int(@ctz(placements));

            findInner(piece, square, pos, occupied, occupied_self, occupied_enemy, &move_list, true, false);
            for (idx..move_list.len) |i| {
                const move = move_list.moves[i];
                var pos_copy = pos.*;
                pos_copy.apply(move);
                if (!isInCheck(&pos_copy, pos.side_to_move)) return true;
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

fn isAttackedBy(area_mask: Bitboard, piece: Piece, attacker: Color, pos: *const Position, occupied: Bitboard) bool {
    var pieces = pos.piece_boards[attacker.idx()][piece.idx()];
    while (pieces != 0) : (pieces &= pieces - 1) {
        const square = Square.from_int(@ctz(pieces));
        const attacked = attacks.getAttacks(piece, attacker, square, occupied);
        if (attacked & area_mask != 0) return true;
    }

    return false;
}

// is any square in the area mask attacked by any piece of the attacker side
fn isAttacked(area: Bitboard, attacker: Color, pos: *const Position) bool {
    const occupied = pos.occupied();

    inline for (std.enums.values(Piece)) |piece| {
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

    if (pawn_attacks & pos.piece_boards[defender.opp().idx()][Piece.Pawn.idx()] != 0) return true;

    const knight_attacks = attacks.getAttacksKnight(square);
    if (knight_attacks & pos.piece_boards[defender.opp().idx()][Piece.Knight.idx()] != 0) return true;

    const king_attacks = attacks.getAttacksKing(square);
    if (king_attacks & pos.piece_boards[defender.opp().idx()][Piece.King.idx()] != 0) return true;

    const occupied = pos.occupied();

    const attacker_pieces = pos.piece_boards[defender.opp().idx()];

    const rook_attacks = attacks.getAttacksRook(square, occupied);
    if (rook_attacks & (attacker_pieces[Piece.Rook.idx()] | attacker_pieces[Piece.Queen.idx()]) != 0) return true;

    const bishop_attacks = attacks.getAttacksBishop(square, occupied);
    return bishop_attacks & (attacker_pieces[Piece.Bishop.idx()] | attacker_pieces[Piece.Queen.idx()]) != 0;
}

pub fn isInCheck(pos: *const Position, side: Color) bool {
    const king_mask = pos.piece_boards[side.idx()][Piece.King.idx()];
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

fn pieceWorth(piece: Piece) i8 {
    return switch (piece) {
        .Pawn => 1,
        .Knight => 3,
        .Bishop => 3,
        .Rook => 5,
        .Queen => 9,
        .King => 0,
    };
}

fn materialScore(piece_boards: [6]Bitboard) f16 {
    var score: f16 = 0;

    inline for (std.enums.values(Piece)) |piece| {
        score += @popCount(piece_boards[piece.idx()]) * pieceWorth(piece);
    }

    return score;
}

fn controlScoreInner(pos: *const Position, side: Color, occupied: Bitboard) f16 {
    var result: f16 = 0;

    const controlled = attacks.attackedMask(pos, side, occupied);

    inline for (std.enums.values(Piece)) |piece| {
        const placements = pos.piece_boards[side.opp().idx()][piece.idx()];
        const worth = if (piece == .King) 5 else pieceWorth(piece);

        result += @popCount(placements & controlled) * worth;
    }

    // mobility bonus
    result += 0.2 * @as(f16, @popCount(controlled & ~occupied));

    return result;
}

fn controlScore(pos: *const Position) f16 {
    const occupied = pos.occupied();

    const score_white = controlScoreInner(pos, .White, occupied);
    const score_black = controlScoreInner(pos, .Black, occupied);

    return score_white - score_black;
}

inline fn staticEval(pos: *const Position) f16 {
    const material = materialScore(pos.piece_boards[Color.White.idx()]) - materialScore(pos.piece_boards[Color.Black.idx()]);

    const control = controlScore(pos);

    const total = material + 0.05 * control;

    // std.debug.print("material: {}, control: {}, total: {}\n", .{ material, control, total });

    return total;
}

fn movePriority(move: Move) i8 {
    if (move.move_type == .CAPTURE) {
        // https://chessprogramming.org/MVV-LVA
        // TODO: this should somehow account for protected pieces
        return pieceWorth(move.captured_piece.?) - pieceWorth(move.piece) + 10;
    }

    if (move.promotion_piece != null) return pieceWorth(move.promotion_piece.?);

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
    if (isInCheck(pos, pos.side_to_move)) {
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
        if (!hasMoves(pos)) return gameOverScore(pos, maximize);
        return staticEval(pos);
    }

    var move_list = MoveList{};
    var score: f16 = undefined;

    const in_check = isInCheck(pos, pos.side_to_move);

    if (in_check) {
        score = losingScore(maximize);
        findAllPseudoLegal(pos, &move_list);
    } else {
        score = staticEval(pos);

        if (maximize) {
            if (score >= beta) return if (hasMoves(pos)) score else 0;
            alpha = @max(alpha, score);
        } else {
            if (score <= alpha) return if (hasMoves(pos)) score else 0;
            beta = @min(beta, score);
        }

        findCaptures(pos, &move_list);
    }

    std.sort.insertion(Move, move_list.moves[0..move_list.len], @as(?Move, null), moveCmp);

    var legal_move_exists = false;

    for (0..move_list.len) |i| {
        var pos_copy = pos.*;
        pos_copy.apply(move_list.moves[i]);
        if (isInCheck(&pos_copy, pos.side_to_move)) continue;

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
        return if (hasMoves(pos)) score else 0;
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
            .LOWERBOUND => {
                alpha = @max(alpha, ex.score);
            },
            .UPPERBOUND => {
                beta = @min(beta, ex.score);
            },
        }

        if (alpha >= beta) return existing_result;
    }

    if (depth == 0) return MinimaxResult{ .score = quiescence(pos, alpha, beta, 0) };

    const prior_best_move = if (existing != null) existing.?.best_move else null;

    var entry: TranspositionEntry = .{ .depth = depth, .entry_type = .EXACT };

    const maximize: bool = (pos.side_to_move == .White);

    var move_list = MoveList{};
    findAllPseudoLegal(pos, &move_list);

    std.sort.insertion(Move, move_list.moves[0..move_list.len], prior_best_move, moveCmp);

    entry.score = losingScore(maximize);
    var legal_move_exists = false;

    for (0..move_list.len) |i| {
        var pos_copy = pos.*;
        const move = move_list.moves[i];
        pos_copy.apply(move);

        if (isInCheck(&pos_copy, pos.side_to_move)) continue;

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

    if (!legal_move_exists) {
        entry.score = gameOverScore(pos, maximize);
    }

    try table.put(pos.hash, entry);

    return MinimaxResult{ .score = entry.score, .best_move = entry.best_move };
}

test "minimax_static" {
    var pos = Position.init(.White);

    pos.put(.White, .King, .e1);

    // 3
    pos.put(.White, .Pawn, .e2);
    pos.put(.White, .Pawn, .d2);
    pos.put(.White, .Pawn, .c2);

    // 5 + 3 + 3
    pos.put(.White, .Rook, .a1);
    pos.put(.White, .Knight, .b1);
    pos.put(.White, .Bishop, .c1);

    pos.put(.Black, .King, .e8);

    // 9 + 1
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

    var captures = MoveList{};
    findCaptures(&pos, &captures);

    try t.expect(captures.has("g7h6", .CAPTURE));
    try t.expect(!isInCheck(&pos, .Black));
    try t.expect(!hasMoves(&pos));

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

    var pseudo_legal_moves = MoveList{};
    findAllPseudoLegal(&pos, &pseudo_legal_moves);
    try t.expect(pseudo_legal_moves.has("e2d2", .CAPTURE));

    var table: TranspositionTable = .init(t.allocator);
    defer table.deinit();

    const result = try minimax(&pos, 1, null, null, &table);
    try t.expect(result.best_move != null);
    try t.expect(!result.best_move.?.equalsUci("e2d2"));

    var next = pos;
    next.apply(result.best_move.?);
    try t.expect(!isInCheck(&next, .White));
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
        // checkmate
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
        // checkmate next move
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
        // TODO: log nodes, nps, depth, best move
    }

    return result.best_move;
}

test "find_best_move" {
    // scholars mate in one
    var pos = try Position.fromFEN("rnbqkbnr/pp3ppp/2pp4/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 0 4");

    var table: TranspositionTable = .init(t.allocator);
    defer table.deinit();

    const best_move = try findBestMove(&pos, 1, &table);

    try t.expectEqual(Square.f7, best_move.?.to);
    try t.expectEqual(Square.f3, best_move.?.from);
}
