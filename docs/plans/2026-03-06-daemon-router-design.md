# Daemon Router Design

## Goal

Wire up the tank daemon router so plugs can register over Unix sockets using Cap'n Proto serialization, cells can be created and attached, and messages flow between plugs.

## Context

The daemon (`src/Tank/Daemon/`) has all the scaffolding — Unix socket listener, STM-based state management, CRDT types — but the router drops all messages and the accept loop immediately closes client connections. The Cap'n Proto schema (`schema/protocol.capnp`) defines 15 message types but no Haskell serialization exists.

## Architecture

**Protocol-first**: Fix `haskell-capnp` for GHC 9.10, generate Haskell types from schema, replace hand-written `Protocol.hs`, build wire layer, then implement router handlers.

### Nix Integration

- Fetch `haskell-capnp` from GitHub (pinned rev) in `flake.nix`
- Apply `DuplicateRecordFields` pragma patch to `GenHelpers/Rpc.hs` (only GHC 9.10 fix needed)
- Use `doJailbreak` to relax upper bounds (ghc-prim, containers, text, bytestring, primitive, template-haskell)
- Add `capnpc-haskell` to devShell for schema-to-Haskell codegen

### Wire Protocol

- **Generated types**: `src/Tank/Gen/Protocol.hs` and `src/Tank/Gen/Grid.hs` — checked into git, regenerated manually when schema changes
- **Remove**: `src/Tank/Core/Protocol.hs` — replaced by generated `C.Parsed` types
- **Keep**: `src/Tank/Core/Types.hs` — domain types (CellId, PlugId, Cell, PlugInfo) with conversions to/from Cap'n Proto parsed types
- **Framing**: Cap'n Proto's built-in segment framing (`Capnp.IO.hGetMsg` / `Capnp.IO.hPutMsg`)
- **Socket.hs**: Add `readEnvelope` / `writeEnvelope` wrappers

### Client Handler Threads

- `acceptLoop` spawns a handler thread per client via `forkIO`
- Handler: `Socket` → `Handle` → read loop → `routeMessage` → write responses
- On disconnect: `removePlug` cleanup
- Track threads in DaemonState for clean shutdown

### Router Implementation (Phased)

**Phase 1 — Plug lifecycle:**
- `plugRegister`: Store `PlugConn` in `dsPlugs`, respond `plugRegistered`
- `plugDeregister`: Remove from `dsPlugs`, detach from all cells

**Phase 2 — Cell lifecycle:**
- `cellCreate`: Create `Cell` with empty `Grid`, add to `dsCells`
- `cellDestroy`: Remove from `dsCells`, notify attached plugs
- `cellAttach`: Add plug to cell's `cellPlugs` set
- `cellDetach`: Remove plug from cell's `cellPlugs` set

**Phase 3 — I/O routing:**
- `input`: Forward to PTY-owning plug for this cell
- `output`: Broadcast to all attached plugs
- `listCells`: Return all cells

**Phase 4 — State sync (future, not in scope):**
- `stateUpdate`: Merge CRDT delta, broadcast

### Testing

- Unit: Router handlers with mock state
- Integration: Daemon + two clients, register → create cell → attach → send messages
- Wire format: Serialize/deserialize round-trip per message type

## Key Decisions

1. **haskell-capnp fix**: Only 1 source fix needed (DuplicateRecordFields in GenHelpers/Rpc.hs) + doJailbreak for bounds
2. **Check in generated code**: No build-time codegen dependency, regenerate manually
3. **Cap'n Proto framing**: Use library's built-in segment I/O, no custom framing
4. **STM for state**: Router mutations in STM transactions, I/O outside
5. **Phase 4 deferred**: CRDT state sync is out of scope for this task (grid.capnp types need separate integration work)
