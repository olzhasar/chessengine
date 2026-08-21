pub const Position = @import("Position.zig");
pub const GameError = Position.PositionError;

pub const Game = @import("Game.zig");
pub const GameMode = Game.GameMode;

const types = @import("types.zig");

pub const Move = types.Move;
pub const Color = types.Color;

test {
    _ = @import("Game.zig");
    _ = @import("Position.zig");
    _ = @import("attacks.zig");
    _ = @import("movegen.zig");
    _ = @import("perft.zig");
    _ = @import("search.zig");
    _ = @import("types.zig");
    _ = @import("zobrist.zig");
}
