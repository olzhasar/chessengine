const std = @import("std");

const terminal = @import("terminal.zig");
const uci = @import("uci.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len > 1 and std.ascii.eqlIgnoreCase("play", args[1])) return terminal.play(init.io, init.gpa);

    return uci.run(init);
}
