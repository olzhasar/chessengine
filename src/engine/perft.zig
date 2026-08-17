const std = @import("std");
const t = std.testing;

const board = @import("board.zig");
const Position = board.Position;

const movegen = @import("movegen.zig");

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

test "perft" {
    const pos = Position.start();

    try t.expectEqual(20, perft(pos, 1));
    try t.expectEqual(400, perft(pos, 2));
    try t.expectEqual(8902, perft(pos, 3));
    try t.expectEqual(197281, perft(pos, 4));
    try t.expectEqual(4865609, perft(pos, 5)); // e.p.
    // try t.expectEqual(119060324, perft(pos, 6));
    // try t.expectEqual(3195901860, perft(pos, 7));
}

test "perft_2" {
    const pos = try Position.fromFEN("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");

    try t.expectEqual(48, perft(pos, 1));
    try t.expectEqual(2039, perft(pos, 2));
    try t.expectEqual(97862, perft(pos, 3));
    // try t.expectEqual(4085603, perft(pos, 4));
}

test "perft_3" {
    const pos = try Position.fromFEN("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1");

    try t.expectEqual(14, perft(pos, 1));
    try t.expectEqual(191, perft(pos, 2));
    try t.expectEqual(2812, perft(pos, 3));
    try t.expectEqual(43238, perft(pos, 4));
    // try t.expectEqual(674624, perft(pos, 5));
    // try t.expectEqual(11030083, perft(pos, 6));
    // try t.expectEqual(178633661, perft(pos, 7));
    // try t.expectEqual(3009794393, perft(pos, 8));
}

test "perft_4" {
    const pos = try Position.fromFEN("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1");

    try t.expectEqual(6, perft(pos, 1));
    try t.expectEqual(264, perft(pos, 2));
    try t.expectEqual(9467, perft(pos, 3));
    try t.expectEqual(422333, perft(pos, 4));
    // try t.expectEqual(15833292, perft(pos, 5));
    // try t.expectEqual(706045033, perft(pos, 6));
}

test "perft_5" {
    const pos = try Position.fromFEN("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8");

    try t.expectEqual(44, perft(pos, 1));
    try t.expectEqual(1486, perft(pos, 2));
    try t.expectEqual(62379, perft(pos, 3));
    // try t.expectEqual(2103487, perft(pos, 4));
    // try t.expectEqual(89941194, perft(pos, 4));
}
