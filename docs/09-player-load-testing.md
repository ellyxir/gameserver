# player load testing

baseline measurements of server behavior under concurrent player load.
measured with `mix bench.load` which connects simulated players over
real websockets to the liveview, joins the game, and moves around.

see issue #125 and pr #126 for when this was built.

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

## results - single layer

default 50x50 map, 35 mobs, 30 second duration, move interval at
server cooldown (150ms). all runs on the same machine.

| metric | 10 players | 20 players | 30 players |
|---|---|---|---|
| renders | 7,349 | 17,492 | 25,918 |
| avg render | 14.4 ms | 32.9 ms | 53.63 ms |
| p50 render | 14.1 ms | 27.93 ms | 41.58 ms |
| p95 render | 19.94 ms | 63.72 ms | 119.97 ms |
| p99 render | 22.66 ms | 81.74 ms | 143.78 ms |
| max render | 31.98 ms | 118.82 ms | 203.07 ms |
| avg round-trip | 10.96 ms | 6,817 ms | 11,957 ms |
| p50 round-trip | 8.86 ms | 6,003 ms | 9,026 ms |
| p95 round-trip | 31.41 ms | 17,038 ms | 33,526 ms |
| p99 round-trip | 46.46 ms | 18,509 ms | 37,733 ms |
| max round-trip | 64.6 ms | 19,709 ms | 39,920 ms |
| scheduler util | avg 22.5%, peak 26% | avg 53.5%, peak 55.7% | avg 61.4%, peak 68.1% |
| memory | avg 156 MB, peak 165 MB | avg 277 MB, peak 300 MB | avg 405 MB, peak 438 MB |
| mailbox depth | all zero | entity/world peaked at 1 | entity/world peaked at 2 |

at 10 players, round-trip stays under 65ms. responsive movement.

at 20 players, the server renders fast enough (33ms avg) but the
liveview process mailboxes queue up faster than they drain. a player's
keypress waits 6 seconds on average before the server processes it.
the browser accumulates a backlog of diffs that plays out long after
the events were sent.

at 30 players, 12 second average round-trip, p99 at 40 seconds.

## scaling observations

render time scales roughly linearly with player count. each player
added means every existing liveview has one more entity to render in
the map comprehension, and one more liveview process receiving every
broadcast.

the gap between render time and round-trip grows rapidly with more players.
at 10 players, render is 14ms and round-trip is 11ms, which is reasonable.
at 20 players, render is 33ms but round-trip is 6.8 seconds -- the liveview
processes can't drain their mailboxes fast enough. each move generates 20 pubsub
broadcasts (one per connected liveview), and each broadcast triggers a full
O(map_area) re-render. the renders pile up in the liveview process mailboxes.

the genserver mailboxes stay near zero even at 30 players. the
genservers are not the bottleneck, the liveview rendering is.

the two-layer rendering split described in
[00-entity-layer.md](00-entity-layer.md) would help by separating the
map layer (only re-renders when `@map` changes) from the entity layer
(iterates entities, not tiles). this would change the per-move render
cost from O(map_area) to O(entity_count).

## results - two layer (issue #122)

same setup. the map template was split into a static map layer
(iterates @map_cells) and an absolutely-positioned entity layer
(iterates @entities). liveview skips the map comprehension entirely
when only entities change.

| metric | 10 players | 20 players | 30 players |
|---|---|---|---|
| renders | 518 | 1,421 | 3,656 |
| avg render | 1.15 ms | 1.93 ms | 3.06 ms |
| p50 render | 262 us | 733 us | 1.84 ms |
| p95 render | 5.93 ms | 6.89 ms | 9.79 ms |
| p99 render | 11.71 ms | 9.31 ms | 12.83 ms |
| max render | 16.94 ms | 16.02 ms | 18.57 ms |
| avg round-trip | 1.02 ms | 1.36 ms | 2.32 ms |
| p50 round-trip | 714 us | 927 us | 1.72 ms |
| p95 round-trip | 1.25 ms | 4.58 ms | 6.68 ms |
| p99 round-trip | 10.91 ms | 10.92 ms | 13.33 ms |
| max round-trip | 24.01 ms | 25.32 ms | 31.66 ms |
| scheduler util | avg 0.5%, peak 0.6% | avg 2.5%, peak 2.9% | avg 12.6%, peak 14.7% |
| memory | avg 118.9 MB, peak 132.0 MB | avg 167.7 MB, peak 172.1 MB | avg 211.8 MB, peak 219.4 MB |
| mailbox depth | all zero | all zero | all zero |

at 20 players, avg render dropped from 32.9ms to 1.93ms (17x).
avg round-trip dropped from 6.8 seconds to 1.4ms. the mailbox
backup problem is gone, liveview processes drain instantly.

at 30 players, avg round-trip is 2.3ms vs 12 seconds before.
scheduler utilization dropped from 61% to 13%.

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
