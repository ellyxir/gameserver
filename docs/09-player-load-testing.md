# player load testing

baseline measurements of server behavior under concurrent player load.
measured with `mix bench.load` which connects simulated players over
real websockets to the liveview, joins the game, and moves around.

see issue #125 and pr (TBD) for when this was built.

## why websockets and not direct genserver calls

the goal is to measure what real clients experience, partly because
i wanted to make sure the server wouldn't fall apart for the reveal
at the conference.
a browser connecting to the game goes through:

websocket -> liveview mount/render -> genserver calls -> pubsub ->
re-render all connected liveviews -> diff serialization -> send back over websocket

the expensive part is the pub sub which fans out to all the other clients.
when one player moves, every connected liveview re-renders
its entire map. direct genserver calls would miss the rendering cost
entirely.

## how the simulated client works

each simulated player is an elixir process using websockex that pretends
to be the liveview javascript client. the join flow:

1. create user via `User.new/1` and `WorldServer.join_user/1` directly
   (same BEAM, no network for this step)
2. HTTP GET `/world?user_id=<id>` to get the rendered HTML
3. parse `phx-session`, `phx-static`, and `id` from the main liveview
   div, and `csrf-token` from the meta tag
4. extract the session cookie from the response headers -- liveview
   needs this to verify the session token on websocket connect
5. websocket connect to `/live/websocket?_csrf_token=TOKEN&vsn=2.0.0`
   with the cookie in the request headers
6. send `phx_join` with the session and static tokens
7. liveview mounts, subscribes to pubsub, starts receiving diffs

after joining, the player sends random keydown events (wasd) at the
configured move interval plus random jitter. the server validates moves
against walls so some bounce, which is realistic.

phoenix dev mode adds `data-phx-loc` attributes to HTML tags which
changes attribute ordering. the token parser handles this by not
assuming a fixed order between tag attributes.

## results

default 50x50 map, 35 mobs, 30 second duration, move interval at
server cooldown (150ms). all runs on the same machine.

### 10 players

| metric | value |
|---|---|
| renders | 7,300 |
| avg render | 14.46 ms |
| p50 render | 14.07 ms |
| p95 render | 20.31 ms |
| p99 render | 24.07 ms |
| max render | 59.71 ms |
| scheduler util | avg 21.9%, peak 27.2% |
| memory | avg 151 MB, peak 159 MB |
| mailbox depth | all zero |

### 20 players

| metric | value |
|---|---|
| renders | 17,798 |
| avg render | 33.15 ms |
| p50 render | 28.3 ms |
| p95 render | 63.34 ms |
| p99 render | 78.84 ms |
| max render | 136.15 ms |
| scheduler util | avg 53.2%, peak 55.4% |
| memory | avg 276 MB, peak 305 MB |
| mailbox depth | all zero |

### 30 players

| metric | value |
|---|---|
| renders | 25,906 |
| avg render | 52.95 ms |
| p50 render | 41.05 ms |
| p95 render | 117.51 ms |
| p99 render | 142.21 ms |
| max render | 200.79 ms |
| scheduler util | avg 63.1%, peak 73.4% |
| memory | avg 399 MB, peak 458 MB |
| mailbox depth | entity/world peaked at 1 |

## scaling observations

render time scales roughly linearly with player count. each player
added means every existing liveview has one more entity to render in
the map comprehension, and one more liveview process receiving every
broadcast.

at 30 players the p95 render is 117ms, which is well past the point
where movement feels laggy. the bottleneck is the same one identified
in [06-map_cpu_perf.md](06-map_cpu_perf.md): the map comprehension
re-runs O(map_area) on every entity change because `@entities` is
referenced inside the comprehension.

the genserver mailboxes stay near zero even at 30 players. the
genservers are not the bottleneck, the liveview rendering is.

the two-layer rendering split described in
[00-entity-layer.md](00-entity-layer.md) would help by separating the
map layer (only re-renders when `@map` changes) from the entity layer
(iterates entities, not tiles). this would change the per-move render
cost from O(map_area) to O(entity_count).

## how to reproduce

```
mix bench.load --players 20 --duration 30
```

options:
- `--players` number of simulated players (default 100)
- `--move-interval` ms between moves per player (default: server move cooldown, 150ms)
- `--duration` test duration in seconds (default 60)
- `--ramp-rate` players to connect per second during ramp-up (default 10)
- `--map-size` override map width and height (auto-scales room count and mob count)
