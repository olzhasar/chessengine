const std = @import("std");

const ZobristT = @This();

piece_boards: [2][6][64]u64,
castling_rights: [2][2]u64,
side_to_move: u64,
en_passant_targets: [8]u64,

fn make_zobrist_table() ZobristT {
    @setEvalBranchQuota(100_000);

    var PRNG = std.Random.DefaultPrng.init(123);
    var rand = PRNG.random();

    var z: ZobristT = undefined;

    for (0..2) |ci| {
        for (0..6) |pi| {
            for (0..64) |si| {
                z.piece_boards[ci][pi][si] = rand.int(u64);
            }
        }
    }

    for (0..2) |ci| {
        for (0..2) |si| {
            z.castling_rights[ci][si] = rand.int(u64);
        }
    }

    z.side_to_move = rand.int(u64);

    for (0..8) |fi| {
        z.en_passant_targets[fi] = rand.int(u64);
    }

    return z;
}

pub const TABLE = make_zobrist_table();
