const std = @import("std");

const lib = @import("chessengine");

const ENGINE_DEPTH = 5;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const stdin = std.Io.File.stdin();

    var buffer: [1024]u8 = undefined;
    var reader = stdin.reader(io, &buffer);

    var game = lib.Game.new();

    const playerColor = promptColor(&reader.interface);

    std.debug.print("You play: {}\n", .{playerColor});

    while (true) {
        game.drawBoard();

        switch (game.status()) {
            .CHECKMATE => {
                std.debug.print("{} wins by checkmate!", .{game.position.side_to_move});
                break;
            },
            .STALEMATE => {
                std.debug.print("The game ended in stalemate!", .{});
                break;
            },
            .ONGOING => {},
        }

        if (game.sideToMove() == playerColor) {
            std.debug.print("enter your move: ", .{});
            while (true) {
                const input = try reader.interface.takeDelimiter('\n');
                if (input == null) continue;

                game.go(input.?) catch |err| {
                    switch (err) {
                        lib.GameError.IllegalMove => std.debug.print("Illegal move: {s}\n", .{input.?}),
                        lib.GameError.InvalidMove => std.debug.print("Invalid input. Use long algebraic notation, e.g.: e2e4\n", .{}),
                        else => unreachable,
                    }
                    continue;
                };
                break;
            }
        } else {
            std.debug.print("engine is thinking...\n", .{});
            const move = game.goEngine(ENGINE_DEPTH);
            std.debug.print("engine played: {s}\n", .{move.str()});
        }
    }
}

fn promptColor(reader: *std.Io.Reader) lib.Color {
    std.debug.print("Input your side: w - White, b - Black\n", .{});

    while (true) {
        const input = reader.takeDelimiter('\n') catch continue;
        if (input == null or input.?.len != 1) continue;
        switch (input.?[0]) {
            'w' => return .White,
            'b' => return .Black,
            else => {},
        }
    }
}
