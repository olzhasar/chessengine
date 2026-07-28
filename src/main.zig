const std = @import("std");
const Io = std.Io;

const chessengine = @import("chessengine");

pub fn main() !void {
    chessengine.run();
}
