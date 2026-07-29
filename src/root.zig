const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

// [color][piece type] bitmasks. LSB (bit 0) - a1, MSB (bit 63) - h8.
const Bitboard = [2][6]u64;

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

const Color = enum(u1) {
    White,
    Black,

    fn idx(self: Color) usize {
        return @intFromEnum(self);
    }
};

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
};

const Position = struct {
    pieces: Bitboard,
    side_to_move: Color,

    fn empty() Position {
        return .{
            .pieces = .{
                @splat(0),
                @splat(0),
            },
        };
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
        var buf: [8][8]u8 = undefined;
        for (0..64) |i| {
            buf[i / 8][i % 8] = 32;
        }

        inline for (0..2) |ci| {
            inline for (std.enums.values(Piece), 0..) |piece, pi| {
                const bitmask = self.pieces[ci][pi];

                for (0..64) |i| {
                    if ((bitmask >> @truncate(i)) & 1 == 1) {
                        buf[i / 8][i % 8] = piece.symbol();
                    }
                }
            }
        }

        std.debug.print("-" ** 33, .{});
        std.debug.print("\n", .{});
        for (0..8) |r| {
            std.debug.print("|", .{});
            for (0..8) |c| {
                std.debug.print(" {c} |", .{buf[r][c]});
            }
            std.debug.print("\n", .{});
            std.debug.print("-" ** 33, .{});
            std.debug.print("\n", .{});
        }
    }

    fn occupied(self: *const Position) u64 {
        var result: u64 = 0;
        inline for (0..2) |ci| {
            inline for (std.enums.values(Piece)) |piece| {
                result |= self.pieces[ci][piece.idx()];
            }
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
    assert(square.mask() & pos.pieces[pos.side_to_move.idx()][Piece.Pawn.idx()] != 0);
    var n: u8 = 0;

    const occupied = pos.occupied();

    switch (pos.side_to_move) {
        .White => {
            assert(square.rank() < 7);
            // regular step
            const target = square.rel(0, 1);
            if (target != null and occupied & target.?.mask() == 0) {
                out.append(.get(square.idx), .get(target.?.idx));
                n += 1;
            }
        },
        .Black => {
            assert(square.rank() > 0);
        },
    }

    return n;
}

test "pawn_moves" {
    const pos = Position.start();
    const square = Square.at("e2");

    var move_list: MoveList = .{};

    const n = generatePawnMoves(square, &pos, &move_list);
    try t.expect(n > 0);
    try t.expect(move_list.len > 0);

    const first = move_list.moves[0];

    try t.expectEqualStrings(&first.from.str(), "e2");
    try t.expectEqualStrings(&first.to.str(), "e3");

    for (0..move_list.len) |i| {
        std.debug.print("{s}\n", .{move_list.moves[i].str()});
    }
}

pub fn run() void {
    const position = Position.start();
    // position.print();
    //
    var move_list: MoveList = .{};
    generateMoves(&position, &move_list);

    std.debug.print("moves: {}\n", .{move_list.len});

    for (0..move_list.len) |i| {
        std.debug.print("{s}\n", .{move_list.moves[i].str()});
    }
}
