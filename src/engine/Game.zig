const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

const board = @import("board.zig");
const movegen = @import("movegen.zig");

const Move = board.Move;
const Color = board.Color;
const GameError = board.GameError;

pub const GameMode = enum {
    ENGINE_VS_ENGINE,
    HUMAN_VS_ENGINE,
};

pub const GameStatus = enum {
    CHECKMATE,
    STALEMATE,
    ONGOING,
    DRAW_BY_REPETITION,
    DRAW_50_RULE,
};

const Game = @This();

position: board.Position,
table: movegen.TranspositionTable,

history: [101]u64 = @splat(0),
history_len: u8 = 0,

pub fn new(alloc: std.mem.Allocator) Game {
    var game = Game{
        .position = .start(),
        .table = .init(alloc),
    };

    game.saveHash();

    return game;
}

pub fn deinit(self: *Game) void {
    self.table.deinit();
}

pub fn status(self: *Game) GameStatus {
    if (self.position.half_move_counter >= 100) return .DRAW_50_RULE;
    if (self.isRepetition(3)) return .DRAW_BY_REPETITION;

    var move_list = movegen.MoveList{};
    movegen.findAll(&self.position, &move_list);

    if (move_list.len == 0) {
        if (movegen.isInCheck(&self.position, self.position.side_to_move)) return .CHECKMATE;
        return .STALEMATE;
    }

    return .ONGOING;
}

fn isRepetition(self: *const Game, limit: u8) bool {
    assert(limit >= 1);

    var counter: u8 = 0;

    var i: usize = 2;
    while (i < self.history_len) : (i += 2) {
        if (self.history[self.history_len - 1] == self.history[self.history_len - 1 - i]) counter += 1;
        if (counter >= (limit - 1)) return true;
    }

    return false;
}

fn printLegalMoves(self: *Game) void {
    var move_list: movegen.MoveList = .{};
    movegen.findAll(&self.position, &move_list);

    for (0..move_list.len) |i| {
        std.debug.print("{s}\n", .{move_list.moves[i].str()});
    }
}

pub fn drawBoard(self: *Game) void {
    self.position.print();
}

fn makeMove(self: *Game, move: Move) void {
    self.position.apply(move);
    if (move.piece == .Pawn or move.move_type != .NORMAL) {
        self.history_len = 0;
    }
    self.saveHash();
}

fn saveHash(self: *Game) void {
    self.history[self.history_len] = self.position.hash;
    self.history_len += 1;
}

pub fn sideToMove(self: *Game) Color {
    return self.position.side_to_move;
}

pub fn go(self: *Game, input: []const u8) !void {
    const move = try self.position.parseMove(input);
    if (!movegen.isMoveLegal(&self.position, move)) return GameError.IllegalMove;

    self.makeMove(move);
}

pub fn goEngine(self: *Game, depth: u8) !Move {
    const move = try movegen.findBestMove(&self.position, depth, &self.table);
    if (move == null) unreachable;
    self.makeMove(move.?);

    return move.?;
}

test "threefold repetition" {
    var game = Game.new(t.allocator);
    const moves = [_][]const u8{ "g1f3", "g8f6", "f3g1", "f6g8" };

    for (moves) |m| try game.go(m);
    try t.expect(!game.isRepetition(3));

    for (moves) |m| try game.go(m);
    try t.expect(game.isRepetition(3));
}
