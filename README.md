A UCI-compatible hobby chess engine written in Zig.

## Features 

- Position representation with bitboards
- Legal move generation
- Best move search using [quiescence search](https://chessprogramming.org/Quiescence_Search), the [minimax](https://chessprogramming.org/Minimax) algorithm, and [alpha-beta pruning](https://chessprogramming.org/Alpha-Beta)
- UCI mode
- Terminal mode

## Build

Requires Zig 0.16+.

```sh
zig build --release=fast
```

The resulting binary is written to `zig-out/bin/chessengine`.

## Terminal mode

Play in the terminal:

```sh
./zig-out/bin/chessengine play
```

or

```sh
zig build run -- play
```

## UCI mode

With no arguments, the engine runs in [UCI](https://www.wbec-ridderkerk.nl/html/UCIProtocol.html) mode. Use any UCI-compatible GUI to play it (e.g. [cutechess](https://github.com/cutechess/cutechess))

```sh
./zig-out/bin/chessengine
```


## License

MIT
