const std = @import("std");

const Color = enum {
    White,
    Black,
};

const Piece = enum {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,
};

const Position = struct {
    // [color][piece] bitmasks. Bit 0 - a1, bit 63 is h8.
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
        _ = self;
        std.debug.print("Position\n", .{});
    }
};

pub fn run() void {
    const position = Position.start();
    position.print();
}
