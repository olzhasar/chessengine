const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const t = std.testing;

const engine = @import("chessengine");

const UciError = error{
    InvalidPositionCommand,
    InvalidDepth,
};

const DEFAULT_SEARCH_DEPTH = 3;
const MAX_SEARCH_DEPTH = 7;

const Command = enum {
    uci,
    isready,
    quit,
    ucinewgame,
    position,
    go,
    setoption,
    stop,
};

const Instruction = struct {
    cmd: Command,
    args: []const u8,
};

fn writeMessages(output: *Io.Writer, messages: []const []const u8) !void {
    for (messages) |msg| {
        try output.print("{s}\n", .{msg});
    }

    try output.flush();
}

fn handleInstruction(instr: Instruction, game: *engine.Game, output: *Io.Writer) !void {
    switch (instr.cmd) {
        .quit => unreachable,
        .uci => {
            try writeMessages(output, &.{ "id name chessengine", "id author olzhasar", "uciok" });
        },
        .isready => {
            try writeMessages(output, &.{"readyok"});
        },
        .ucinewgame => game.setPosition(.start()),
        .position => try handlePosition(instr.args, game),
        .go => try handleGo(instr.args, game, output),
        .setoption, .stop => {}, // TODO
    }
}

fn handlePosition(args: []const u8, game: *engine.Game) !void {
    var tokens = std.mem.tokenizeAny(u8, args, " \t\r");
    const kind = tokens.next() orelse return UciError.InvalidPositionCommand;

    if (std.mem.eql(u8, kind, "fen")) {
        game.setPosition(try engine.Position.fromFEN(args[kind.len + 1 ..]));
        return;
    }

    if (!std.mem.eql(u8, kind, "startpos")) {
        return UciError.InvalidPositionCommand;
    }

    game.setPosition(.start());

    const moves = tokens.next() orelse return;
    if (!std.mem.eql(u8, moves, "moves")) return UciError.InvalidPositionCommand;

    while (tokens.next()) |move| {
        try game.go(move);
    }
}

fn handleGo(args: []const u8, game: *engine.Game, output: *Io.Writer) !void {
    // TODO ponder
    const depth = try parseGoDepth(args);
    const move = try game.findEngineMove(depth);

    if (move) |best_move| {
        var buffer: [5]u8 = undefined;
        try output.print("bestmove {s}\n", .{best_move.uci(&buffer)});
    } else {
        try output.writeAll("bestmove 0000\n");
    }
    try output.flush();
}

fn parseGoDepth(args: []const u8) !u8 {
    var tokens = std.mem.tokenizeAny(u8, args, " \t\r");
    while (tokens.next()) |token| {
        if (!std.mem.eql(u8, token, "depth")) continue;

        const value = tokens.next() orelse return UciError.InvalidDepth;
        const depth = std.fmt.parseInt(u8, value, 10) catch return UciError.InvalidDepth;
        if (depth == 0) return DEFAULT_SEARCH_DEPTH;
        return @min(depth, MAX_SEARCH_DEPTH);
    }

    return DEFAULT_SEARCH_DEPTH;
}

fn nextInstruction(reader: *Io.Reader) ?Instruction {
    while (true) {
        const raw_line = reader.takeDelimiter('\n') catch continue orelse continue;
        const line = std.mem.trim(u8, raw_line, " \t\r");

        const delim_idx = std.mem.indexOfAny(u8, line, " \t") orelse line.len;

        const cmd = std.meta.stringToEnum(Command, line[0..delim_idx]) orelse {
            std.debug.print("Unknown command: '{s}'\n", .{raw_line});
            continue;
        };

        return .{ .cmd = cmd, .args = std.mem.trim(u8, line[@min(delim_idx + 1, line.len)..], " \t") };
    }
}

pub fn run(init: std.process.Init) !void {
    const stdin = std.Io.File.stdin();

    // FIXME: this should allocate instead as move sequences can go quite deep
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = stdin.reader(init.io, &stdin_buffer);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);

    var game: engine.Game = engine.Game.new(init.gpa);
    defer game.deinit();

    while (nextInstruction(&stdin_reader.interface)) |instr| {
        if (instr.cmd == .quit) break;

        handleInstruction(instr, &game, &stdout_writer.interface) catch |err| {
            std.debug.print("Invalid {s} command: {}\n", .{ @tagName(instr.cmd), err });
        };
    }
}

test "position startpos moves" {
    var game = engine.Game.new(t.allocator);
    defer game.deinit();

    try handlePosition("startpos moves e2e4 e7e5 g1f3", &game);

    try t.expectEqual(engine.Color.Black, game.sideToMove());
    try t.expect(game.position.getPieceAtForSide(.e4, .White) == .Pawn);
    try t.expect(game.position.getPieceAtForSide(.e5, .Black) == .Pawn);
    try t.expect(game.position.getPieceAtForSide(.f3, .White) == .Knight);
}

test "position fen" {
    var game = engine.Game.new(t.allocator);
    defer game.deinit();

    try handlePosition("fen 4k3/8/8/8/8/8/8/4K3 b - e3 37 42", &game);

    try t.expectEqual(engine.Color.Black, game.sideToMove());
    try t.expect(game.position.getPieceAtForSide(.e8, .Black) == .King);
    try t.expect(game.position.getPieceAtForSide(.e1, .White) == .King);
}

test "go depth" {
    try t.expectEqual(@as(u8, 1), try parseGoDepth("depth 1"));
    try t.expectEqual(DEFAULT_SEARCH_DEPTH, try parseGoDepth("wtime 1000 btime 1000"));
    try t.expectEqual(MAX_SEARCH_DEPTH, try parseGoDepth("depth 99"));
    try t.expectEqual(DEFAULT_SEARCH_DEPTH, try parseGoDepth("depth 0"));
}
