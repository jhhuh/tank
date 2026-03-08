# GridDelta Domain Types & Wire Serialization Design

## Goal

Define Haskell domain types for GridDelta (matching the Cap'n Proto schema), implement Wire.hs serialization, and have the router relay MsgStateUpdate to attached plugs.

## Context

The Cap'n Proto schema (`schema/grid.capnp`) defines a `GridDelta` union with four variants: cell updates, viewport updates, epoch updates, and full snapshots. The generated Haskell code (`Tank.Gen.Grid`) exists. But:
- No Haskell domain types for GridDelta
- Wire.hs stubs MsgStateUpdate with an error
- Router silently ignores MsgStateUpdate
- CellAttrs has 4 flags; schema has 6 (missing blink, dim)

## Architecture

**Approach: Proper domain types.** Define a `GridDelta` ADT in Types.hs matching the schema union. Change `MsgStateUpdate !CellId !ByteString` to `MsgStateUpdate !CellId !GridDelta`. Wire.hs converts between domain types and Cap'n Proto generated types. Router broadcasts MsgStateUpdate to attached plugs (simple relay, no merge).

### Domain types (Types.hs)

```haskell
data GridDelta
  = DeltaCells ![CellUpdate]
  | DeltaViewport !ViewportUpdate
  | DeltaEpoch !EpochUpdate
  | DeltaSnapshot !GridSnapshot
  deriving (Eq, Show)

data CellUpdate = CellUpdate
  { cuAbsLine   :: !Word64
  , cuCol       :: !Int
  , cuCell      :: !GridCell       -- from Grid.hs
  , cuEpoch     :: !Word64
  , cuTimestamp :: !Word64
  , cuReplicaId :: !ReplicaId
  } deriving (Eq, Show)

data ViewportUpdate = ViewportUpdate
  { vuAbsLine   :: !Word64
  , vuTimestamp  :: !Word64
  , vuReplicaId  :: !ReplicaId
  } deriving (Eq, Show)

data EpochUpdate = EpochUpdate
  { euEpoch     :: !Word64
  , euTimestamp  :: !Word64
  , euReplicaId  :: !ReplicaId
  } deriving (Eq, Show)

data GridSnapshot = GridSnapshot
  { gsWidth       :: !Int
  , gsHeight      :: !Int
  , gsBufferAbove :: !Int
  , gsBufferBelow :: !Int
  , gsViewport    :: !Word64
  , gsEpoch       :: !Word64
  , gsCells       :: ![CellUpdate]
  } deriving (Eq, Show)
```

### CellAttrs alignment (Grid.hs)

Add `attrBlink :: !Bool` and `attrDim :: !Bool` to `CellAttrs` to match the Cap'n Proto schema's 6-flag definition.

### Protocol.hs change

```haskell
-- Change:
| MsgStateUpdate !CellId !ByteString
-- To:
| MsgStateUpdate !CellId !GridDelta
```

### Wire.hs serialization

Convert between domain types and `Tank.Gen.Grid` Cap'n Proto types:
- `GridCell` ↔ CP GridCell (Char as UInt32, Color union, CellAttrs with 6 flags)
- `CellUpdate` ↔ CP CellUpdate
- `GridDelta` union ↔ CP GridDelta union
- `ViewportUpdate`, `EpochUpdate`, `GridSnapshot` ↔ CP equivalents
- UUID-based ReplicaId ↔ 16-byte Data field

### Router change

```haskell
MsgStateUpdate cid delta ->
  pure [Broadcast cid (MsgStateUpdate cid delta)]
```

Simple relay — no grid merge yet.

### Testing

- Wire round-trip tests for all 4 GridDelta variants
- Router test for MsgStateUpdate broadcast
- Update existing Grid tests for new CellAttrs fields

## Key Decisions

1. **Domain types over raw bytes** — type safety, pattern matchable, testable
2. **CellAttrs alignment** — match schema now to avoid mismatch bugs in Wire.hs
3. **Router relay only** — no grid merge yet (YAGNI for current use case)
4. **Codepoint as Char** — Wire.hs converts UInt32 ↔ Char via fromEnum/toEnum
5. **ReplicaId as UUID** — consistent with existing CRDT.hs
