# Performance Enhancement: Don't iterate every map tile

## The problem

The current template renders the map as one big nested comprehension:

```heex
<%= for y <- 0..height, x <- 0..width do %>
  <span>
    <%= cond do %>
      <% mob_here?(@entities, {x,y}) -> %> ...mob symbol...
      <% player_here?(@entities, {x,y}) -> %> ...player symbol...
      <% true -> %> <%= tile_char(@map[{x,y}]) %>
    <% end %>
  </span>
<% end %>
```

The body references `@entities`. So on every entity move, LiveView invalidates
the whole comprehension and re-runs it: on a 150×150 map that's over 22k cond
evaluations and ~45k lookups into `@entities`, every single move.

The LiveView over-the-wire diff is still only proportional to entity
count (not map area), but the server-side CPU cost scales with `map_area`, and
possibly with `map_area × entities` if `mob_symbol_at` / `players_at` scan the
entity list.

## Improvement

Split rendering into two layers. Map layer iterates coordinates; entity layer
iterates entities. Overlay with CSS grid.

```heex
<div class="map-layer">
  <%= for y <- 0..height, x <- 0..width do %>
    <span class={"tile-#{@map[{x,y}]}"}><%= tile_char(@map[{x,y}]) %></span>
  <% end %>
</div>

<div class="entity-layer">
  <%= for {id, e} <- @entities do %>
    <span style={"grid-area: #{e.y} / #{e.x}"} id={"e-#{id}"}>
      <%= e.symbol %>
    </span>
  <% end %>
</div>
```

Map layer references only `@map`. Entity layer references only `@entities`.

## Why it works

On entity moves:

- Map layer comprehension is skipped entirely. LiveView's change tracker
  sees `@map` hasn't changed, marks the comprehension clean, doesn't run it.
  The 22k cell loop stops happening on every move.
- Entity layer re-evaluates, but it has N iterations (one per entity),
  not `map_area` iterations.
- No per-cell lookup into `@entities`. The entity layer iterates entities
  directly. If `mob_symbol_at`/`players_at` were O(entities) scans, the current
  cost is O(map_area × entities); after the split it's O(entities).

## Status

Haven't done the work yet. Would be nice to get some benchmarks first, mostly on
the CPU side to make sure we can see the improvements.
