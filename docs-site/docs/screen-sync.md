# Terminal Screen Sync

Tank's terminal screen synchronization uses three innovations over traditional
approaches (like SSH's byte stream or mosh's state sync).

## Problem

Two types of updates flow between tanks for a terminal cell:

1. **Content updates**: cell at position (row, col) changed
2. **Viewport position**: the screen scrolled (new output pushed lines up)

These can arrive **out of order** over unreliable transports. Traditional
approaches either require reliable delivery (SSH/TCP) or sacrifice scrollback
(mosh).

## Solution 1: Spatial Jitter Buffer

All cell positions use **absolute line numbers** — a monotonically increasing
u64. The CRDT syncs a bounded window around the viewport.

```
absolute
line
numbers
  │
  │   line A-B   ─┐
  │   ...         ├─ hidden ABOVE (CRDT, ~200 lines)
  │   line A-1   ─┘  instant scroll-up, no fetch needed
  │
  │   line A     ─┐
  │   ...         ├─ LIVE SCREEN (CRDT, terminal height)
  │   line A+H-1 ─┘  what the user sees
  │
  │   line A+H   ─┐
  │   ...         ├─ hidden BELOW (CRDT, ~100 lines)
  │   line A+H+J ─┘  jitter buffer for early content
  │
  ▼  A increases monotonically
```

**How out-of-order delivery is handled:**

- Content arrives before viewport update → drawn in hidden-below buffer,
  viewport catches up later
- Viewport update arrives before content → viewport moves, content fills in
  when it arrives
- Scroll-up (small) → data already in hidden-above buffer, instant
- Scroll-up (large) → fetch from cold scrollback via control message

Lines aging out of hidden-above are frozen into an append-only scrollback
log (not CRDT, fetched on demand).

## Solution 2: Epoch-Based Clear Screen

Clear screen (ESC[2J) is a destructive operation. Naively blanking every cell
would be O(W×H) CRDT operations.

Instead, each grid has an **epoch** counter:

```
Clear screen → increment epoch (one CRDT operation)
Cell write   → tag with current epoch

Display rule:
  cell.epoch < grid.epoch  →  stale, show blank
  cell.epoch == grid.epoch →  current, display
  cell.epoch > grid.epoch  →  future, keep (epoch will catch up)
```

**O(1)** clear screen, correct regardless of arrival order. Old-epoch cells
are lazily treated as blank.

## Solution 3: Absolute Line Addressing

Every cell in the grid is addressed by `(absolute_line, column)` where
`absolute_line` is a u64 that only increases. The viewport position is
an independent CRDT value pointing to the current top of the visible screen.

This decouples content placement from viewport position, allowing both to
arrive in any order on any transport.

## CRDT Properties

The terminal grid uses these CRDT types:

| Component | CRDT | Merge rule |
|-----------|------|------------|
| Each cell | Epoch-tagged LWW | Higher epoch wins, then higher timestamp |
| Viewport | LWW (monotonic) | Higher timestamp wins |
| Epoch | LWW (monotonic) | Higher timestamp wins |

All three are commutative, associative, and idempotent — the CRDT
convergence guarantees. Two replicas will always converge to the same
state regardless of message order or duplication.

## Comparison

| Feature | SSH | mosh | Tank |
|---------|-----|------|------|
| Transport | TCP (reliable) | UDP (unreliable) | Any (CRDT) |
| Scrollback | Via terminal | None | Full (jitter buffer + log) |
| Screen model | Byte stream | State sync | CRDT state sync |
| Clear screen | N/A (stream) | Overwrite all | O(1) epoch |
| Ordering | TCP guarantees | SSP handles | CRDTs handle |
| IP roaming | Breaks | Single-packet | QUIC or reconnect |
