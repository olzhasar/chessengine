const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const t = std.testing;

const engine = @import("chessengine");

const UciError = error{
    InvalidPositionCommand,
};

const Command = enum {
    quit,
    ucinewgame,
    position,
};

const Instruction = struct {
    cmd: Command,
    args: []const u8,
};

fn handleInstruction(instr: Instruction, game: *engine.Game) !void {
    switch (instr.cmd) {
        .quit => unreachable,
        .ucinewgame => game.setPosition(.start()),
        .position => try handlePosition(instr.args, game),
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

fn nextInstruction(reader: *Io.Reader) ?Instruction {
    while (true) {
        const raw_line = reader.takeDelimiter('\n') catch continue orelse continue;
        const line = std.mem.trim(u8, raw_line, " \t\r");

        const delim_idx = std.mem.indexOfAny(u8, line, " \t") orelse line.len;

        const cmd = std.meta.stringToEnum(Command, line[0..delim_idx]) orelse {
            std.debug.print("Unknown command: '{s}'\n", .{line});
            continue;
        };

        return .{ .cmd = cmd, .args = std.mem.trim(u8, line[@min(delim_idx + 1, line.len)..], " \t") };
    }
}

pub fn run(init: std.process.Init) !void {
    const stdin = std.Io.File.stdin();

    var buffer: [1024]u8 = undefined;
    var stdin_reader = stdin.reader(init.io, &buffer);

    var game: engine.Game = engine.Game.new(init.gpa);
    defer game.deinit();

    while (nextInstruction(&stdin_reader.interface)) |instr| {
        if (instr.cmd == .quit) break;

        handleInstruction(instr, &game) catch |err| {
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
