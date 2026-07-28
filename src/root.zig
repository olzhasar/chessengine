const std = @import("std");

const Color = enum(u1) {
    White,
    Black,
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
};

const Position = struct {
    // [color][piece type] bitmasks. LSB (bit 0) - a1, MSB (bit 63) - h8.
    pieces: [2][6]u64,

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
