const std = @import("std");

const lib = @import("chessengine");

const ENGINE_DEPTH = 5;

const GameMode = enum {
    ENGINE_VS_ENGINE,
    HUMAN_VS_ENGINE,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const stdin = std.Io.File.stdin();

    var buffer: [1024]u8 = undefined;
    var reader = stdin.reader(io, &buffer);

    var game = lib.Game.new(init.gpa);
    defer game.deinit();

    const game_mode = promptGameMode(&reader.interface);
    var player_color: lib.Color = undefined;

    if (game_mode == .HUMAN_VS_ENGINE) {
        player_color = promptColor(&reader.interface);
    }

    std.debug.print("You play: {}\n", .{player_color});

    while (true) {
        game.drawBoard();

        switch (game.status()) {
            .CHECKMATE => {
                std.debug.print("{} wins by checkmate!\n", .{game.position.sideEnemy()});
                break;
            },
            .STALEMATE => {
                std.debug.print("The game ended in stalemate!\n", .{});
                break;
            },
            .DRAW_BY_REPETITION => {
                std.debug.print("Draw by repetition!\n", .{});
                break;
            },
            .DRAW_50_RULE => {
                std.debug.print("Draw by the 50-move rule!\n", .{});
                break;
            },
            .ONGOING => {},
        }

        if (game_mode == .HUMAN_VS_ENGINE and game.sideToMove() == player_color) {
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
            const side = game.sideToMove();

            std.debug.print("{s} is thinking...\n", .{@tagName(side)});
            const move = try game.goEngine(ENGINE_DEPTH);
            std.debug.print("{s} played: {s}\n", .{ @tagName(side), move.str() });
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

fn promptGameMode(reader: *std.Io.Reader) GameMode {
    std.debug.print("Select game mode:\n1 - Human vs Engine\n2 - Engine vs Engine\n", .{});

    while (true) {
        const input = reader.takeDelimiter('\n') catch continue;
        if (input == null or input.?.len != 1) continue;
        switch (input.?[0]) {
            '1' => return .HUMAN_VS_ENGINE,
            '2' => return .ENGINE_VS_ENGINE,
            else => {},
        }
    }
}
