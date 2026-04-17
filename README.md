# Gameserver

This project is to build a basic MMORPG-like game server.

Idea is to leverage OTP to have servers around presence, world location, player characters, mobs, and combat.

Version 1 is to build enough to support a Nethack-like game built on top of LiveView.

## Mix commands

Run all checks (format, compile, test, dialyzer, credo):
```
mix check
```

Measure LiveView websocket diff sizes during player moves:
```
mix bench.diff_size --moves 20
```
needs `playwright-core` (via nix `playwright` package or `npm install playwright-core`).
see [docs/map_performance.md](docs/map_performance.md) for findings.

## License

Apache 2.0
