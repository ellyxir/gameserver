# map rendering performance

## how to measure

see mix task `Mix.Tasks.Bench.DiffSize`:
```
mix bench.diff_size --moves 30
```
uses playwright to hook the liveview websocket, join the game, move around,
and report the size of every diff message the server sends.

## what we found

the question was: when one player moves on a 30x30 map (900 spans), does
liveview re-send the entire map or just the tiles that changed?

short answer: just the changed tiles.

### baseline numbers (30x30 map, 3 mobs, 1 player)

| metric | value |
|---|---|
| idle traffic | 0 bytes/sec (mobs dont wander, no background diffs) |
| event reply size | ~80-110 bytes (empty ack for the keydown) |
| player move diff | ~850 bytes (includes template fragments for branch switch) |
| mob/entity diff | ~350 bytes (just the changed cell dynamics) |
| diffs per move | ~2.4-3.0 |
| avg diff size | ~530 bytes |

### why a player move diff is bigger than a mob diff

the template uses a `cond` with branches for player, mob, other-player, and
floor. when the player moves, the old tile switches from the player branch to
the floor branch, and the new tile does the opposite. liveview sends two new
template fragments in a `"p"` key because the static html changed (different
classes, different data attributes). mob cells stay in the same branch so
liveview only sends the changed dynamic value (the mob symbol character).

### why mobs appear in the diff even when they didnt move

every cell in the template calls `Entities.mob_symbol_at(@entities, {x, y})`.
when the player moves, `@entities` gets reassigned. liveview tracks which
dynamic slots depend on which assigns at the slot level. since `mob_symbol`
depends on `@entities` and `@entities` changed, liveview re-sends the mob
symbol value for every mob cell -- even though the value is still `"r"`.

it does NOT re-send floor tiles though, because `{char}` depends on
`@map_cells` which didnt change. so liveview's slot-level tracking is
doing real work here.

### what this means for scaling

- **server cpu**: O(map_area) per move. all 900 cond evaluations re-run every
  time any entity moves because `@entities` is referenced inside the
  comprehension. the map size is the bottleneck for server-side render cost.

- **wire cost**: O(entity_count) per move. only cells whose dynamic slot
  values actually changed get sent. more mobs = more bytes per diff, but
  linearly. bigger map with the same number of mobs = same diff size.

- **idle cost**: zero. mobs only have attack ai, no wandering. if mob
  wandering is added (pr4 in roadmap), each mob move will generate a diff
  broadcast to every connected liveview.

### not yet tested

- how big can the map get before server-side re-render time is noticeable?
- how many mobs before diff size becomes a problem?
- does the mount payload (initial full render) scale with map area?
- multiple connected players multiplying the pubsub fanout

