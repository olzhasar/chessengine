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
        assert(idx > 0 and idx < 64);
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

    fn symbol(self: Piece) u8 {
        return switch (self) {
            Piece.Pawn => 'P',
            Piece.Knight => 'N',
            Piece.Bishop => 'B',
            Piece.Rook => 'R',
            Piece.Queen => 'Q',
            Piece.King => 'K',
        };
    }

    fn idx(self: Piece) usize {
        return @intFromEnum(self);
    }
};

const Move = struct {
    from: Square,
    to: Square,

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

    fn append(self: *MoveList, from: Square, to: Square) void {
        self.moves[self.len] = .{ .from = from, .to = to };
        self.len += 1;
    }

    fn has(self: *MoveList, str: []const u8) bool {
        for (&self.moves) |*move| {
            if (std.mem.eql(u8, &move.str(), str)) return true;
        }
        return false;
    }

    fn print(self: *const MoveList) void {
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
        var piece_mask: [64]u8 = @splat(32);
        var color_mask: [64]u8 = @splat(32);

        inline for (std.enums.values(Color), 0..) |col, ci| {
            inline for (std.enums.values(Piece), 0..) |piece, pi| {
                const bitmask = self.pieces[ci][pi];

                for (0..64) |i| {
                    if ((bitmask >> @truncate(i)) & 1 == 1) {
                        piece_mask[i] = piece.symbol();
                        color_mask[i] = col.symbol();
                    }
                }
            }
        }

        std.debug.print("-" ** 41, .{});
        std.debug.print("\n", .{});
        for (0..8) |r| {
            std.debug.print("|", .{});
            for (0..8) |f| {
                const idx = (7 - r) * 8 + f;
                std.debug.print(" {c}{c} |", .{ color_mask[idx], piece_mask[idx] });
            }
            std.debug.print("\n", .{});
            std.debug.print("-" ** 41, .{});
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

fn generateMoves(pos: *const Position, out: *MoveList) void {
    var idx: u8 = 0;
    while (idx < 64) : (idx += 1) {
        if ((@as(u64, 1) << @intCast(idx)) & pos.pieces[pos.side_to_move.idx()][Piece.Pawn.idx()] != 0) {
            _ = generatePawnMoves(.get(idx), pos, out);
        }
    }
}

fn generatePawnMoves(square: Square, pos: *const Position, out: *MoveList) u8 {
    var n: u8 = 0;

    const occupied = pos.occupied();
    const occupied_enemy = pos.occupiedBy(pos.side_enemy());

    // step one
    {
        const step: i8 = if (pos.side_to_move == .White) 1 else -1;
        const target = square.rel(0, step);

        if (target != null and occupied & target.?.mask() == 0) {
            out.append(.get(square.idx), .get(target.?.idx));
            n += 1;
        }
    }

    // step two
    blk: {
        if (pos.side_to_move == .White and square.rank() != 1) break :blk;
        if (pos.side_to_move == .Black and square.rank() != 6) break :blk;

        const next = if (pos.side_to_move == .White) square.rel(0, 1) else square.rel(0, -1);
        if (occupied & next.?.mask() != 0) break :blk;

        const target = if (pos.side_to_move == .White) square.rel(0, 2) else square.rel(0, -2);

        if (target != null and occupied & target.?.mask() == 0) {
            out.append(.get(square.idx), .get(target.?.idx));
            n += 1;
        }
    }

    // capture left
    {
        const target = if (pos.side_to_move == .White) square.rel(-1, 1) else square.rel(1, -1);
        if (target != null and occupied_enemy & target.?.mask() != 0) {
            out.append(.get(square.idx), .get(target.?.idx));
            n += 1;
        }
    }
    // capture right
    {
        const target = if (pos.side_to_move == .White) square.rel(1, 1) else square.rel(-1, -1);
        if (target != null and occupied_enemy & target.?.mask() != 0) {
            out.append(.get(square.idx), .get(target.?.idx));
            n += 1;
        }
    }

    // TODO: promotions

    return n;
}

fn generateKnightMoves(square: Square, pos: *const Position, out: *MoveList) u8 {
    var n: u8 = 0;
    const occupied = pos.occupied();
    const occupied_enemy = pos.occupiedBy(pos.side_enemy());

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

    for (&directions) |dir| {
        const target = square.rel(dir.x, dir.y);
        if (target == null) continue;

        if (target.?.mask() & occupied == 0 or target.?.mask() & occupied_enemy != 0) {
            out.append(square, target.?);
            n += 1;
        }
    }

    return n;
}

fn generateBishopMoves(from: Square, pos: *const Position, out: *MoveList) u8 {
    var n: u8 = 0;

    const occupied = pos.occupied();
    const occupied_enemy = pos.occupiedBy(pos.side_enemy());

    const directions = [_]struct { x: i8, y: i8 }{
        .{ .x = -1, .y = 1 },
        .{ .x = 1, .y = 1 },
        .{ .x = -1, .y = -1 },
        .{ .x = 1, .y = -1 },
    };

    for (&directions) |*dir| {
        inner: for (1..8) |i| {
            const target = from.rel(@as(i8, @intCast(i)) * dir.x, @as(i8, @intCast(i)) * dir.y);
            if (target == null) {
                break :inner;
            }

            if (target.?.mask() & occupied == 0) {
                out.append(from, target.?);
                n += 1;
            } else {
                if (target.?.mask() & occupied_enemy != 0) {
                    out.append(from, target.?);
                    n += 1;
                }
                break :inner;
            }
        }
    }

    return n;
}

fn generateRookMoves(from: Square, pos: *const Position, out: *MoveList) u8 {
    var n: u8 = 0;

    const directions = [_]struct { x: i8, y: i8 }{
        .{ .x = 1, .y = 0 },
        .{ .x = -1, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = 0, .y = -1 },
    };

    const occupied = pos.occupied();
    const occupied_enemy = pos.occupiedBy(pos.side_enemy());

    for (&directions) |*dir| {
        inner: for (1..8) |i| {
            const target = from.rel(@as(i8, @intCast(i)) * dir.x, @as(i8, @intCast(i)) * dir.y);
            if (target == null) {
                break :inner;
            }

            if (target.?.mask() & occupied == 0) {
                out.append(from, target.?);
                n += 1;
            } else {
                if (target.?.mask() & occupied_enemy != 0) {
                    out.append(from, target.?);
                    n += 1;
                }
                break :inner;
            }
        }
    }

    return n;
}

fn generateQueenMoves(from: Square, pos: *const Position, out: *MoveList) u8 {
    return generateRookMoves(from, pos, out) + generateBishopMoves(from, pos, out);
}

fn generateKingMoves(from: Square, pos: *const Position, out: *MoveList) u8 {
    var n: u8 = 0;

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

    const occupied = pos.occupied();
    const occupied_enemy = pos.occupiedBy(pos.side_enemy());

    for (&directions) |*dir| {
        const target = from.rel(dir.x, dir.y);
        if (target == null) {
            continue;
        }

        if (target.?.mask() & occupied == 0 or target.?.mask() & occupied_enemy != 0) {
            out.append(from, target.?);
            n += 1;
        }
    }

    return n;
}

test "pawn_moves" {
    const pos = Position.start();
    const square = Square.at("e2");

    var move_list: MoveList = .{};

    const n = generatePawnMoves(square, &pos, &move_list);
    try t.expectEqual(2, n);
    try t.expectEqual(2, move_list.len);

    try t.expectEqualStrings(&move_list.moves[0].str(), "e2e3");
    try t.expectEqualStrings(&move_list.moves[1].str(), "e2e4");
}

test "pawn_step_starting" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e2");

    var move_list = MoveList{};
    const n = generatePawnMoves(.at("e2"), &pos, &move_list);

    try t.expectEqual(2, n);
    try t.expectEqual(2, move_list.len);

    try t.expect(move_list.has("e2e3"));
    try t.expect(move_list.has("e2e4"));
}

test "pawn_step_not_starting" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e3");

    var move_list = MoveList{};
    const n = generatePawnMoves(.at("e3"), &pos, &move_list);

    try t.expectEqual(1, n);

    try t.expect(move_list.has("e3e4"));
}

test "pawn_step_blocked" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e2");
    pos.put(.Black, .Pawn, "e3");

    var move_list = MoveList{};
    const n = generatePawnMoves(.at("e2"), &pos, &move_list);

    try t.expectEqual(0, n);
}

test "pawn_capture" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e2");
    pos.put(.Black, .Bishop, "d3");
    pos.put(.Black, .Bishop, "f3");

    var move_list = MoveList{};
    const n = generatePawnMoves(.at("e2"), &pos, &move_list);

    try t.expectEqual(4, n);

    try t.expect(move_list.has("e2e3"));
    try t.expect(move_list.has("e2e4"));
    try t.expect(move_list.has("e2d3"));
    try t.expect(move_list.has("e2f3"));
}

test "knight" {
    var pos = Position.init(.White);
    pos.put(.White, .Knight, "e4");

    var move_list = MoveList{};
    const n = generateKnightMoves(.at("e4"), &pos, &move_list);

    try t.expectEqual(8, n);
    try t.expectEqual(8, move_list.len);

    try t.expect(move_list.has("e4d6"));
    try t.expect(move_list.has("e4f6"));
    try t.expect(move_list.has("e4c5"));
    try t.expect(move_list.has("e4g5"));
    try t.expect(move_list.has("e4c5"));
    try t.expect(move_list.has("e4g5"));
    try t.expect(move_list.has("e4c3"));
    try t.expect(move_list.has("e4g3"));
    try t.expect(move_list.has("e4d2"));
    try t.expect(move_list.has("e4f2"));
}

test "knight_2" {
    var pos = Position.init(.White);
    pos.put(.White, .Knight, "g4");
    pos.put(.White, .Queen, "f2");
    pos.put(.White, .King, "h2");
    pos.put(.Black, .Bishop, "f6");

    var move_list = MoveList{};
    const n = generateKnightMoves(.at("g4"), &pos, &move_list);

    try t.expectEqual(4, n);
    try t.expectEqual(4, move_list.len);

    try t.expect(move_list.has("g4f6"));
    try t.expect(move_list.has("g4h6"));
    try t.expect(move_list.has("g4e5"));
    try t.expect(move_list.has("g4e3"));
}

test "bishop" {
    var pos = Position.init(.White);
    pos.put(.White, .Bishop, "e4");

    var move_list = MoveList{};
    const n = generateBishopMoves(.at("e4"), &pos, &move_list);

    try t.expectEqual(13, n);
    try t.expectEqual(13, move_list.len);

    try t.expect(move_list.has("e4f5"));
    try t.expect(move_list.has("e4g6"));
    try t.expect(move_list.has("e4h7"));
    try t.expect(move_list.has("e4f3"));
    try t.expect(move_list.has("e4g2"));
    try t.expect(move_list.has("e4h1"));
    try t.expect(move_list.has("e4d5"));
    try t.expect(move_list.has("e4c6"));
    try t.expect(move_list.has("e4b7"));
    try t.expect(move_list.has("e4a8"));
    try t.expect(move_list.has("e4d3"));
    try t.expect(move_list.has("e4c2"));
    try t.expect(move_list.has("e4b1"));
}

test "bishop_2" {
    var pos = Position.init(.White);
    pos.put(.White, .Bishop, "g2");

    pos.put(.Black, .Knight, "f3");
    pos.put(.White, .Rook, "h1");

    var move_list = MoveList{};
    const n = generateBishopMoves(.at("g2"), &pos, &move_list);

    try t.expectEqual(3, n);
    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("g2h3"));
    try t.expect(move_list.has("g2f1"));
    try t.expect(move_list.has("g2f3"));
}

test "rook" {
    var pos = Position.init(.White);
    pos.put(.White, .Rook, "e4");

    var move_list = MoveList{};
    const n = generateRookMoves(.at("e4"), &pos, &move_list);

    try t.expectEqual(14, n);
    try t.expectEqual(14, move_list.len);

    try t.expect(move_list.has("e4e5"));
    try t.expect(move_list.has("e4e6"));
    try t.expect(move_list.has("e4e7"));
    try t.expect(move_list.has("e4e8"));
    try t.expect(move_list.has("e4e3"));
    try t.expect(move_list.has("e4e2"));
    try t.expect(move_list.has("e4e1"));
    try t.expect(move_list.has("e4d4"));
    try t.expect(move_list.has("e4c4"));
    try t.expect(move_list.has("e4b4"));
    try t.expect(move_list.has("e4a4"));
    try t.expect(move_list.has("e4f4"));
    try t.expect(move_list.has("e4g4"));
    try t.expect(move_list.has("e4h4"));
}

test "rook_2" {
    var pos = Position.init(.White);
    pos.put(.White, .Rook, "g2");

    pos.put(.Black, .Knight, "g3");
    pos.put(.White, .Pawn, "f2");

    var move_list = MoveList{};
    const n = generateRookMoves(.at("g2"), &pos, &move_list);

    try t.expectEqual(3, n);
    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("g2g3"));
    try t.expect(move_list.has("g2h2"));
    try t.expect(move_list.has("g2g1"));
}

test "queen" {
    var pos = Position.init(.White);
    pos.put(.White, .Queen, "d1");

    pos.put(.White, .Pawn, "d3");
    pos.put(.Black, .Pawn, "c2");
    pos.put(.White, .Bishop, "c1");
    pos.put(.White, .King, "e1");

    var move_list = MoveList{};
    const n = generateQueenMoves(.at("d1"), &pos, &move_list);

    try t.expectEqual(6, n);
    try t.expectEqual(6, move_list.len);
}

test "king" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "e4");

    var move_list = MoveList{};
    const n = generateKingMoves(.at("e4"), &pos, &move_list);

    try t.expectEqual(8, n);
    try t.expectEqual(8, move_list.len);

    try t.expect(move_list.has("e4e5"));
    try t.expect(move_list.has("e4d5"));
    try t.expect(move_list.has("e4f5"));
    try t.expect(move_list.has("e4d4"));
    try t.expect(move_list.has("e4f4"));
    try t.expect(move_list.has("e4d3"));
    try t.expect(move_list.has("e4e3"));
    try t.expect(move_list.has("e4f3"));
}

test "king_2" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "e1");

    pos.put(.White, .Queen, "d1");
    pos.put(.White, .Pawn, "e2");

    pos.put(.Black, .Pawn, "d2");

    var move_list = MoveList{};
    const n = generateKingMoves(.at("e1"), &pos, &move_list);

    try t.expectEqual(3, n);
    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("e1d2"));
    try t.expect(move_list.has("e1f1"));
    try t.expect(move_list.has("e1f2"));
}

pub fn run() void {
    const position = Position.start();
    position.print();

    var move_list: MoveList = .{};
    generateMoves(&position, &move_list);

    std.debug.print("moves: {}\n", .{move_list.len});

    for (0..move_list.len) |i| {
        std.debug.print("{s}\n", .{move_list.moves[i].str()});
    }
}
