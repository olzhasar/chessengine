const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

const board = @import("board.zig");
const movegen = @import("movegen.zig");

pub const Game = struct {
    position: board.Position,

    pub fn new() Game {
        return .{
            .position = .start(),
        };
    }

    pub fn list_moves(self: *Game) void {
        var move_list: movegen.MoveList = .{};
        movegen.findAll(&self.position, &move_list);

        for (0..move_list.len) |i| {
            std.debug.print("{s}\n", .{move_list.moves[i].str()});
        }
    }

    pub fn draw_board(self: *Game) void {
        self.position.print();
    }

    pub fn go(self: *Game, input: []const u8) !void {
        if (input.len != 4) return error.InvalidMove;

        try self.position.go(input);
    }
};
