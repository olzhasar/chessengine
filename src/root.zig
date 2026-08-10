const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

const board = @import("board.zig");
const movegen = @import("movegen.zig");

pub const Move = board.Move;
pub const Color = board.Color;
pub const GameError = board.GameError;

pub const Game = struct {
    position: board.Position,

    const GameStatus = enum {
        CHECKMATE,
        STALEMATE,
        ONGOING,
        DRAW_BY_REPETITION,
        DRAW_50_RULE,
    };

    pub fn new() Game {
        return .{
            .position = .start(),
        };
    }

    pub fn status(self: *Game) GameStatus {
        if (self.position.half_move_counter >= 100) return .DRAW_50_RULE;
        if (self.position.isRepetition(3)) return .DRAW_BY_REPETITION;

        var move_list = movegen.MoveList{};
        movegen.findAll(&self.position, &move_list);

        if (move_list.len == 0) {
            if (movegen.isInCheck(&self.position, self.position.side_to_move)) return .CHECKMATE;
            return .STALEMATE;
        }

        return .ONGOING;
    }

    pub fn printLegalMoves(self: *Game) void {
        var move_list: movegen.MoveList = .{};
        movegen.findAll(&self.position, &move_list);

        for (0..move_list.len) |i| {
            std.debug.print("{s}\n", .{move_list.moves[i].str()});
        }
    }

    pub fn drawBoard(self: *Game) void {
        self.position.print();
    }

    pub fn go(self: *Game, input: []const u8) !void {
        const move = try self.position.parseMove(input);
        if (!movegen.isMoveLegal(&self.position, move)) return GameError.IllegalMove;

        self.position.apply(move);
    }

    pub fn sideToMove(self: *Game) Color {
        return self.position.side_to_move;
    }

    pub fn goEngine(self: *Game, depth: u8) Move {
        const move = movegen.findBestMove(&self.position, depth);
        if (move == null) unreachable;
        self.position.apply(move.?);

        return move.?;
    }
};
