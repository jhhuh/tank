# I/O Routing & Plug Registration Design

## Goal

Make the daemon router fully functional: plugs register with their Handle stored in state, MsgInput forwards to the PTY-owning plug, MsgOutput broadcasts to all attached plugs.

## Context

The daemon router (completed in the previous task) handles plug/cell lifecycle and queries, but I/O routing is stubbed (`MsgInput`/`MsgOutput` return `Nothing`). Additionally, `MsgPlugRegister` returns an ack but doesn't store the PlugConn because `routeMessage` lacked access to the client Handle.

## Architecture

**Approach A: Expand routeMessage return type**

Instead of `Maybe Message` (one response to sender), `routeMessage` returns `[RouteAction]` — a list of routing decisions. The caller (`handleClient` in Main.hs) dispatches each action to the appropriate handle.

### RouteAction type

```haskell
data RouteAction
  = Reply Message              -- respond to sender
  | SendTo PlugId Message      -- send to specific plug
  | Broadcast CellId Message   -- send to all plugs attached to cell
```

### routeMessage signature change

```haskell
routeMessage :: DaemonState -> Handle -> MessageEnvelope -> IO [RouteAction]
```

The Handle parameter lets `MsgPlugRegister` store the PlugConn in state.

### PTY ownership

Add `cellPtyOwner :: !(Maybe PlugId)` to `Cell`. Set by `MsgCellCreate` (the creating plug becomes PTY owner).

### Handler behavior

| Message | Action |
|---------|--------|
| `MsgPlugRegister info` | Store `PlugConn info handle` in dsPlugs, return `[Reply (MsgPlugRegistered pid)]` |
| `MsgPlugDeregister pid` | Remove plug, detach from cells, return `[]` |
| `MsgCellCreate cid dir` | Create cell with `cellPtyOwner = Just (meSource envelope)`, return `[]` |
| `MsgCellDestroy cid` | Remove cell, return `[]` |
| `MsgCellAttach/Detach` | Update cellPlugs set, return `[]` |
| `MsgListCells` | `[Reply (MsgListCellsResponse cells)]` |
| `MsgInput cid bytes` | `[SendTo ptyOwner (MsgInput cid bytes)]` — forward to PTY owner |
| `MsgOutput cid bytes` | `[Broadcast cid (MsgOutput cid bytes)]` — send to all attached plugs |
| `MsgStateUpdate` | Deferred (return `[]`) |
| Response messages | Ignored (return `[]`) |

### Dispatch in handleClient

`handleClient` calls `routeMessage`, iterates over `[RouteAction]`, writes each to the appropriate handle by looking up `PlugConn` in `dsPlugs`.

### State.hs additions

- `lookupPlug :: DaemonState -> PlugId -> STM (Maybe PlugConn)` — find a plug's connection
- `getCellPlugs :: DaemonState -> CellId -> STM (Set PlugId)` — get plugs attached to a cell

### Testing

- Router tests verify returned `[RouteAction]` values (no real sockets needed)
- Integration test: two clients, one sends MsgOutput, other receives it

## Key Decisions

1. **RouteAction list** over direct I/O in router — clean separation, testable
2. **PTY owner on Cell** — simplest ownership model, set at creation time
3. **No channels** — YAGNI; direct handle writes sufficient for now
4. **Handle in routeMessage** — enables plug registration to store PlugConn
