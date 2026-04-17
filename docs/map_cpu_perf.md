# map rendering cpu performance

baseline measurements before the two-layer rendering split described in
[entity-layer.md](entity-layer.md). these numbers represent
the current single-layer approach where the map comprehension re-runs on
every entity change.

see pr #124 for when this was done.

server-side LiveView render time at various map sizes. measured with
`mix bench.render_time` which attaches to the built-in
`[:phoenix, :live_view, :render, :stop]` telemetry event.

each run: 30 player moves, 3 mobs, single connected player.

## results

| map size | tiles | avg render | p50 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| 10x10 | 100 | 470 us | 245 us | 538 us | 13.81 ms | 13.81 ms |
| 20x20 | 400 | 871 us | 681 us | 1.3 ms | 12.42 ms | 12.42 ms |
| 50x50 | 2,500 | 3.84 ms | 3.51 ms | 6.49 ms | 7.75 ms | 19.25 ms |
| 100x100 | 10,000 | 16.2 ms | 14.92 ms | 25.72 ms | 54.21 ms | 54.21 ms |
| 200x200 | 40,000 | 62.73 ms | 60.65 ms | 98.01 ms | 227.12 ms | 227.12 ms |

## scaling

render time scales roughly linearly with tile count.

at 200x200, rendering times make the game too sluggish to play.
this is where the two-layer rendering split (issue #122) would
help by separating the map layer from the entity layer. this way
only entity changes trigger re-render.

## how to reproduce

```
mix bench.render_time --width 100 --height 100 --moves 30
```

see `mix help bench.render_time` for all options.
