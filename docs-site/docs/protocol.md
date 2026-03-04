# Protocol

## Wire Format

Tank uses **Cap'n Proto** for binary serialization. The schema files in
`schema/` are the source of truth.

- `schema/protocol.capnp` — message envelope, plug/cell lifecycle, queries
- `schema/grid.capnp` — terminal grid CRDT types

Cap'n Proto was chosen for:

- **Zero-copy reads**: no decode step, read directly from the buffer
- **Mutable messages**: update CRDT cells in-place
- **Canonical form**: byte-level equality for convergence checks
- **Cache-friendly**: fixed-offset field access (no vtable indirection)

## Message Envelope

Every message has:

| Field | Type | Description |
|-------|------|-------------|
| version | UInt16 | Protocol version |
| sourceId | Data (16 bytes) | Source plug UUID |
| target | Target | Cell ID, plug ID, or broadcast |
| sequence | UInt64 | Lamport clock for causal ordering |
| payload | Message | The actual message content |

## Message Types

### Control (reliable delivery)

| Message | Direction | Description |
|---------|-----------|-------------|
| `plugRegister` | plug → daemon | Register plug with capabilities |
| `plugRegistered` | daemon → plug | Confirm registration |
| `cellCreate` | plug → daemon | Create a new cell |
| `cellDestroy` | plug → daemon | Destroy a cell |
| `cellAttach` | daemon → plug | Assign plug to a cell |
| `cellDetach` | daemon → plug | Remove plug from a cell |
| `listCells` | plug → daemon | Query active cells |
| `listCellsResp` | daemon → plug | List of cells |

### State (CRDT sync, tolerates loss/reorder)

| Message | Direction | Description |
|---------|-----------|-------------|
| `stateUpdate` | bidirectional | CRDT delta for a cell |

### Data (bulk)

| Message | Direction | Description |
|---------|-----------|-------------|
| `input` | plug → daemon | Keyboard input for a cell |
| `output` | daemon → plug | PTY output from a cell |
| `fetchLines` | plug → daemon | Request scrollback lines |
| `fetchLinesResp` | daemon → plug | Scrollback line content |

## Plug Lifecycle

```
Plug                          Tank Daemon
 │                                 │
 │──── PlugRegister ──────────────>│
 │<─── PlugRegistered ─────────────│
 │                                 │
 │<─── CellAttach(cell_id) ────────│
 │──── StateUpdate(cell_id, delta)>│
 │<─── StateUpdate(cell_id, delta) │
 │                                 │
 │<─── CellDetach(cell_id) ────────│
 │──── PlugDeregister ────────────>│
```
