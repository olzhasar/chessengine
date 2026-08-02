const std = @import("std");

const engine = @import("chessengine");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const stdin = std.Io.File.stdin();

    var buffer: [1024]u8 = undefined;
    var reader = stdin.reader(io, &buffer);

    var game = engine.Game.new();

    while (true) {
        game.draw_board();
        game.list_moves();

        const input = try reader.interface.takeDelimiter('\n');

        try game.go(input.?);
    }
}
