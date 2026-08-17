const std = @import("std");

const DEFAULT_ENGINE_DEPTH = 5;

const engine = @import("chessengine");

pub fn play(io: std.Io, alloc: std.mem.Allocator) !void {
    const stdin = std.Io.File.stdin();

    var buffer: [1024]u8 = undefined;
    var reader = stdin.reader(io, &buffer);

    const game_mode = promptGameMode(&reader.interface);
    var player_color: engine.Color = undefined;

    if (game_mode == .HUMAN_VS_ENGINE) {
        player_color = promptColor(&reader.interface);
        std.debug.print("You play: {}\n", .{player_color});
    }

    const engine_depth = promptEngineDepth(&reader.interface) orelse DEFAULT_ENGINE_DEPTH;

    var game = engine.Game.new(alloc);
    defer game.deinit();

    var uci_buf: [5]u8 = undefined;

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
                        engine.GameError.IllegalMove => std.debug.print("Illegal move: {s}\n", .{input.?}),
                        engine.GameError.InvalidMove => std.debug.print("Invalid input. Use long algebraic notation, e.g.: e2e4\n", .{}),
                        else => unreachable,
                    }
                    continue;
                };
                break;
            }
        } else {
            const side = game.sideToMove();

            std.debug.print("{s} is thinking...\n", .{@tagName(side)});
            const move = try game.goEngine(engine_depth);
            std.debug.print("{s} played: {s}\n", .{ @tagName(side), move.uci(&uci_buf) });
        }
    }
}

fn promptColor(reader: *std.Io.Reader) engine.Color {
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

fn promptGameMode(reader: *std.Io.Reader) engine.GameMode {
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

fn promptEngineDepth(reader: *std.Io.Reader) ?u8 {
    std.debug.print("Input engine depth (default if blank: {}):", .{DEFAULT_ENGINE_DEPTH});

    while (true) {
        const input = reader.takeDelimiter('\n') catch continue;
        if (input == null or input.?.len != 1) return null;

        if (std.fmt.parseInt(u8, input.?, 10)) |val| {
            return val;
        } else |_| {
            return null;
        }
    }
}
