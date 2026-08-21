const std = @import("std");
const t = std.testing;

const types = @import("types.zig");
const Position = @import("Position.zig");

const movegen = @import("movegen.zig");

const DEFAULT_DEPTH_LIMIT = 5;

pub const Case = struct {
    name: []const u8,
    fen: []const u8,
    nodes: []const u64,
};

pub const CASES = [_]Case{
    .{
        .name = "perft_1",
        .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        .nodes = &[_]u64{ 20, 400, 8902, 197281, 4865609, 119060324, 3195901860 },
    },
    .{
        .name = "perft_2",
        .fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        .nodes = &[_]u64{ 48, 2039, 97862, 4085603 },
    },
    .{
        .name = "perft_3",
        .fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        .nodes = &[_]u64{ 14, 191, 2812, 43238, 674624, 11030083, 178633661, 3009794393 },
    },
    .{
        .name = "perft_4",
        .fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        .nodes = &[_]u64{ 6, 264, 9467, 422333, 15833292, 706045033 },
    },
    .{
        .name = "perft_5",
        .fen = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
        .nodes = &[_]u64{ 44, 1486, 62379, 2103487, 89941194 },
    },
};

fn perft(pos: Position, depth: u8) u64 {
    if (depth == 0) return 1;
    var result: u64 = 0;

    var move_list = movegen.MoveList{};
    movegen.findAll(&pos, &move_list);

    for (0..move_list.len) |i| {
        var temp_pos = pos;
        const move = move_list.moves[i];
        temp_pos.apply(move);
        result += perft(temp_pos, depth - 1);
    }

    return result;
}

test "perft cases" {
    const max_depth = 4;

    for (CASES) |case| {
        const pos = try Position.fromFEN(case.fen);

        for (0..max_depth) |i| {
            if (i >= case.nodes.len) break;
            try t.expectEqual(case.nodes[i], perft(pos, @intCast(i + 1)));
        }
    }
}

pub fn run(io: std.Io, depth_limit: ?u8) !void {
    const limit = if (depth_limit != null and depth_limit.? > 0) depth_limit.? else DEFAULT_DEPTH_LIMIT;

    for (CASES, 1..) |case, case_i| {
        std.debug.print("Position: {}/{} fen: ({s}): \n", .{ case_i, CASES.len, case.fen });
        const pos = try Position.fromFEN(case.fen);

        for (0..limit) |i| {
            if (i >= case.nodes.len) break;
            const time_start = std.Io.Clock.now(.awake, io);
            const nodes = perft(pos, @intCast(i + 1));
            const elapsed: f64 = @as(f64, @floatFromInt(time_start.untilNow(io, .awake).toNanoseconds())) / 1e9;
            try t.expectEqual(case.nodes[i], nodes);

            const nps: f64 = @as(f64, @floatFromInt(nodes)) / elapsed;

            std.debug.print("depth {} elapsed: {d:.3} nps {d:.0} nodes {}\n", .{ i + 1, elapsed, nps, nodes });
        }
    }
}
