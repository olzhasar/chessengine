const std = @import("std");
const assert = std.debug.assert;
const t = std.testing;

// LSB (bit 0) - a1, MSB (bit 63) - h8.
const Bitboard = u64;

inline fn idx_to_bitboard(idx: u8) Bitboard {
    return @as(Bitboard, 1) << @intCast(idx);
}

const GameError = error{
    InvalidMove,
    InvalidFEN,
};

fn print_bitboard(board: Bitboard) void {
    std.debug.print("-" ** 33, .{});
    std.debug.print("\n", .{});
    for (0..8) |r| {
        std.debug.print("|", .{});
        for (0..8) |f| {
            const idx: u8 = @intCast((7 - r) * 8 + f);
            const mask = idx_to_bitboard(idx);
            const c: u8 = if (board & mask == 0) ' ' else 'X';
            std.debug.print(" {c} |", .{c});
        }
        std.debug.print("\n", .{});
        std.debug.print("-" ** 33, .{});
        std.debug.print("\n", .{});
    }
}

const Color = enum(u1) {
    White,
    Black,

    fn idx(self: Color) usize {
        return @intFromEnum(self);
    }

    // get the opposite color
    fn opp(self: Color) Color {
        if (self == .White) return .Black;
        return .White;
    }

    fn pawn_direction(self: Color) i3 {
        return if (self == .White) 1 else -1;
    }

    fn start_rank(self: Color) u3 {
        return if (self == .White) 0 else 7;
    }

    fn end_rank(self: Color) u3 {
        return if (self == .White) 7 else 0;
    }

    fn symbol(self: Color) u8 {
        if (self == .White) return 'W' else return 'B';
    }
};

// square address 0-63
const Square = struct {
    idx: u8,

    fn at(addr: *const [2]u8) Square {
        assert(addr[1] >= '1' and addr[1] <= '8');
        assert(addr[0] >= 'a' and addr[0] <= 'h');

        return .{ .idx = (addr[1] - '1') * 8 + addr[0] - 'a' };
    }

    fn get(idx: u8) Square {
        assert(idx >= 0 and idx < 64);
        return .{ .idx = idx };
    }

    fn file(self: Square) u3 {
        return @truncate(self.idx % 8);
    }

    fn rank(self: Square) u3 {
        return @truncate(self.idx / 8);
    }

    fn file_str(self: Square) u8 {
        return @as(u8, 'a') + self.file();
    }

    fn rank_str(self: Square) u8 {
        return @as(u8, '1') + self.rank();
    }

    fn str(self: Square) [2]u8 {
        return .{
            self.file_str(),
            self.rank_str(),
        };
    }

    // locate a square shifted relative to the current one, null if out of bounds
    fn rel(self: Square, file_shift: i8, rank_shift: i8) ?Square {
        const target_rank: i16 = self.rank() + rank_shift;
        if (target_rank < 0 or target_rank > 7) return null;

        const target_file: i16 = self.file() + file_shift;
        if (target_file < 0 or target_file > 7) return null;

        return .{ .idx = @as(u8, @intCast(target_rank * 8)) + @as(u8, @intCast(target_file)) };
    }

    // get bitmask for bitwise operations with bitboard
    fn mask(self: Square) Bitboard {
        return idx_to_bitboard(self.idx);
    }
};

test "square_from_addr" {
    const cases = [_]struct { input: *const [2]u8, expected: u8 }{
        .{ .input = "a1", .expected = 0 },
        .{ .input = "h8", .expected = 63 },
        .{ .input = "c2", .expected = 10 },
    };

    for (cases) |case| {
        const sq: Square = Square.at(case.input);
        try t.expectEqual(case.expected, sq.idx);
        try t.expectEqualStrings(case.input, &sq.str());
    }
}

const SquareContent = struct {
    piece: ?Piece,
    color: ?Color,
};

const Piece = enum(u3) {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,

    fn symbol(self: Piece, color: Color) u21 {
        return switch (color) {
            .Black => switch (self) {
                Piece.Pawn => 0x2659,
                Piece.Knight => 0x2658,
                Piece.Bishop => 0x2657,
                Piece.Rook => 0x2656,
                Piece.Queen => 0x2655,
                Piece.King => 0x2654,
            },
            .White => switch (self) {
                Piece.Pawn => 0x265F,
                Piece.Knight => 0x265E,
                Piece.Bishop => 0x265D,
                Piece.Rook => 0x265C,
                Piece.Queen => 0x265B,
                Piece.King => 0x265A,
            },
        };
    }

    fn idx(self: Piece) usize {
        return @intFromEnum(self);
    }
};

const PromotionPieces = [_]Piece{
    Piece.Knight,
    Piece.Bishop,
    Piece.Rook,
    Piece.Queen,
};

const MoveType = enum {
    NORMAL,
    CAPTURE,
    CASTLE,
    PROMOTION,
};

const Move = struct {
    from: Square,
    to: Square,
    move_type: MoveType = .NORMAL,
    promotion_piece: ?Piece = null,

    fn str(self: Move) [4]u8 {
        return [4]u8{
            self.from.file_str(),
            self.from.rank_str(),
            self.to.file_str(),
            self.to.rank_str(),
        };
    }
};

const MoveList = struct {
    moves: [255]Move = undefined,
    len: u8 = 0,

    fn append(self: *MoveList, from: Square, to: Square, move_type: MoveType) void {
        self.moves[self.len] = .{ .from = from, .to = to, .move_type = move_type };
        self.len += 1;
    }

    fn append_move(self: *MoveList, move: Move) void {
        self.moves[self.len] = move;
        self.len += 1;
    }

    fn has(self: *MoveList, str: []const u8, move_type: MoveType) bool {
        for (0..self.len) |i| {
            if (std.mem.eql(u8, &self.moves[i].str(), str)) {
                assert(self.moves[i].move_type == move_type);
                return true;
            }
        }
        return false;
    }

    fn draw(self: *const MoveList) void {
        var buf: [64]u8 = @splat(32);

        for (0..self.len) |i| {
            buf[self.moves[i].to.idx] = 'X';
        }

        std.debug.print("-" ** 33, .{});
        std.debug.print("\n", .{});
        for (0..8) |r| {
            std.debug.print("|", .{});
            for (0..8) |f| {
                const idx = (7 - r) * 8 + f;
                std.debug.print(" {c} |", .{buf[idx]});
            }
            std.debug.print("\n", .{});
            std.debug.print("-" ** 33, .{});
            std.debug.print("\n", .{});
        }
    }

    fn print(self: *const MoveList) void {
        for (0..self.len) |i| {
            const move = self.moves[i];
            std.debug.print("{s}\n", .{move.str()});
        }
    }

    fn reset(self: *MoveList) void {
        self.len = 0;
    }
};

const CastlingRights = struct {
    long: bool = true,
    short: bool = true,
};

const Position = struct {
    // [color][piece type] bitmasks
    piece_boards: [2][6]Bitboard,
    // [piece][short, long]
    castling_rights: [2]CastlingRights = .{ .{}, .{} },
    side_to_move: Color,
    en_passant_targets: Bitboard = 0,

    // the enemy (opposite) of the current side_to_move
    fn side_enemy(self: *const Position) Color {
        return self.side_to_move.opp();
    }

    fn init(side_to_move: Color) Position {
        return .{
            .side_to_move = side_to_move,
            .piece_boards = .{
                @splat(0),
                @splat(0),
            },
        };
    }

    fn put(self: *Position, color: Color, piece: Piece, addr: *const [2]u8) void {
        const square = Square.at(addr);
        assert(self.occupied() & square.mask() == 0);

        self.piece_boards[color.idx()][piece.idx()] |= square.mask();
    }

    fn parse_move(self: *Position, input: []const u8) !Move {
        const occupied_self = self.occupiedBy(self.side_to_move);
        const occupied_enemy = self.occupiedBy(self.side_enemy());

        var move: Move = .{ .from = .at(input[0..2]), .to = .at(input[2..4]) };
        if (move.from.mask() & occupied_self == 0) return GameError.InvalidMove;
        if (move.to.mask() & occupied_self != 0) return GameError.InvalidMove;

        if (input.len < 4 or input.len > 5) return GameError.InvalidMove;

        const piece = self.getPieceAt(input[0..2]).?;
        if (piece == .King) {
            if (input.len != 4) return GameError.InvalidMove;
            switch (self.side_to_move) {
                .White => {
                    if (move.from.idx == Square.at("e1").idx) {
                        if (move.to.idx == Square.at("c1").idx or move.to.idx == Square.at("g1").idx) move.move_type = .CASTLE;
                    }
                },
                .Black => {
                    if (move.from.idx == Square.at("e8").idx) {
                        if (move.to.idx == Square.at("c8").idx or move.to.idx == Square.at("g8").idx) move.move_type = .CASTLE;
                    }
                },
            }
        } else if (move.to.mask() & occupied_enemy != 0 or move.to.mask() & self.en_passant_targets != 0) {
            if (input.len != 4) return GameError.InvalidMove;
            move.move_type = .CAPTURE;
        } else if (piece == .Pawn and move.to.rank() == self.side_to_move.end_rank()) {
            if (input.len != 5) return GameError.InvalidMove;
            move.move_type = .PROMOTION;
            move.promotion_piece = switch (input[4]) {
                'q' => .Queen,
                'r' => .Rook,
                'b' => .Bishop,
                'n' => .Knight,
                else => return GameError.InvalidMove,
            };
        } else if (input.len != 4) return GameError.InvalidMove;

        return move;
    }

    fn go(self: *Position, input: []const u8) !void {
        const move = try self.parse_move(input);

        self.apply(move);
    }

    fn resetEnPassantTargets(self: *Position, side: Color) void {
        var mask: u64 = (1 << 32) - 1;
        if (side == .White) mask = ~mask;

        self.en_passant_targets &= mask;
    }

    fn apply(self: *Position, move: Move) void {
        const from_mask = move.from.mask();
        const to_mask = move.to.mask();

        self.resetEnPassantTargets(self.side_to_move);

        var piece: Piece = undefined;

        for (std.enums.values(Piece)) |p| {
            const bitmask = &self.piece_boards[self.side_to_move.idx()][p.idx()];

            if (bitmask.* & from_mask != 0) {
                bitmask.* ^= from_mask;
                bitmask.* |= to_mask;
                piece = p;

                break;
            }
        } else unreachable;

        // en passant
        if (piece == .Pawn and @abs(@as(i8, move.to.rank()) - @as(i8, move.from.rank())) == 2) {
            const en_passant_square: ?Square = switch (self.side_to_move) {
                .White => move.to.rel(0, -1),
                .Black => move.to.rel(0, 1),
            };

            self.en_passant_targets |= en_passant_square.?.mask();
        } else if (piece == .Rook) {
            switch (self.side_to_move) {
                .White => {
                    if (move.from.idx == Square.at("h1").idx) {
                        self.castling_rights[self.side_to_move.idx()].short = false;
                    } else if (move.from.idx == Square.at("a1").idx) {
                        self.castling_rights[self.side_to_move.idx()].long = false;
                    }
                },
                .Black => {
                    if (move.from.idx == Square.at("h8").idx) {
                        self.castling_rights[self.side_to_move.idx()].short = false;
                    } else if (move.from.idx == Square.at("a8").idx) {
                        self.castling_rights[self.side_to_move.idx()].long = false;
                    }
                },
            }
        } else if (piece == .King) {
            self.castling_rights[self.side_to_move.idx()].short = false;
            self.castling_rights[self.side_to_move.idx()].long = false;
        }

        if (move.move_type == .CAPTURE) {
            var captured_piece: Piece = undefined;

            for (std.enums.values(Piece)) |p| {
                const bitmask = &self.piece_boards[self.side_enemy().idx()][p.idx()];
                if (bitmask.* & to_mask != 0) {
                    bitmask.* ^= to_mask;
                    captured_piece = p;
                    break;
                }
            } else if (self.en_passant_targets & move.to.mask() != 0) {
                // en passant
                const pawn_to_capture = switch (self.side_to_move) {
                    .White => move.to.rel(0, -1),
                    .Black => move.to.rel(0, 1),
                };

                assert(self.piece_boards[self.side_enemy().idx()][Piece.Pawn.idx()] & pawn_to_capture.?.mask() != 0);
                self.piece_boards[self.side_enemy().idx()][Piece.Pawn.idx()] ^= pawn_to_capture.?.mask();
            } else unreachable;

            if (captured_piece == .Rook) {
                switch (self.side_enemy()) {
                    .White => {
                        if (move.to.idx == Square.at("h1").idx) {
                            self.castling_rights[self.side_enemy().idx()].short = false;
                        } else if (move.to.idx == Square.at("a1").idx) {
                            self.castling_rights[self.side_enemy().idx()].long = false;
                        }
                    },
                    .Black => {
                        if (move.to.idx == Square.at("h8").idx) {
                            self.castling_rights[self.side_enemy().idx()].short = false;
                        } else if (move.to.idx == Square.at("a8").idx) {
                            self.castling_rights[self.side_enemy().idx()].long = false;
                        }
                    },
                }
            }
        } else if (move.move_type == .CASTLE) {
            var old_rook_square: Square = undefined;
            var new_rook_square: Square = undefined;

            switch (move.to.file()) {
                // long castle
                2 => {
                    switch (self.side_to_move) {
                        .White => {
                            old_rook_square = Square.at("a1");
                            new_rook_square = Square.at("d1");
                        },
                        .Black => {
                            old_rook_square = Square.at("a8");
                            new_rook_square = Square.at("d8");
                        },
                    }
                },
                // short castle
                6 => {
                    switch (self.side_to_move) {
                        .White => {
                            old_rook_square = Square.at("h1");
                            new_rook_square = Square.at("f1");
                        },
                        .Black => {
                            old_rook_square = Square.at("h8");
                            new_rook_square = Square.at("f8");
                        },
                    }
                },
                else => unreachable,
            }

            self.piece_boards[self.side_to_move.idx()][Piece.Rook.idx()] ^= old_rook_square.mask();
            self.piece_boards[self.side_to_move.idx()][Piece.Rook.idx()] |= new_rook_square.mask();

            self.castling_rights[self.side_to_move.idx()].long = false;
            self.castling_rights[self.side_to_move.idx()].short = false;
        }

        self.switchSide();
    }

    fn switchSide(self: *Position) void {
        self.side_to_move = self.side_to_move.opp();
    }

    fn start() Position {
        return .{
            .piece_boards = .{
                .{
                    0x000000000000ff00,
                    0x0000000000000042,
                    0x0000000000000024,
                    0x0000000000000081,
                    0x0000000000000008,
                    0x0000000000000010,
                },
                .{
                    0x00ff000000000000,
                    0x4200000000000000,
                    0x2400000000000000,
                    0x8100000000000000,
                    0x0800000000000000,
                    0x1000000000000000,
                },
            },
            .side_to_move = Color.White,
        };
    }

    fn print(self: *const Position) void {
        var piece_mask: [64]u21 = @splat(32);
        var color_mask: [64]u8 = @splat(32);

        inline for (std.enums.values(Color), 0..) |col, ci| {
            inline for (std.enums.values(Piece), 0..) |piece, pi| {
                const bitmask = self.piece_boards[ci][pi];

                for (0..64) |i| {
                    if ((bitmask >> @truncate(i)) & 1 == 1) {
                        piece_mask[i] = piece.symbol(col);
                        color_mask[i] = col.symbol();
                    }
                }
            }
        }

        std.debug.print("-" ** 33, .{});
        std.debug.print("\n", .{});
        for (0..8) |r| {
            std.debug.print("|", .{});
            for (0..8) |f| {
                const idx = (7 - r) * 8 + f;
                std.debug.print(" {u} |", .{piece_mask[idx]});
            }
            std.debug.print("\n", .{});
            std.debug.print("-" ** 33, .{});
            std.debug.print("\n", .{});
        }
    }

    fn occupied(self: *const Position) Bitboard {
        return self.occupiedBy(.White) | self.occupiedBy(.Black);
    }

    fn occupiedBy(self: *const Position, color: Color) Bitboard {
        var result: Bitboard = 0;
        inline for (std.enums.values(Piece)) |piece| {
            result |= self.piece_boards[color.idx()][piece.idx()];
        }

        return result;
    }

    fn getPieceAt(self: *const Position, addr: *const [2]u8) ?Piece {
        const square = Square.at(addr);

        for (0..2) |ci| {
            for (std.enums.values(Piece)) |piece| {
                if (self.piece_boards[ci][piece.idx()] & square.mask() != 0) return piece;
            }
        }

        return null;
    }

    fn getSquareContent(self: *const Position, square: Square) ?SquareContent {
        var content: SquareContent = undefined;

        for (std.enums.values(Color)) |color| {
            for (std.enums.values(Piece)) |piece| {
                if (self.piece_boards[color.idx()][piece.idx()] & square.mask() != 0) {
                    content.piece = piece;
                    content.color = color;
                }
            }
        }

        return null;
    }

    fn fromFEN(input: []const u8) !Position {
        var pos = Position.init(.White);

        var rank: u8 = 7;
        var idx: u8 = 0;

        var i: u8 = 0;
        while (i < input.len) : (i += 1) {
            const char = input[i];
            if (char >= '1' and char <= '9') {
                idx += char - '1' + 1;
                continue;
            }

            if (char == '/') {
                if (rank == 0) break;
                rank -= 1;
                continue;
            }

            const square = Square.get(rank * 8 + (idx % 8));

            var color: Color = undefined;

            if (char >= 'b' and char <= 'r') {
                color = .Black;
            } else if (char >= 'B' and char <= 'R') {
                color = .White;
            } else {
                std.debug.print("i: {}, idx: {}, char: {c}\n", .{ i, idx, char });
                return GameError.InvalidFEN;
            }

            const piece: Piece = switch (char) {
                'p', 'P' => .Pawn,
                'b', 'B' => .Bishop,
                'k', 'K' => .King,
                'n', 'N' => .Knight,
                'r', 'R' => .Rook,
                'q', 'Q' => .Queen,
                else => return GameError.InvalidFEN,
            };

            pos.piece_boards[color.idx()][piece.idx()] |= square.mask();
            idx += 1;
            if (idx >= 64) break;
        }

        // side to move

        i += 2;

        pos.side_to_move = switch (input[i]) {
            'w' => .White,
            'b' => .Black,
            else => return GameError.InvalidFEN,
        };

        i += 2;

        pos.castling_rights = .{ .{ .long = false, .short = false }, .{ .long = false, .short = false } };

        while (i < input.len) : (i += 1) {
            switch (input[i]) {
                'k' => pos.castling_rights[Color.Black.idx()].short = true,
                'q' => pos.castling_rights[Color.Black.idx()].long = true,
                'K' => pos.castling_rights[Color.White.idx()].short = true,
                'Q' => pos.castling_rights[Color.White.idx()].long = true,
                else => break,
            }
        }

        return pos;

        // TODO moves counters
    }
};

test "position_apply" {
    var pos = Position.start();

    const move = Move{ .from = .at("e2"), .to = .at("e4"), .move_type = .NORMAL };

    try t.expect(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.from.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.to.mask(), 0);

    pos.apply(move);

    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.from.mask(), 0);
    try t.expect(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.to.mask() != 0);
}

test "position_apply_capture" {
    var pos = Position.init(.White);

    pos.put(.White, .Pawn, "e4");
    pos.put(.Black, .Pawn, "d5");

    const move = Move{ .from = .at("e4"), .to = .at("d5"), .move_type = .NORMAL };

    try t.expect(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.from.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.to.mask(), 0);

    pos.apply(move);

    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.from.mask(), 0);
    try t.expect(pos.piece_boards[Color.White.idx()][Piece.Pawn.idx()] & move.to.mask() != 0);
}

test "position_apply_castle" {
    var pos = Position.init(.White);

    pos.put(.White, .King, "e1");
    pos.put(.White, .Rook, "h1");

    const move = Move{ .from = .at("e1"), .to = .at("g1"), .move_type = .CASTLE };
    pos.apply(move);

    try t.expect(pos.piece_boards[Color.White.idx()][Piece.King.idx()] & move.to.mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.King.idx()] & move.from.mask(), 0);

    try t.expect(pos.piece_boards[Color.White.idx()][Piece.Rook.idx()] & Square.at("f1").mask() != 0);
    try t.expectEqual(pos.piece_boards[Color.White.idx()][Piece.Rook.idx()] & Square.at("h1").mask(), 0);
}

test "position_apply_en_passant_push" {
    var pos = Position.init(.Black);

    pos.put(.White, .Pawn, "e5");
    pos.put(.Black, .Pawn, "f7");

    try pos.go("f7f5");

    try t.expect(pos.en_passant_targets & Square.at("f6").mask() != 0);
}

test "position_apply_en_passant_capture" {
    var pos = Position.init(.White);

    pos.put(.Black, .Pawn, "c4");
    pos.put(.White, .Pawn, "b2");
    pos.put(.White, .Pawn, "a2");

    pos.put(.White, .Pawn, "e5");
    pos.put(.Black, .Pawn, "f7");

    try pos.go("b2b4");
    try pos.go("c4b3");

    try pos.go("a2b3");

    try pos.go("f7f5");
    try pos.go("e5f6");

    try t.expectEqual(Piece.Pawn, pos.getPieceAt("b3"));
    try t.expectEqual(null, pos.getPieceAt("b4"));
}

test "position_apply_castling_rights_king_moved" {
    var pos = Position.start();

    try pos.go("e2e4");
    try pos.go("e7e5");

    try pos.go("e1e2");

    try t.expect(!pos.castling_rights[Color.White.idx()].short);
    try t.expect(!pos.castling_rights[Color.White.idx()].long);
    try t.expect(pos.castling_rights[Color.Black.idx()].short);
    try t.expect(pos.castling_rights[Color.Black.idx()].long);

    try pos.go("e8e7");

    try t.expect(!pos.castling_rights[Color.Black.idx()].short);
    try t.expect(!pos.castling_rights[Color.Black.idx()].long);
}

test "position_apply_castling_rights_rook_moved" {
    var pos = Position.init(.White);

    pos.put(.White, .King, "e1");
    pos.put(.White, .Rook, "a1");
    pos.put(.White, .Rook, "h1");

    pos.put(.Black, .King, "e8");
    pos.put(.Black, .Rook, "a8");
    pos.put(.Black, .Rook, "h8");

    try pos.go("a1a4");
    try t.expect(!pos.castling_rights[Color.White.idx()].long);
    try t.expect(pos.castling_rights[Color.White.idx()].short);

    try pos.go("h8h4");
    try t.expect(!pos.castling_rights[Color.Black.idx()].short);
    try t.expect(pos.castling_rights[Color.Black.idx()].long);

    try pos.go("h1h2");
    try t.expect(!pos.castling_rights[Color.White.idx()].short);

    try pos.go("a8a7");
    try t.expect(!pos.castling_rights[Color.Black.idx()].long);
}

test "position_apply_rook_captured" {
    var pos = Position.init(.White);

    pos.put(.White, .King, "e1");
    pos.put(.White, .Knight, "b1");
    pos.put(.White, .Knight, "g1");
    pos.put(.White, .Rook, "a1");
    pos.put(.White, .Rook, "h1");

    pos.put(.Black, .King, "e8");
    pos.put(.White, .Knight, "b8");
    pos.put(.White, .Knight, "g8");
    pos.put(.Black, .Rook, "a8");
    pos.put(.Black, .Rook, "h8");

    try pos.go("a1a8");
    try t.expect(!pos.castling_rights[Color.Black.idx()].long);
    try t.expect(pos.castling_rights[Color.Black.idx()].short);

    try pos.go("h8h1");
    try t.expect(!pos.castling_rights[Color.White.idx()].short);
    try t.expect(!pos.castling_rights[Color.White.idx()].long);
}

test "parse_move" {
    var pos = Position.init(.White);

    pos.put(.White, .Pawn, "e4");
    pos.put(.Black, .Pawn, "d5");

    var move: Move = undefined;
    move = try pos.parse_move("e4e5");

    try t.expectEqualStrings("e4", &move.from.str());
    try t.expectEqualStrings("e5", &move.to.str());
    try t.expectEqual(MoveType.NORMAL, move.move_type);

    move = try pos.parse_move("e4d5");

    try t.expectEqualStrings("e4", &move.from.str());
    try t.expectEqualStrings("d5", &move.to.str());
    try t.expectEqual(MoveType.CAPTURE, move.move_type);

    pos.put(.White, .King, "e1");
    pos.put(.White, .Rook, "a1");
    pos.put(.White, .Rook, "h1");

    move = try pos.parse_move("e1g1");

    try t.expectEqualStrings("e1", &move.from.str());
    try t.expectEqualStrings("g1", &move.to.str());
    try t.expectEqual(MoveType.CASTLE, move.move_type);

    pos.put(.White, .Pawn, "b7");

    move = try pos.parse_move("b7b8q");

    try t.expectEqualStrings("b7", &move.from.str());
    try t.expectEqualStrings("b8", &move.to.str());
    try t.expectEqual(MoveType.PROMOTION, move.move_type);
    try t.expectEqual(Piece.Queen, move.promotion_piece);
}

test "from_fen" {
    const pos = try Position.fromFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    const start = Position.start();

    for (0..2) |ci| {
        for (std.enums.values(Piece)) |piece| {
            try t.expectEqual(start.piece_boards[ci][piece.idx()], pos.piece_boards[ci][piece.idx()]);
        }
    }
}

fn getAttacksPawn(from: Square, side: Color) Bitboard {
    var result: Bitboard = 0;

    const left = if (side == .White) from.rel(-1, 1) else from.rel(1, -1);
    if (left != null) result |= left.?.mask();

    const right = if (side == .White) from.rel(1, 1) else from.rel(-1, -1);
    if (right != null) result |= right.?.mask();

    return result;
}

fn getAttacksKnight(from: Square) Bitboard {
    const directions = [_]struct { x: i8, y: i8 }{
        .{ .x = -1, .y = 2 },
        .{ .x = 1, .y = 2 },
        .{ .x = -1, .y = -2 },
        .{ .x = 1, .y = -2 },
        .{ .x = -2, .y = 1 },
        .{ .x = -2, .y = -1 },
        .{ .x = 2, .y = 1 },
        .{ .x = 2, .y = -1 },
    };

    var result: Bitboard = 0;

    for (&directions) |dir| {
        const target = from.rel(dir.x, dir.y);
        if (target != null) result |= target.?.mask();
    }

    return result;
}

fn getAttacksBishop(from: Square, occupied: Bitboard) Bitboard {
    const directions = [_]struct { x: i8, y: i8 }{
        .{ .x = -1, .y = 1 },
        .{ .x = 1, .y = 1 },
        .{ .x = -1, .y = -1 },
        .{ .x = 1, .y = -1 },
    };

    var result: Bitboard = 0;

    for (&directions) |*dir| {
        inner: for (1..8) |i| {
            const target = from.rel(@as(i8, @intCast(i)) * dir.x, @as(i8, @intCast(i)) * dir.y);
            if (target == null) {
                break :inner;
            }

            result |= target.?.mask();
            if (occupied & target.?.mask() != 0) break :inner;
        }
    }

    return result;
}

fn getAttacksRook(from: Square, occupied: Bitboard) Bitboard {
    const directions = [_]struct { x: i8, y: i8 }{
        .{ .x = 1, .y = 0 },
        .{ .x = -1, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = 0, .y = -1 },
    };

    var result: Bitboard = 0;

    for (&directions) |*dir| {
        inner: for (1..8) |i| {
            const target = from.rel(@as(i8, @intCast(i)) * dir.x, @as(i8, @intCast(i)) * dir.y);
            if (target == null) {
                break :inner;
            }

            result |= target.?.mask();

            if (occupied & target.?.mask() != 0) break :inner;
        }
    }

    return result;
}

fn getAttacksQueen(from: Square, occupied: Bitboard) Bitboard {
    return getAttacksBishop(from, occupied) | getAttacksRook(from, occupied);
}

fn getAttacksKing(from: Square) Bitboard {
    const directions = [_]struct { x: i8, y: i8 }{
        .{ .x = 1, .y = 0 },
        .{ .x = -1, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = 0, .y = -1 },
        .{ .x = 1, .y = -1 },
        .{ .x = 1, .y = 1 },
        .{ .x = -1, .y = 1 },
        .{ .x = -1, .y = -1 },
    };

    var result: Bitboard = 0;

    for (&directions) |*dir| {
        const target = from.rel(dir.x, dir.y);
        if (target != null) {
            result |= target.?.mask();
        }
    }

    return result;
}

fn getAttacks(piece: Piece, side: Color, from: Square, occupied: Bitboard) Bitboard {
    return switch (piece) {
        Piece.Pawn => getAttacksPawn(from, side),
        Piece.Knight => getAttacksKnight(from),
        Piece.Bishop => getAttacksBishop(from, occupied),
        Piece.Rook => getAttacksRook(from, occupied),
        Piece.Queen => getAttacksQueen(from, occupied),
        Piece.King => getAttacksKing(from),
    };
}

fn getPawnPushes(square: Square, side: Color, occupied: Bitboard) Bitboard {
    var result: Bitboard = 0;

    // push single
    var target = square.rel(0, side.pawn_direction());
    if (target == null or occupied & target.?.mask() != 0) return result;

    result |= target.?.mask();

    // push double
    if (side == .White and square.rank() != 1) return result;
    if (side == .Black and square.rank() != 6) return result;

    target = square.rel(0, side.pawn_direction() * 2);

    if (target != null and occupied & target.?.mask() == 0) {
        result |= target.?.mask();
    }

    return result;
}

fn getEnPassantMoves(from: Square, side: Color, pos: *const Position, out: *MoveList) void {
    const expected_rank: u3 = if (side == .White) 4 else 3;
    if (from.rank() != expected_rank) return;

    const targets = [2]?Square{ from.rel(1, side.pawn_direction()), from.rel(-1, side.pawn_direction()) };

    for (targets) |target| {
        if (target == null) continue;

        if (target.?.mask() & pos.en_passant_targets != 0) {
            out.append(from, target.?, .CAPTURE);
        }
    }

    return;
}

fn getCastleMoves(from: Square, side: Color, pos: *const Position, occupied: Bitboard, out: *MoveList) void {
    if (side == .White and from.idx != Square.at("e1").idx) return;
    if (side == .Black and from.idx != Square.at("e8").idx) return;
    if (!pos.castling_rights[side.idx()].long and !pos.castling_rights[side.idx()].short) return;

    if (isInCheck(pos, side)) return;

    if (pos.castling_rights[side.idx()].short) blk: {
        const squares: [2]Square = switch (side) {
            .White => [2]Square{ .at("f1"), .at("g1") },
            .Black => [2]Square{ .at("f8"), .at("g8") },
        };

        const mask = squares[0].mask() | squares[1].mask();

        if (mask & occupied != 0) break :blk;
        if (isAttacked(mask, side.opp(), pos)) break :blk;

        out.append(from, squares[1], .CASTLE);
    }

    if (pos.castling_rights[side.idx()].long) blk: {
        const squares: [3]Square = switch (side) {
            .White => [3]Square{ .at("d1"), .at("c1"), .at("b1") },
            .Black => [3]Square{ .at("d8"), .at("c8"), .at("b8") },
        };

        const mask = squares[0].mask() | squares[1].mask();

        if ((mask | squares[2].mask()) & occupied != 0) break :blk;
        if (isAttacked(mask, side.opp(), pos)) break :blk; // only the king path should be free from checks

        out.append(from, squares[1], .CASTLE);
    }
}

fn getMoveSquares(piece: Piece, from: Square, pos: *const Position, occupied: Bitboard, occupied_self: Bitboard, occupied_enemy: Bitboard) Bitboard {
    var squares = getAttacks(piece, pos.side_to_move, from, occupied) & ~occupied_self;

    if (piece == .Pawn) {
        squares &= occupied_enemy;
        squares |= getPawnPushes(from, pos.side_to_move, occupied);
    }

    return squares;
}

inline fn appendMoveIfLegal(move: Move, pos: *const Position, out: *MoveList) void {
    var pos_copy = pos.*;
    pos_copy.apply(move);

    if (!isInCheck(&pos_copy, pos.side_to_move)) out.append_move(move);
}

fn findMovesFrom(
    piece: Piece,
    from: Square,
    pos: *const Position,
    out: *MoveList,
) void {
    const occupied = pos.occupied();
    const occupied_self = pos.occupiedBy(pos.side_to_move);
    const occupied_enemy = pos.occupiedBy(pos.side_enemy());

    var squares = getMoveSquares(piece, from, pos, occupied, occupied_self, occupied_enemy);
    if (piece == .Pawn) getEnPassantMoves(from, pos.side_to_move, pos, out);
    if (piece == .King) getCastleMoves(from, pos.side_to_move, pos, occupied, out);

    while (squares != 0) : (squares &= squares - 1) {
        const idx = @ctz(squares);

        const target = Square.get(idx);
        const mask = target.mask();

        if (piece == .Pawn and target.file() == from.file() and (target.rank() == 7 or target.rank() == 0)) {
            inline for (PromotionPieces) |prom_piece| {
                appendMoveIfLegal(.{ .from = from, .to = target, .move_type = .PROMOTION, .promotion_piece = prom_piece }, pos, out);
            }
            continue;
        }

        const move_type: MoveType = if (mask & occupied_enemy == 0) .NORMAL else .CAPTURE;
        appendMoveIfLegal(.{ .from = from, .to = target, .move_type = move_type }, pos, out);
    }
}

test "pawn_moves" {
    const pos = Position.start();
    const square = Square.at("e2");

    var move_list: MoveList = .{};

    findMovesFrom(.Pawn, square, &pos, &move_list);
    try t.expectEqual(2, move_list.len);

    try t.expectEqualStrings(&move_list.moves[0].str(), "e2e3");
    try t.expectEqualStrings(&move_list.moves[1].str(), "e2e4");
}

test "pawn_step_starting" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e2");

    var move_list = MoveList{};
    findMovesFrom(.Pawn, .at("e2"), &pos, &move_list);

    try t.expectEqual(2, move_list.len);

    try t.expect(move_list.has("e2e3", .NORMAL));
    try t.expect(move_list.has("e2e4", .NORMAL));
}

test "pawn_step_not_starting" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e3");

    var move_list = MoveList{};
    findMovesFrom(.Pawn, .at("e3"), &pos, &move_list);

    try t.expectEqual(1, move_list.len);

    try t.expect(move_list.has("e3e4", .NORMAL));
}

test "pawn_step_blocked" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e2");
    pos.put(.Black, .Pawn, "e3");

    var move_list = MoveList{};
    findMovesFrom(.Pawn, .at("e2"), &pos, &move_list);

    try t.expectEqual(0, move_list.len);
}

test "pawn_capture" {
    var pos = Position.init(.White);
    pos.put(.White, .Pawn, "e2");
    pos.put(.Black, .Bishop, "d3");
    pos.put(.Black, .Bishop, "f3");

    var move_list = MoveList{};
    findMovesFrom(.Pawn, .at("e2"), &pos, &move_list);

    try t.expectEqual(4, move_list.len);

    try t.expect(move_list.has("e2e3", .NORMAL));
    try t.expect(move_list.has("e2e4", .NORMAL));
    try t.expect(move_list.has("e2d3", .CAPTURE));
    try t.expect(move_list.has("e2f3", .CAPTURE));
}

test "pawn_capture_2" {
    var pos = Position.init(.Black);
    pos.put(.Black, .Pawn, "d5");
    pos.put(.Black, .Bishop, "d4");
    pos.put(.White, .Bishop, "c6");
    pos.put(.White, .Queen, "c4");

    var move_list = MoveList{};
    findMovesFrom(.Pawn, .at("d5"), &pos, &move_list);

    try t.expectEqual(1, move_list.len);

    try t.expect(move_list.has("d5c4", .CAPTURE));
}

test "pawn_promotions" {
    var pos = Position.init(.White);

    pos.put(.White, .Pawn, "e7");

    var move_list = MoveList{};

    findMovesFrom(.Pawn, .at("e7"), &pos, &move_list);

    try t.expectEqual(4, move_list.len);

    for (0..move_list.len) |i| {
        const move = move_list.moves[i];
        try t.expectEqual(MoveType.PROMOTION, move.move_type);
        try t.expectEqualStrings("e7e8", &move.str());
        try t.expectEqualStrings("e8", &move.to.str());
        try t.expectEqualStrings("e7", &move.from.str());
    }
}

test "pawn_en_passant" {
    var pos = Position.init(.White);

    pos.put(.White, .Pawn, "e2");
    pos.put(.Black, .Pawn, "d4");

    pos.put(.White, .Pawn, "e5");
    pos.put(.Black, .Pawn, "f7");

    try pos.go("e2e4");

    var move_list = MoveList{};

    findMovesFrom(.Pawn, .at("d4"), &pos, &move_list);

    try t.expectEqual(2, move_list.len);
    try t.expect(move_list.has("d4e3", .CAPTURE));

    try pos.go("f7f5");

    move_list.reset();
    findMovesFrom(.Pawn, .at("e5"), &pos, &move_list);

    try t.expectEqual(2, move_list.len);
    try t.expect(move_list.has("e5f6", .CAPTURE));
}

test "knight" {
    var pos = Position.init(.White);
    pos.put(.White, .Knight, "e4");

    var move_list = MoveList{};
    findMovesFrom(.Knight, .at("e4"), &pos, &move_list);

    try t.expectEqual(8, move_list.len);

    try t.expect(move_list.has("e4d6", .NORMAL));
    try t.expect(move_list.has("e4f6", .NORMAL));
    try t.expect(move_list.has("e4c5", .NORMAL));
    try t.expect(move_list.has("e4g5", .NORMAL));
    try t.expect(move_list.has("e4c5", .NORMAL));
    try t.expect(move_list.has("e4g5", .NORMAL));
    try t.expect(move_list.has("e4c3", .NORMAL));
    try t.expect(move_list.has("e4g3", .NORMAL));
    try t.expect(move_list.has("e4d2", .NORMAL));
    try t.expect(move_list.has("e4f2", .NORMAL));
}

test "knight_2" {
    var pos = Position.init(.White);
    pos.put(.White, .Knight, "g4");
    pos.put(.White, .Queen, "f2");
    pos.put(.White, .King, "h2");
    pos.put(.Black, .Bishop, "f6");

    var move_list = MoveList{};
    findMovesFrom(.Knight, .at("g4"), &pos, &move_list);

    try t.expectEqual(4, move_list.len);

    try t.expect(move_list.has("g4f6", .CAPTURE));
    try t.expect(move_list.has("g4h6", .NORMAL));
    try t.expect(move_list.has("g4e5", .NORMAL));
    try t.expect(move_list.has("g4e3", .NORMAL));
}

test "bishop" {
    var pos = Position.init(.White);
    pos.put(.White, .Bishop, "e4");

    var move_list = MoveList{};
    findMovesFrom(.Bishop, .at("e4"), &pos, &move_list);

    try t.expectEqual(13, move_list.len);

    try t.expect(move_list.has("e4f5", .NORMAL));
    try t.expect(move_list.has("e4g6", .NORMAL));
    try t.expect(move_list.has("e4h7", .NORMAL));
    try t.expect(move_list.has("e4f3", .NORMAL));
    try t.expect(move_list.has("e4g2", .NORMAL));
    try t.expect(move_list.has("e4h1", .NORMAL));
    try t.expect(move_list.has("e4d5", .NORMAL));
    try t.expect(move_list.has("e4c6", .NORMAL));
    try t.expect(move_list.has("e4b7", .NORMAL));
    try t.expect(move_list.has("e4a8", .NORMAL));
    try t.expect(move_list.has("e4d3", .NORMAL));
    try t.expect(move_list.has("e4c2", .NORMAL));
    try t.expect(move_list.has("e4b1", .NORMAL));
}

test "bishop_2" {
    var pos = Position.init(.White);
    pos.put(.White, .Bishop, "g2");

    pos.put(.Black, .Knight, "f3");
    pos.put(.White, .Rook, "h1");

    var move_list = MoveList{};
    findMovesFrom(.Bishop, .at("g2"), &pos, &move_list);

    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("g2h3", .NORMAL));
    try t.expect(move_list.has("g2f1", .NORMAL));
    try t.expect(move_list.has("g2f3", .CAPTURE));
}

test "rook" {
    var pos = Position.init(.White);
    pos.put(.White, .Rook, "e4");

    var move_list = MoveList{};
    findMovesFrom(.Rook, .at("e4"), &pos, &move_list);

    try t.expectEqual(14, move_list.len);

    try t.expect(move_list.has("e4e5", .NORMAL));
    try t.expect(move_list.has("e4e6", .NORMAL));
    try t.expect(move_list.has("e4e7", .NORMAL));
    try t.expect(move_list.has("e4e8", .NORMAL));
    try t.expect(move_list.has("e4e3", .NORMAL));
    try t.expect(move_list.has("e4e2", .NORMAL));
    try t.expect(move_list.has("e4e1", .NORMAL));
    try t.expect(move_list.has("e4d4", .NORMAL));
    try t.expect(move_list.has("e4c4", .NORMAL));
    try t.expect(move_list.has("e4b4", .NORMAL));
    try t.expect(move_list.has("e4a4", .NORMAL));
    try t.expect(move_list.has("e4f4", .NORMAL));
    try t.expect(move_list.has("e4g4", .NORMAL));
    try t.expect(move_list.has("e4h4", .NORMAL));
}

test "rook_2" {
    var pos = Position.init(.White);
    pos.put(.White, .Rook, "g2");

    pos.put(.Black, .Knight, "g3");
    pos.put(.White, .Pawn, "f2");

    var move_list = MoveList{};
    findMovesFrom(.Rook, .at("g2"), &pos, &move_list);

    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("g2g3", .CAPTURE));
    try t.expect(move_list.has("g2h2", .NORMAL));
    try t.expect(move_list.has("g2g1", .NORMAL));
}

test "queen" {
    var pos = Position.init(.White);
    pos.put(.White, .Queen, "d1");

    pos.put(.White, .Pawn, "d3");
    pos.put(.Black, .Pawn, "c2");
    pos.put(.White, .Bishop, "c1");
    pos.put(.White, .King, "e1");

    var move_list = MoveList{};
    findMovesFrom(.Queen, .at("d1"), &pos, &move_list);

    try t.expectEqual(6, move_list.len);
}

test "king" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "e4");

    var move_list = MoveList{};
    findMovesFrom(.King, .at("e4"), &pos, &move_list);

    try t.expectEqual(8, move_list.len);

    try t.expect(move_list.has("e4e5", .NORMAL));
    try t.expect(move_list.has("e4d5", .NORMAL));
    try t.expect(move_list.has("e4f5", .NORMAL));
    try t.expect(move_list.has("e4d4", .NORMAL));
    try t.expect(move_list.has("e4f4", .NORMAL));
    try t.expect(move_list.has("e4d3", .NORMAL));
    try t.expect(move_list.has("e4e3", .NORMAL));
    try t.expect(move_list.has("e4f3", .NORMAL));
}

test "king_2" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "e1");

    pos.put(.White, .Queen, "d1");
    pos.put(.White, .Pawn, "e2");

    pos.put(.Black, .Pawn, "d2");

    var move_list = MoveList{};
    findMovesFrom(.King, .at("e1"), &pos, &move_list);

    try t.expectEqual(3, move_list.len);

    try t.expect(move_list.has("e1f1", .NORMAL));
    try t.expect(move_list.has("e1f2", .NORMAL));
    try t.expect(move_list.has("e1d2", .CAPTURE));
}

test "castle_short" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "e1");
    pos.put(.White, .Rook, "h1");
    pos.put(.White, .Pawn, "e2");
    pos.put(.White, .Pawn, "d2");
    pos.put(.White, .Pawn, "f2");
    pos.put(.White, .Queen, "d1");

    var move_list = MoveList{};
    findMovesFrom(.King, .at("e1"), &pos, &move_list);

    try t.expect(move_list.has("e1g1", .CASTLE));
    try t.expect(!move_list.has("e1c1", .CASTLE));
}

test "castle_long_short" {
    var pos = Position.init(.Black);
    pos.put(.Black, .King, "e8");
    pos.put(.Black, .Rook, "a8");

    var move_list = MoveList{};
    findMovesFrom(.King, .at("e8"), &pos, &move_list);

    try t.expect(move_list.has("e8c8", .CASTLE));
    try t.expect(move_list.has("e8g8", .CASTLE));
}

test "castle_king_in_check" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "e1");
    pos.put(.White, .Rook, "a1");
    pos.put(.White, .Rook, "h1");

    pos.put(.Black, .Rook, "e8");

    var move_list = MoveList{};
    findMovesFrom(.King, .at("e1"), &pos, &move_list);

    try t.expect(!move_list.has("e1c1", .CASTLE));
    try t.expect(!move_list.has("e1g1", .CASTLE));
}

test "castle_king_path_in_check" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "e1");
    pos.put(.White, .Rook, "a1");
    pos.put(.White, .Rook, "h1");

    pos.put(.Black, .Rook, "b8");
    pos.put(.Black, .Rook, "g8");

    var move_list = MoveList{};
    findMovesFrom(.King, .at("e1"), &pos, &move_list);

    try t.expect(!move_list.has("e1g1", .CASTLE));
    try t.expect(move_list.has("e1c1", .CASTLE));
}

fn findAllMoves(pos: *const Position, out: *MoveList) void {
    inline for (std.enums.values(Piece)) |piece| {
        var placements = pos.piece_boards[pos.side_to_move.idx()][piece.idx()];

        while (placements != 0) : (placements &= placements - 1) {
            const idx = @ctz(placements);

            findMovesFrom(piece, .get(idx), pos, out);
        }
    }
}

test "starting_moves" {
    var position = Position.start();

    var move_list: MoveList = .{};

    findAllMoves(&position, &move_list);
    try t.expectEqual(20, move_list.len);

    position.side_to_move = .Black;
    move_list = .{};

    findAllMoves(&position, &move_list);
    try t.expectEqual(20, move_list.len);
}

fn isAttackedBy(area_mask: Bitboard, piece: Piece, attacker: Color, pos: *const Position, occupied: Bitboard) bool {
    var pieces = pos.piece_boards[attacker.idx()][piece.idx()];
    while (pieces != 0) : (pieces &= pieces - 1) {
        const idx = @ctz(pieces);
        const attacks = getAttacks(piece, attacker, .get(idx), occupied);
        if (attacks & area_mask != 0) return true;
    }

    return false;
}

// is any square in the area mask attacked by any piece of the attacker side
fn isAttacked(area: Bitboard, attacker: Color, pos: *const Position) bool {
    const occupied = pos.occupied();

    inline for (std.enums.values(Piece)) |piece| {
        if (isAttackedBy(area, piece, attacker, pos, occupied)) return true;
    }

    return false;
}

fn isInCheck(pos: *const Position, side: Color) bool {
    const king_mask = pos.piece_boards[side.idx()][Piece.King.idx()];

    return isAttacked(king_mask, side.opp(), pos);
}

test "is_check_no" {
    const pos = Position.start();

    try t.expect(!isInCheck(&pos, .White));
    try t.expect(!isInCheck(&pos, .Black));
}

test "is_check_pawn" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "d1");
    pos.put(.Black, .Pawn, "c2");

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, "e8");
    pos.put(.White, .Pawn, "d7");

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_knight" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "d1");
    pos.put(.Black, .Knight, "e3");

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, "h8");
    pos.put(.White, .Knight, "g6");

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_bishop" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "d1");
    pos.put(.Black, .Bishop, "a4");

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, "h8");
    pos.put(.White, .Bishop, "a1");

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_rook" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "d1");
    pos.put(.Black, .Rook, "d8");

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, "h8");
    pos.put(.White, .Rook, "h1");

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_queen" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "d1");
    pos.put(.Black, .Queen, "a4");

    try t.expect(isInCheck(&pos, .White));

    pos = Position.init(.Black);
    pos.put(.Black, .King, "h8");
    pos.put(.White, .Queen, "h1");

    try t.expect(isInCheck(&pos, .Black));
}

test "is_check_king" {
    var pos = Position.init(.White);
    pos.put(.White, .King, "e4");
    pos.put(.Black, .King, "d4");

    try t.expect(isInCheck(&pos, .White));
    try t.expect(isInCheck(&pos, .Black));
}

test "skips_moves_exposing_king" {
    var position = Position.start();

    position.put(.Black, .Bishop, "b4");

    var move_list: MoveList = .{};

    findAllMoves(&position, &move_list);

    try t.expectEqual(17, move_list.len);

    try t.expect(!move_list.has("d2d3", .NORMAL));
    try t.expect(!move_list.has("d2d4", .NORMAL));
    try t.expect(!move_list.has("b2b4", .NORMAL));
}

fn perft(pos: Position, depth: u8) u64 {
    if (depth == 0) return 1;
    var result: u64 = 0;

    var move_list = MoveList{};
    findAllMoves(&pos, &move_list);

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
    // try t.expectEqual(4865609, perft(pos, 5)); // e.p.
    // try t.expectEqual(119060324, perft(pos, 6));
    // try t.expectEqual(3195901860, perft(pos, 7));
}

test "perft_2" {
    const pos = try Position.fromFEN("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - ");

    try t.expectEqual(48, perft(pos, 1));
    try t.expectEqual(2039, perft(pos, 2));
    try t.expectEqual(97862, perft(pos, 3));
    // try t.expectEqual(4085603, perft(pos, 4));
}

pub const Game = struct {
    position: Position,

    pub fn new() Game {
        return .{
            .position = .start(),
        };
    }

    pub fn list_moves(self: *Game) void {
        var move_list: MoveList = .{};
        findAllMoves(&self.position, &move_list);

        for (0..move_list.len) |i| {
            std.debug.print("{s}\n", .{move_list.moves[i].str()});
        }
    }

    pub fn draw_board(self: *Game) void {
        self.position.print();
    }

    pub fn go(self: *Game, input: []const u8) !void {
        if (input.len != 4) return error.InvalidMove;

        self.position.go(input);
    }
};
