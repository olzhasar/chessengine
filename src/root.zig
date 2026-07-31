const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

// [color][piece type] bitmasks. LSB (bit 0) - a1, MSB (bit 63) - h8.
const Bitboard = [2][6]u64;

const Color = enum(u1) {
    White,
    Black,

    fn idx(self: Color) usize {
        return @intFromEnum(self);
    }

    // get the opposite color
    fn opp(self: Color) Color {
        if (self == .White) return .Black;
        return .White;
    }

    fn symbol(self: Color) u8 {
        if (self == .White) return 'W' else return 'B';
    }
};

// square address 0-63
const Square = struct {
    idx: u8,

    fn at(addr: *const [2]u8) Square {
        assert(addr[1] >= '1' and addr[1] <= '8');
        assert(addr[0] >= 'a' and addr[0] <= 'h');

        return .{ .idx = (addr[1] - '1') * 8 + addr[0] - 'a' };
    }

    fn get(idx: u8) Square {
        assert(idx >= 0 and idx < 64);
        return .{ .idx = idx };
    }

    fn file(self: Square) u3 {
        return @truncate(self.idx % 8);
    }

    fn rank(self: Square) u3 {
        return @truncate(self.idx / 8);
    }

    fn file_str(self: Square) u8 {
        return @as(u8, 'a') + self.file();
    }

    fn rank_str(self: Square) u8 {
        return @as(u8, '1') + self.rank();
    }

    fn str(self: Square) [2]u8 {
        return .{
            self.file_str(),
            self.rank_str(),
        };
    }

    // locate a square shifted relative to the current one, null if out of bounds
    fn rel(self: Square, file_shift: i8, rank_shift: i8) ?Square {
        const target_rank: i16 = self.rank() + rank_shift;
        if (target_rank < 0 or target_rank > 7) return null;

        const target_file: i16 = self.file() + file_shift;
        if (target_file < 0 or target_file > 7) return null;

        return .{ .idx = @as(u8, @intCast(target_rank * 8)) + @as(u8, @intCast(target_file)) };
    }

    // get bitmask for bitwise operations with bitboard
    fn mask(self: Square) u64 {
        return @as(u64, 1) << @intCast(self.idx);
    }
};

test "square_from_addr" {
    const cases = [_]struct { input: *const [2]u8, expected: u8 }{
        .{ .input = "a1", .expected = 0 },
        .{ .input = "h8", .expected = 63 },
        .{ .input = "c2", .expected = 10 },
    };

    for (cases) |case| {
        const sq: Square = Square.at(case.input);
        try t.expectEqual(case.expected, sq.idx);
        try t.expectEqualStrings(case.input, &sq.str());
    }
}

const Piece = enum(u3) {
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

    fn idx(self: Piece) usize {
        return @intFromEnum(self);
    }
};

const MoveType = enum {
    NORMAL,
    CAPTURE,
    CASTLE,
    PROMOTION,
    EN_PASSANT,
};

const Move = struct {
    from: Square,
    to: Square,
    move_type: MoveType = .NORMAL,

    fn str(self: Move) [4]u8 {
        return [4]u8{
            self.from.file_str(),
            self.from.rank_str(),
            self.to.file_str(),
            self.to.rank_str(),
        };
    }
};

const MoveList = struct {
    moves: [255]Move = undefined,
    len: u8 = 0,

    fn append(self: *MoveList, from: Square, to: Square, move_type: MoveType) void {
        self.moves[self.len] = .{ .from = from, .to = to, .move_type = move_type };
        self.len += 1;
    }

    fn append_move(self: *MoveList, move: Move) void {
        self.moves[self.len] = move;
        self.len += 1;
    }

    fn has(self: *MoveList, str: []const u8, move_type: MoveType) bool {
        for (0..self.len) |i| {
            if (std.mem.eql(u8, &self.moves[i].str(), str)) {
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
        for (0..self.len) |i| {
            const move = self.moves[i];
            std.debug.print("{s}\n", .{move.str()});
        }
    }
};

const Position = struct {
    pieces: Bitboard,
    side_to_move: Color,

    // the enemy (opposite) of the current side_to_move
    fn side_enemy(self: *const Position) Color {
        return self.side_to_move.opp();
    }

    fn init(side_to_move: Color) Position {
        return .{
            .side_to_move = side_to_move,
            .pieces = .{
                @splat(0),
                @splat(0),
            },
        };
    }

    fn put(self: *Position, color: Color, piece: Piece, addr: *const [2]u8) void {
        const square = Square.at(addr);
        assert(self.occupied() & square.mask() == 0);

        self.pieces[color.idx()][piece.idx()] |= square.mask();
    }

    fn apply(self: *Position, move: Move) void {
        const from_mask = move.from.mask();
        const to_mask = move.to.mask();

        for (&self.pieces[self.side_to_move.idx()]) |*bitmask| {
            if (bitmask.* & from_mask != 0) {
                bitmask.* ^= from_mask;
                bitmask.* |= to_mask;
                break;
            }
        } else unreachable;

        if (move.move_type == .CAPTURE) {
            for (&self.pieces[self.side_enemy().idx()]) |*bitmask| {
                if (bitmask.* & to_mask != 0) {
                    bitmask.* ^= to_mask;
                    break;
                }
            } else unreachable;
        }
    }

    fn start() Position {
        return .{
            .pieces = .{
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
    }

    fn print(self: *const Position) void {
        var piece_mask: [64]u21 = @splat(32);
        var color_mask: [64]u8 = @splat(32);

        inline for (std.enums.values(Color), 0..) |col, ci| {
            inline for (std.enums.values(Piece), 0..) |piece, pi| {
                const bitmask = self.pieces[ci][pi];

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

    fn occupied(self: *const Position) u64 {
        return self.occupiedBy(.White) | self.occupiedBy(.Black);
    }

    fn occupiedBy(self: *const Position, color: Color) u64 {
        var result: u64 = 0;
        inline for (std.enums.values(Piece)) |piece| {
            result |= self.pieces[color.idx()][piece.idx()];
        }

        return result;
    }
};

test "position_apply" {
    var pos = Position.start();

    const move = Move{ .from = .at("e2"), .to = .at("e4"), .move_type = .NORMAL };

    try t.expect(pos.pieces[Color.White.idx()][Piece.Pawn.idx()] & move.from.mask() != 0);
    try t.expectEqual(pos.pieces[Color.White.idx()][Piece.Pawn.idx()] & move.to.mask(), 0);

    pos.apply(move);

    try t.expectEqual(pos.pieces[Color.White.idx()][Piece.Pawn.idx()] & move.from.mask(), 0);
    try t.expect(pos.pieces[Color.White.idx()][Piece.Pawn.idx()] & move.to.mask() != 0);
}

fn getAttacksPawn(from: Square, side: Color, occupied: u64) u64 {
    var result: u64 = 0;

    const left = if (side == .White) from.rel(-1, 1) else from.rel(1, -1);
    if (left != null and left.?.mask() & occupied != 0) result |= left.?.mask();

    const right = if (side == .White) from.rel(1, 1) else from.rel(-1, -1);
    if (right != null and right.?.mask() & occupied != 0) result |= right.?.mask();

    return result;
}

fn getAttacksKnight(from: Square) u64 {
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

    var result: u64 = 0;

    for (&directions) |dir| {
        const target = from.rel(dir.x, dir.y);
        if (target != null) result |= target.?.mask();
    }

    return result;
}

fn getAttacksBishop(from: Square, occupied: u64) u64 {
    const directions = [_]struct { x: i8, y: i8 }{
        .{ .x = -1, .y = 1 },
        .{ .x = 1, .y = 1 },
        .{ .x = -1, .y = -1 },
        .{ .x = 1, .y = -1 },
    };

    var result: u64 = 0;

    for (&directions) |*dir| {
        inner: for (1..8) |i| {
            const target = from.rel(@as(i8, @intCast(i)) * dir.x, @as(i8, @intCast(i)) * dir.y);
            if (target == null) {
                break :inner;
            }

            result |= target.?.mask();
            if (occupied & target.?.mask() != 0) break :inner;
        }
    }

    return result;
}

fn getAttacksRook(from: Square, occupied: u64) u64 {
    const directions = [_]struct { x: i8, y: i8 }{
        .{ .x = 1, .y = 0 },
        .{ .x = -1, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = 0, .y = -1 },
    };

    var result: u64 = 0;

    for (&directions) |*dir| {
        inner: for (1..8) |i| {
            const target = from.rel(@as(i8, @intCast(i)) * dir.x, @as(i8, @intCast(i)) * dir.y);
            if (target == null) {
                break :inner;
            }

            result |= target.?.mask();

            if (occupied & target.?.mask() != 0) break :inner;
        }
    }

    return result;
}

fn getAttacksQueen(from: Square, occupied: u64) u64 {
    return getAttacksBishop(from, occupied) | getAttacksRook(from, occupied);
}

fn getAttacksKing(from: Square) u64 {
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

    var result: u64 = 0;

    for (&directions) |*dir| {
        const target = from.rel(dir.x, dir.y);
        if (target != null) {
            result |= target.?.mask();
        }
    }

    return result;
}

fn getAttacks(piece: Piece, side: Color, from: Square, occupied: u64) u64 {
    return switch (piece) {
        Piece.Pawn => getAttacksPawn(from, side, occupied),
        Piece.Knight => getAttacksKnight(from),
        Piece.Bishop => getAttacksBishop(from, occupied),
        Piece.Rook => getAttacksRook(from, occupied),
        Piece.Queen => getAttacksQueen(from, occupied),
        Piece.King => getAttacksKing(from),
    };
}

fn getPawnPushes(square: Square, side: Color, occupied: u64) u64 {
    var result: u64 = 0;

    // push single
    var target = if (side == .White) square.rel(0, 1) else square.rel(0, -1);
    if (target == null or occupied & target.?.mask() != 0) return result;

    result |= target.?.mask();

    // push double
    if (side == .White and square.rank() != 1) return result;
    if (side == .Black and square.rank() != 6) return result;

    target = if (side == .White) square.rel(0, 2) else square.rel(0, -2);

    if (target != null and occupied & target.?.mask() == 0) {
        result |= target.?.mask();
    }

    return result;
}

fn getMoveSquares(piece: Piece, from: Square, pos: *const Position, occupied: u64) u64 {
    var squares = getAttacks(piece, pos.side_to_move, from, occupied);

    if (piece == .Pawn) {
        squares |= getPawnPushes(from, pos.side_to_move, occupied);

        // TODO: promotions
        // TODO: en passant
    }

    return squares;
}

fn findMovesFrom(
    piece: Piece,
    from: Square,
    pos: *const Position,
    out: *MoveList,
) void {
    const occupied = pos.occupied();
    const occupied_self = pos.occupiedBy(pos.side_to_move);
    const occupied_enemy = pos.occupiedBy(pos.side_enemy());

    var squares = getMoveSquares(piece, from, pos, occupied);

    while (squares != 0) : (squares &= squares - 1) {
        const idx = @ctz(squares);

        const target = Square.get(idx);
        const mask = target.mask();

        if (mask & occupied_self != 0) continue;

        var move_type: MoveType = undefined;
        move_type = if (mask & occupied_enemy == 0) .NORMAL else .CAPTURE;

        const move = Move{ .from = from, .to = target, .move_type = move_type };

        var pos_copy = pos.*;
        pos_copy.apply(move);

        if (!isInCheck(&pos_copy, pos_copy.side_to_move)) out.append_move(move);
    }
}

test "pawn_moves" {
    const pos = Position.start();
    const square = Square.at("e2");

    var move_list: MoveList = .{};

    findMovesFrom(.Pawn, square, &pos, &move_list);
    try t.expectEqual(2, move_list.len);

    try t.expectEqualStrings(&move_list.moves[0].str(), "e2e3");
    try t.expectEqualStrings(&move_list.moves[1].str(), "e2e4");
}

test "pawn_step_starting" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e2");

    var move_list = MoveList{};
    findMovesFrom(.Pawn, .at("e2"), &pos, &move_list);

    try t.expectEqual(2, move_list.len);

    try t.expect(move_list.has("e2e3", .NORMAL));
    try t.expect(move_list.has("e2e4", .NORMAL));
}

test "pawn_step_not_starting" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e3");

    var move_list = MoveList{};
    findMovesFrom(.Pawn, .at("e3"), &pos, &move_list);

    try t.expectEqual(1, move_list.len);

    try t.expect(move_list.has("e3e4", .NORMAL));
}

test "pawn_step_blocked" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e2");
    pos.put(.Black, .Pawn, "e3");

    var move_list = MoveList{};
    findMovesFrom(.Pawn, .at("e2"), &pos, &move_list);

    try t.expectEqual(0, move_list.len);
}

test "pawn_capture" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e2");
    pos.put(.Black, .Bishop, "d3");
    pos.put(.Black, .Bishop, "f3");

    var move_list = MoveList{};
    findMovesFrom(.Pawn, .at("e2"), &pos, &move_list);

    try t.expectEqual(4, move_list.len);

    try t.expect(move_list.has("e2e3", .NORMAL));
    try t.expect(move_list.has("e2e4", .NORMAL));
    try t.expect(move_list.has("e2d3", .CAPTURE));
    try t.expect(move_list.has("e2f3", .CAPTURE));
}

test "pawn_capture_2" {
    var pos = Position.init(.Black);
    pos.put(.Black, .Pawn, "d5");
    pos.put(.Black, .Bishop, "d4");
    pos.put(.White, .Bishop, "c6");
    pos.put(.White, .Queen, "c4");

    var move_list = MoveList{};
    findMovesFrom(.Pawn, .at("d5"), &pos, &move_list);

    try t.expectEqual(1, move_list.len);

    try t.expect(move_list.has("d5c4", .CAPTURE));
}

test "knight" {
    var pos = Position.init(.White);
    pos.put(.White, .Knight, "e4");

    var move_list = MoveList{};
    findMovesFrom(.Knight, .at("e4"), &pos, &move_list);

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
    pos.put(.White, .Knight, "g4");
    pos.put(.White, .Queen, "f2");
    pos.put(.White, .King, "h2");
    pos.put(.Black, .Bishop, "f6");

    var move_list = MoveList{};
    findMovesFrom(.Knight, .at("g4"), &pos, &move_list);

    try t.expectEqual(4, move_list.len);

    try t.expect(move_list.has("g4f6", .CAPTURE));
    try t.expect(move_list.has("g4h6", .NORMAL));
    try t.expect(move_list.has("g4e5", .NORMAL));
    try t.expect(move_list.has("g4e3", .NORMAL));
}

test "bishop" {
    var pos = Position.init(.White);
    pos.put(.White, .Bishop, "e4");

    var move_list = MoveList{};
    findMovesFrom(.Bishop, .at("e4"), &pos, &move_list);

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
    pos.put(.White, .Bishop, "g2");

    pos.put(.Black, .Knight, "f3");
    pos.put(.White, .Rook, "h1");

    var move_list = MoveList{};
    findMovesFrom(.Bishop, .at("g2"), &pos, &move_list);

    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("g2h3", .NORMAL));
    try t.expect(move_list.has("g2f1", .NORMAL));
    try t.expect(move_list.has("g2f3", .CAPTURE));
}

test "rook" {
    var pos = Position.init(.White);
    pos.put(.White, .Rook, "e4");

    var move_list = MoveList{};
    findMovesFrom(.Rook, .at("e4"), &pos, &move_list);

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
    pos.put(.White, .Rook, "g2");

    pos.put(.Black, .Knight, "g3");
    pos.put(.White, .Pawn, "f2");

    var move_list = MoveList{};
    findMovesFrom(.Rook, .at("g2"), &pos, &move_list);

    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("g2g3", .CAPTURE));
    try t.expect(move_list.has("g2h2", .NORMAL));
    try t.expect(move_list.has("g2g1", .NORMAL));
}

test "queen" {
    var pos = Position.init(.White);
    pos.put(.White, .Queen, "d1");

    pos.put(.White, .Pawn, "d3");
    pos.put(.Black, .Pawn, "c2");
    pos.put(.White, .Bishop, "c1");
    pos.put(.White, .King, "e1");

    var move_list = MoveList{};
    findMovesFrom(.Queen, .at("d1"), &pos, &move_list);

    try t.expectEqual(6, move_list.len);
}

test "king" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "e4");

    var move_list = MoveList{};
    findMovesFrom(.King, .at("e4"), &pos, &move_list);

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
    pos.put(.White, .King, "e1");

    pos.put(.White, .Queen, "d1");
    pos.put(.White, .Pawn, "e2");

    pos.put(.Black, .Pawn, "d2");

    var move_list = MoveList{};
    findMovesFrom(.King, .at("e1"), &pos, &move_list);

    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("e1f1", .NORMAL));
    try t.expect(move_list.has("e1f2", .NORMAL));
    try t.expect(move_list.has("e1d2", .CAPTURE));
}

fn findAllMoves(pos: *const Position, out: *MoveList) void {
    for (std.enums.values(Piece)) |piece| {
        var placements = pos.pieces[pos.side_to_move.idx()][piece.idx()];

        while (placements != 0) {
            const idx = @ctz(placements);

            findMovesFrom(piece, .get(idx), pos, out);
            placements &= placements - 1;
        }
    }
}

test "starting_moves" {
    var position = Position.start();

    var move_list: MoveList = .{};

    findAllMoves(&position, &move_list);
    try t.expectEqual(20, move_list.len);

    position.side_to_move = .Black;
    move_list = .{};

    findAllMoves(&position, &move_list);
    try t.expectEqual(20, move_list.len);
}

fn isAttackedBy(area_mask: u64, piece: Piece, attacker: Color, pos: *const Position, occupied: u64) bool {
    var pieces = pos.pieces[attacker.idx()][piece.idx()];
    while (pieces != 0) : (pieces &= pieces - 1) {
        const idx = @ctz(pieces);
        const attacks = getAttacks(piece, attacker, .get(idx), occupied);
        if (attacks & area_mask != 0) return true;
    }

    return false;
}

// is any square in the area mask attacked by any piece of the attacker side
fn isAttacked(area: u64, attacker: Color, pos: *const Position) bool {
    const occupied = pos.occupied();

    inline for (std.enums.values(Piece)) |piece| {
        if (isAttackedBy(area, piece, attacker, pos, occupied)) return true;
    }

    return false;
}

fn isInCheck(pos: *const Position, side: Color) bool {
    const king_mask = pos.pieces[side.idx()][Piece.King.idx()];

    return isAttacked(king_mask, side.opp(), pos);
}

test "is_check_no" {
    const pos = Position.start();

    try t.expect(!isInCheck(&pos, .White));
    try t.expect(!isInCheck(&pos, .Black));
}

test "is_check_pawn" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "d1");
    pos.put(.Black, .Pawn, "c2");

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, "e8");
    pos.put(.White, .Pawn, "d7");

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_knight" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "d1");
    pos.put(.Black, .Knight, "e3");

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, "h8");
    pos.put(.White, .Knight, "g6");

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_bishop" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "d1");
    pos.put(.Black, .Bishop, "a4");

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, "h8");
    pos.put(.White, .Bishop, "a1");

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_rook" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "d1");
    pos.put(.Black, .Rook, "d8");

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, "h8");
    pos.put(.White, .Rook, "h1");

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_queen" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "d1");
    pos.put(.Black, .Queen, "a4");

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, "h8");
    pos.put(.White, .Queen, "h1");

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_king" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "e4");
    pos.put(.Black, .King, "d4");

    try t.expect(isInCheck(&pos, .White));
    try t.expect(isInCheck(&pos, .Black));
}

test "skips_moves_exposing_king" {
    var position = Position.start();

    position.put(.Black, .Bishop, "b4");

    var move_list: MoveList = .{};

    findAllMoves(&position, &move_list);

    try t.expectEqual(17, move_list.len);

    try t.expect(!move_list.has("d2d3", .NORMAL));
    try t.expect(!move_list.has("d2d4", .NORMAL));
    try t.expect(!move_list.has("b2b4", .NORMAL));
}

pub fn run() void {
    const position = Position.start();
    position.print();

    var move_list: MoveList = .{};
    findAllMoves(&position, &move_list);

    std.debug.print("moves: {}\n", .{move_list.len});

    for (0..move_list.len) |i| {
        std.debug.print("{s}\n", .{move_list.moves[i].str()});
    }
}

fn print_bitmask(bitmask: u64) void {
    std.debug.print("-" ** 33, .{});
    std.debug.print("\n", .{});
    for (0..8) |r| {
        std.debug.print("|", .{});
        for (0..8) |f| {
            const idx = (7 - r) * 8 + f;
            const mask = @as(u64, 1) << @intCast(idx);
            const c: u8 = if (bitmask & mask == 0) ' ' else 'X';
            std.debug.print(" {c} |", .{c});
        }
        std.debug.print("\n", .{});
        std.debug.print("-" ** 33, .{});
        std.debug.print("\n", .{});
    }
}
