const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const t = std.testing;

const engine = @import("chessengine");

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
    _ = game;
    std.debug.print("command: {s}, args: [{s}]\n", .{ @tagName(instr.cmd), instr.args });
}

fn nextInstruction(reader: *Io.Reader) ?Instruction {
    while (true) {
        const line = reader.takeDelimiter('\n') catch continue orelse continue;

        const delim_idx = std.mem.indexOfAny(u8, line, " ") orelse line.len;

        const cmd = std.meta.stringToEnum(Command, line[0..delim_idx]) orelse {
            std.debug.print("Unknown command: '{s}'\n", .{line});
            continue;
        };

        return .{ .cmd = cmd, .args = line[@min(delim_idx + 1, line.len)..line.len] };
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

        try handleInstruction(instr, &game);
    }
}
