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

    fn file(self: Square) u3 {
        return @truncate(self.idx % 8);
    }

    fn rank(self: Square) u3 {
        return @truncate(self.idx / 8);
    }

    fn str(self: Square) [2]u8 {
        return .{
            @as(u8, 'a') + self.file(),
            @as(u8, '1') + self.rank(),
        };
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
};

const MoveList = struct {
    moves: [255]Move = undefined,
    len: u8 = 0,

    fn append(self: *MoveList, from: Square, to: Square) void {
        self.moves[self.len + 1] = .{ .from = from, .to = to };
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
};

pub fn run() void {
    const position = Position.start();
    position.print();
}

fn generateMoves(pos: Position, out: *MoveList) void {
    _ = pos;
    _ = out;
}

fn generatePawnMoves(square: Square, pos: Position, out: *MoveList) u8 {
    assert(square.mask() & pos.pieces[pos.side_to_move.idx()][Piece.Pawn.idx()] != 0);

    _ = square.file();
    _ = out;
    return 0;
}

test "pawn_moves" {
    const pos = Position.start();
    const square = Square.at("e2");

    var move_list: MoveList = .{};

    _ = generatePawnMoves(square, pos, &move_list);
}
