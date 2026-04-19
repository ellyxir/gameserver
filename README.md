# Gameserver

A game server for multiplayer games, especially MMORPG-like games.

Elixir is a great language to build multiplayer support around because
of how easy it is to have concurrent processes which can represent
game levels, instances, players, mobs, etc. Elixir's Supervisor system
also restarts these processes when there are issues.

The current game server is very opinionated, it has a hardcoded Stats
system, but will later support a more adapter-based approach.

The server is authoritative and has all game state data.

## Demo Game

This repository also includes a demo game.
It's a multiplayer ASCII roguelike, imagine a simple Nethack
inspired game but adds on multiplayer support.
The game is also "real time" in the sense that mobs don't wait for the
player to make a move. There are cooldowns on abilities so you can't use
them until a certain amount of time has passed.

The demo is built on top of Phoenix LiveView.
The game comes with procedurally generated dungeons, real-time
combat, and mobs with simple behavior.
There is a game system also using Stats, Abilities, and Effects.

## Process Topology

```
Supervisor (rest_for_one)
  ├── EntityServer      — owns all entity data (stats, identity, position, cooldowns)
  ├── WorldServer       — spatial index, collision detection, movement validation
  ├── ProcessRegistry   — registry for per-mob GenServer lookups
  ├── MobServer         — DynamicSupervisor, spawns one GenServer per mob
  ├── CombatServer      — stateless combat resolution, serializes all attacks
  ├── TickServer        — schedules and executes periodic effects (DoTs, buffs)
  └── LiveView (per player)
```

Call flow (synchronous, no cycles)

```
LiveView ── move intent ───────→ WorldServer ─── update_position ──→ EntityServer
LiveView ── use_ability ───────→ CombatServer ── read/write stats ─→ EntityServer
Mob ── move intent ────────────→ WorldServer
Mob ── use_ability ────────────→ CombatServer
Mob ── get_entity ─────────────→ EntityServer
TickServer ── apply transform ─→ EntityServer
TickServer ── broadcast event ─→ CombatServer
MobServer ─── register mobs ───→ WorldServer
```

EntityServer is a leaf node, things call into it, it never calls out. It's a pure data
store. Collision rules, movement validation, and combat formulas all live in the servers above it.

WorldServer is a spatial index derived from EntityServer. It validates moves (walls,
entity collisions, cooldowns), then tells EntityServer to update the position. On restart, it
rebuilds its state from EntityServer and regenerates the same map using a persisted seed.

CombatServer is stateless, it processes each attack as a one-shot call. It validates
adjacency from entity positions, applies damage through EntityServer, and broadcasts the
result. The auto-attack loop lives in the LiveView (repeated timer-driven intents).

TickServer subscribes to entity changes via PubSub. When an entity gains a new tick,
it schedules timers to run the tick's transform on the configured interval. Handles
DoT damage, buff expiration, and cleanup on entity death.

Mob processes listen for combat events via PubSub. When hit, they aggro and counter-attack
on a 2-second timer. They stop wandering while aggro'd. On death, they remove themselves
from the world, respawn after a delay, and exit.

## Real-time Sync

All state changes broadcast via Phoenix PubSub across four topics:

| Topic | Events |
|-------|--------|
| `world:presence` | Entity join, entity leave |
| `world:movement` | Entity position changes |
| `combat:events` | Ability use, damage, death, DoT ticks |
| `entity:changes` | Entity creation, stat updates, entity removal |

LiveViews subscribe on mount and update their assigns from incoming messages.
The LiveView that triggers a change updates itself through the same `handle_info`
path as every other subscriber, one code path for all state changes.

## The Demo Game

Players connect in their browser, pick a username, and explore a procedurally generated
dungeon together. Controls are WASD / arrow keys or click-to-move.

### Map Generation

The dungeon is procedurally generated on a 30x30 grid:

1. Place rooms randomly, then check for overlap, repeat (with padding)
2. Connect rooms via minimum spanning tree (MST) over room centers (Kruskal's algorithm)
3. Carve L-shaped corridors along each MST edge
4. Place upstairs in the first room, downstairs in the farthest room
5. Validate the path between stairs crosses enough rooms, regenerate if too short

Generation is fully deterministic when given a seed. The seed is persisted in ETS so
WorldServer regenerates the same map after a restart.

### Stats

The stats system uses a protocol-based design with base stats and derived stats:

- Base stats (STR, DEX, CON) store a base value and a list of bonuses
- Derived stats (max HP) compute their value from other stats via a formula
- HP is checked to never exceed max HP
- Bonuses can be added and removed dynamically for buffs and equipment (once equipment becomes available)

Effective value of any stat = base (or formula result) + sum of all bonuses.

### Rendering
Note: this is not standard for Nethack, might change it to match in the near future, not sure. I've grown to like it a bit

| Tile | Character | Description |
|------|-----------|-------------|
| Wall | `#` | Blocks movement |
| Floor | `.` | Walkable |
| Door | `+` | Walkable (no special behavior yet) |
| Upstairs | `<` | Player spawn point |
| Downstairs | `>` | Destination (no level transition yet) |

Players render as `@` (yellow for you, cyan for others).
Mobs render as their first letter in red (goblin → `g`, spider → `s`, rat → `r`).

## Development

A `flake.nix` is included. If you use Nix, run `nix develop` to get a shell with
Elixir and all dependencies.

```sh
git clone ssh://git@codeberg.org/ellyxir/gameserver.git
cd gameserver
mix setup
mix phx.server
```

Go to [http://localhost:4000](http://localhost:4000)

```sh
mix test              # Run tests
mix format            # Format code
mix credo --strict    # Lint
mix dialyzer          # Type checking
mix precommit         # Run all checks (compile, format, test)
```

Benchmarking and performance docs are in the [docs/](docs/) directory.

## Future Features

- Equipment (using the same effect system as combat)
- Consumables
- Level transitions via stairs
- Aggressive mob pathfinding toward players
- Space partitioning (don't see all players move, performance optimisation)
- Instances
- Generalise game system (stats, formulas) 
- Sample 3D client
- Support real time movement with 3D interpolation

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
