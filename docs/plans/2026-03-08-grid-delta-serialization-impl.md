# GridDelta Domain Types & Wire Serialization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Define Haskell domain types for GridDelta matching the Cap'n Proto schema, implement Wire.hs serialization, and have the router relay MsgStateUpdate to attached plugs.

**Architecture:** Add `GridDelta` ADT and supporting types to `Types.hs`. Align `CellAttrs` with the 6-flag schema. Change `MsgStateUpdate` payload from `ByteString` to `GridDelta`. Implement `toWire`/`fromWire` conversion in `Wire.hs`. Router broadcasts `MsgStateUpdate` to attached plugs. TDD throughout.

**Tech Stack:** Haskell, GHC 9.6+, Cap'n Proto (capnp-haskell), HSpec, cabal

---

### Task 1: Add blink and dim to CellAttrs

**Files:**
- Modify: `src/Tank/Terminal/Grid.hs:27-35` (CellAttrs type and defaultAttrs)
- Modify: `tests/Tank/Terminal/GridSpec.hs` (update any explicit CellAttrs construction)

**Step 1: Update CellAttrs to add blink and dim fields**

In `src/Tank/Terminal/Grid.hs`, change `CellAttrs` from 4 fields to 6:

```haskell
data CellAttrs = CellAttrs
  { attrBold      :: !Bool
  , attrItalic    :: !Bool
  , attrUnderline :: !Bool
  , attrReverse   :: !Bool
  , attrBlink     :: !Bool
  , attrDim       :: !Bool
  } deriving (Eq, Show)

defaultAttrs :: CellAttrs
defaultAttrs = CellAttrs False False False False False False
```

**Step 2: Fix compilation errors from CellAttrs change**

The `CellAttrs` constructor is used positionally in Grid.hs and tests. Search for `CellAttrs` usage:

- `src/Tank/Terminal/Grid.hs:35` — `defaultAttrs` already updated in step 1
- `tests/Tank/Terminal/GridSpec.hs` — uses `defaultAttrs` (no change needed)
- `src/Tank/Plug/Terminal.hs` — search for `CellAttrs` usage in VTerm parsing

Run: `nix develop -c cabal build all 2>&1 | tail -30`
Expected: Clean compile (or identify sites needing update)

**Step 3: Run tests**

Run: `nix develop -c cabal test 2>&1 | tail -30`
Expected: All tests pass (Grid tests use `defaultAttrs`, not positional CellAttrs)

**Step 4: Commit**

```bash
git add src/Tank/Terminal/Grid.hs
git commit -m "feat: add blink and dim to CellAttrs to match Cap'n Proto schema"
```

---

### Task 2: Define GridDelta domain types

**Files:**
- Modify: `src/Tank/Core/Types.hs` (add GridDelta and supporting types)

**Step 1: Add GridDelta and supporting types to Types.hs**

Add the following types to `src/Tank/Core/Types.hs`. Add `Data.Word (Word64)` to imports. Add `Tank.Terminal.Grid (GridCell)` if not already imported (Grid is already imported for the `Grid` type). Add `Tank.Core.CRDT (ReplicaId)` to imports.

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
  , cuCell      :: !GridCell
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

Update the module export list to include: `GridDelta(..)`, `CellUpdate(..)`, `ViewportUpdate(..)`, `EpochUpdate(..)`, `GridSnapshot(..)`.

**Step 2: Build to verify compilation**

Run: `nix develop -c cabal build all 2>&1 | tail -30`
Expected: Clean compile

**Step 3: Commit**

```bash
git add src/Tank/Core/Types.hs
git commit -m "feat: add GridDelta domain types matching Cap'n Proto schema"
```

---

### Task 3: Change MsgStateUpdate payload to GridDelta

**Files:**
- Modify: `src/Tank/Core/Protocol.hs:34` (change ByteString to GridDelta)
- Modify: `src/Tank/Core/Wire.hs:99,179` (will break — fix in Task 5)
- Modify: `src/Tank/Daemon/Router.hs:95` (will break — fix in Task 6)

**Step 1: Change MsgStateUpdate in Protocol.hs**

In `src/Tank/Core/Protocol.hs`, change line 34:

```haskell
-- From:
  | MsgStateUpdate !CellId !ByteString  -- CRDT delta (serialized)
-- To:
  | MsgStateUpdate !CellId !GridDelta   -- CRDT grid delta
```

Add `GridDelta` to the import from `Tank.Core.Types`:

```haskell
import Tank.Core.Types (CellId, PlugId, PlugInfo, GridDelta)
```

Remove `Data.ByteString (ByteString)` import if `ByteString` is no longer used in this module (check — `MsgInput` and `MsgOutput` still use `ByteString`, so keep it).

**Step 2: Build — expect failures in Wire.hs and Router.hs**

Run: `nix develop -c cabal build all 2>&1 | tail -30`
Expected: Compile errors in Wire.hs (lines 99, 179) and Router.hs (line 95) — these are the stubs we'll fix in Tasks 5 and 6.

**Step 3: Temporarily stub Wire.hs and Router.hs to compile**

In `src/Tank/Core/Wire.hs` line 99, the existing stub `go (MsgStateUpdate _ _) = W.Message'error "stateUpdate not yet supported"` should still compile since `_` matches any type. Same for Router.hs line 95 with `MsgStateUpdate _cid _delta -> pure []`. If they do compile, no change needed. If not, adjust pattern matches.

Verify: `nix develop -c cabal build all 2>&1 | tail -30`

**Step 4: Run tests**

Run: `nix develop -c cabal test 2>&1 | tail -30`
Expected: All existing tests pass (no test uses MsgStateUpdate yet)

**Step 5: Commit**

```bash
git add src/Tank/Core/Protocol.hs
git commit -m "feat: change MsgStateUpdate payload from ByteString to GridDelta"
```

---

### Task 4: Write Wire.hs round-trip tests for GridDelta

**Files:**
- Modify: `tests/Tank/Core/WireSpec.hs` (add 4 new tests)

**Step 1: Write failing tests for all 4 GridDelta variants**

Add to `tests/Tank/Core/WireSpec.hs`. Need these imports:

```haskell
import Data.UUID (nil)
import Tank.Core.CRDT (ReplicaId(..))
import Tank.Core.Types (GridDelta(..), CellUpdate(..), ViewportUpdate(..), EpochUpdate(..), GridSnapshot(..))
import Tank.Terminal.Grid (GridCell(..), Color(..), CellAttrs(..), defaultAttrs, defaultCell)
```

Add these test cases inside the `describe "Wire round-trip"` block:

```haskell
  it "MsgStateUpdate with DeltaCells" $ do
    let cu = CellUpdate
              { cuAbsLine   = 5
              , cuCol       = 10
              , cuCell      = GridCell 'A' DefaultColor (Color256 1) defaultAttrs
              , cuEpoch     = 0
              , cuTimestamp = 100
              , cuReplicaId = ReplicaId nil
              }
        msg = MsgStateUpdate (CellId nil) (DeltaCells [cu])
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgStateUpdate with DeltaViewport" $ do
    let vu = ViewportUpdate
              { vuAbsLine  = 42
              , vuTimestamp = 200
              , vuReplicaId = ReplicaId nil
              }
        msg = MsgStateUpdate (CellId nil) (DeltaViewport vu)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgStateUpdate with DeltaEpoch" $ do
    let eu = EpochUpdate
              { euEpoch     = 3
              , euTimestamp  = 300
              , euReplicaId  = ReplicaId nil
              }
        msg = MsgStateUpdate (CellId nil) (DeltaEpoch eu)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgStateUpdate with DeltaSnapshot" $ do
    let cu = CellUpdate
              { cuAbsLine   = 0
              , cuCol       = 0
              , cuCell      = defaultCell
              , cuEpoch     = 1
              , cuTimestamp = 50
              , cuReplicaId = ReplicaId nil
              }
        snap = GridSnapshot
                { gsWidth       = 80
                , gsHeight      = 24
                , gsBufferAbove = 200
                , gsBufferBelow = 100
                , gsViewport    = 0
                , gsEpoch       = 1
                , gsCells       = [cu]
                }
        msg = MsgStateUpdate (CellId nil) (DeltaSnapshot snap)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)
```

**Step 2: Run tests to verify they fail**

Run: `nix develop -c cabal test 2>&1 | tail -30`
Expected: 4 new tests FAIL (Wire.hs still stubs stateUpdate)

**Step 3: Commit failing tests**

```bash
git add tests/Tank/Core/WireSpec.hs
git commit -m "test: add failing Wire round-trip tests for GridDelta variants"
```

---

### Task 5: Implement Wire.hs GridDelta serialization

**Files:**
- Modify: `src/Tank/Core/Wire.hs` (replace stubs with real serialization)

**Step 1: Add imports to Wire.hs**

Add these imports to `src/Tank/Core/Wire.hs`:

```haskell
import Data.Char (chr, ord)
import Data.Word (Word8, Word16, Word32, Word64)

import Tank.Core.CRDT (ReplicaId(..))
import Tank.Core.Types (CellId(..), PlugId(..), PlugCapability(..), PlugInfo(..), GridDelta(..), CellUpdate(..), ViewportUpdate(..), EpochUpdate(..), GridSnapshot(..))
import Tank.Terminal.Grid (GridCell(..), Color(..), CellAttrs(..))
import qualified Tank.Gen.Grid as G
import qualified Tank.Gen.Protocol as W
```

Note: `Word16` is already imported. `Word8` and `Word32` may be new. Adjust the existing import line `Data.Word (Word16, Word64)` to `Data.Word (Word8, Word16, Word32, Word64)`.

**Step 2: Implement toWire helpers for grid types**

Add these helper functions to `src/Tank/Core/Wire.hs` (in the toWire section):

```haskell
-- Grid type conversions: domain -> wire

colorToWire :: Color -> C.Parsed G.Color
colorToWire DefaultColor      = G.Color G.Color'default_
colorToWire (Color256 n)      = G.Color (G.Color'index (fromIntegral n))
colorToWire (ColorRGB r g b)  = G.Color (G.Color'rgb (G.RGB (fromIntegral r) (fromIntegral g) (fromIntegral b)))

cellAttrsToWire :: CellAttrs -> C.Parsed G.CellAttrs
cellAttrsToWire a = G.CellAttrs
  (attrBold a) (attrItalic a) (attrUnderline a)
  (attrReverse a) (attrBlink a) (attrDim a)

gridCellToWire :: GridCell -> Word64 -> Word64 -> ReplicaId -> C.Parsed G.GridCell
gridCellToWire gc epoch ts (ReplicaId rid) = G.GridCell
  (fromIntegral (ord (gcCodepoint gc)) :: Word32)
  (colorToWire (gcFg gc))
  (colorToWire (gcBg gc))
  (cellAttrsToWire (gcAttrs gc))
  epoch
  ts
  (uuidToBS rid)

cellUpdateToWire :: CellUpdate -> C.Parsed G.CellUpdate
cellUpdateToWire cu = G.CellUpdate
  (cuAbsLine cu)
  (fromIntegral (cuCol cu) :: Word16)
  (gridCellToWire (cuCell cu) (cuEpoch cu) (cuTimestamp cu) (cuReplicaId cu))

gridDeltaToWire :: GridDelta -> C.Parsed G.GridDelta
gridDeltaToWire (DeltaCells cus) =
  G.GridDelta (G.GridDelta'cells (map cellUpdateToWire cus))
gridDeltaToWire (DeltaViewport vu) =
  G.GridDelta (G.GridDelta'viewport (viewportUpdateToWire vu))
gridDeltaToWire (DeltaEpoch eu) =
  G.GridDelta (G.GridDelta'epochUpdate (epochUpdateToWire eu))
gridDeltaToWire (DeltaSnapshot snap) =
  G.GridDelta (G.GridDelta'snapshot (gridSnapshotToWire snap))

viewportUpdateToWire :: ViewportUpdate -> C.Parsed G.ViewportUpdate
viewportUpdateToWire vu = G.ViewportUpdate
  (vuAbsLine vu) (vuTimestamp vu) (uuidToBS (let ReplicaId u = vuReplicaId vu in u))

epochUpdateToWire :: EpochUpdate -> C.Parsed G.EpochUpdate
epochUpdateToWire eu = G.EpochUpdate
  (euEpoch eu) (euTimestamp eu) (uuidToBS (let ReplicaId u = euReplicaId eu in u))

gridSnapshotToWire :: GridSnapshot -> C.Parsed G.GridSnapshot
gridSnapshotToWire gs = G.GridSnapshot
  (fromIntegral (gsWidth gs) :: Word16)
  (fromIntegral (gsHeight gs) :: Word16)
  (fromIntegral (gsBufferAbove gs) :: Word16)
  (fromIntegral (gsBufferBelow gs) :: Word16)
  (gsViewport gs)
  (gsEpoch gs)
  (map cellUpdateToWire (gsCells gs))
```

**Step 3: Replace the toWire stub**

Change line 99 in `messageToWire`:

```haskell
-- From:
    go (MsgStateUpdate _ _) = W.Message'error "stateUpdate not yet supported"
-- To:
    go (MsgStateUpdate cid delta) =
      W.Message'stateUpdate (W.StateUpdate (uuidToBS (let CellId u = cid in u)) (gridDeltaToWire delta))
```

**Step 4: Implement fromWire helpers for grid types**

Add these helper functions to `src/Tank/Core/Wire.hs` (in the fromWire section):

```haskell
-- Grid type conversions: wire -> domain

colorFromWire :: C.Parsed G.Color -> Either String Color
colorFromWire (G.Color w) = case w of
  G.Color'default_  -> Right DefaultColor
  G.Color'index n   -> Right (Color256 (fromIntegral n))
  G.Color'rgb (G.RGB r g b) -> Right (ColorRGB (fromIntegral r) (fromIntegral g) (fromIntegral b))
  G.Color'unknown' n -> Left $ "unknown Color variant: " ++ show n

cellAttrsFromWire :: C.Parsed G.CellAttrs -> CellAttrs
cellAttrsFromWire (G.CellAttrs bo it ul rv bl di) =
  CellAttrs bo it ul rv bl di

gridCellFromWire :: C.Parsed G.GridCell -> Either String (GridCell, Word64, Word64, ReplicaId)
gridCellFromWire (G.GridCell cp fg bg attrs epoch ts ridBs) = do
  fg' <- colorFromWire fg
  bg' <- colorFromWire bg
  rid <- ReplicaId <$> bsToUUID ridBs
  let cell = GridCell (chr (fromIntegral cp)) fg' bg' (cellAttrsFromWire attrs)
  Right (cell, epoch, ts, rid)

cellUpdateFromWire :: C.Parsed G.CellUpdate -> Either String CellUpdate
cellUpdateFromWire (G.CellUpdate absLn col gcW) = do
  (cell, epoch, ts, rid) <- gridCellFromWire gcW
  Right CellUpdate
    { cuAbsLine   = absLn
    , cuCol       = fromIntegral col
    , cuCell      = cell
    , cuEpoch     = epoch
    , cuTimestamp = ts
    , cuReplicaId = rid
    }

viewportUpdateFromWire :: C.Parsed G.ViewportUpdate -> Either String ViewportUpdate
viewportUpdateFromWire (G.ViewportUpdate absLn ts ridBs) = do
  rid <- ReplicaId <$> bsToUUID ridBs
  Right ViewportUpdate { vuAbsLine = absLn, vuTimestamp = ts, vuReplicaId = rid }

epochUpdateFromWire :: C.Parsed G.EpochUpdate -> Either String EpochUpdate
epochUpdateFromWire (G.EpochUpdate ep ts ridBs) = do
  rid <- ReplicaId <$> bsToUUID ridBs
  Right EpochUpdate { euEpoch = ep, euTimestamp = ts, euReplicaId = rid }

gridSnapshotFromWire :: C.Parsed G.GridSnapshot -> Either String GridSnapshot
gridSnapshotFromWire (G.GridSnapshot w h ba bb vp ep cells) = do
  cells' <- traverse cellUpdateFromWire cells
  Right GridSnapshot
    { gsWidth       = fromIntegral w
    , gsHeight      = fromIntegral h
    , gsBufferAbove = fromIntegral ba
    , gsBufferBelow = fromIntegral bb
    , gsViewport    = vp
    , gsEpoch       = ep
    , gsCells       = cells'
    }

gridDeltaFromWire :: C.Parsed G.GridDelta -> Either String GridDelta
gridDeltaFromWire (G.GridDelta w) = case w of
  G.GridDelta'cells cus     -> DeltaCells <$> traverse cellUpdateFromWire cus
  G.GridDelta'viewport vu   -> DeltaViewport <$> viewportUpdateFromWire vu
  G.GridDelta'epochUpdate eu -> DeltaEpoch <$> epochUpdateFromWire eu
  G.GridDelta'snapshot snap -> DeltaSnapshot <$> gridSnapshotFromWire snap
  G.GridDelta'unknown' n    -> Left $ "unknown GridDelta variant: " ++ show n
```

**Step 5: Replace the fromWire stub**

Change line 179 in `messageFromWire`:

```haskell
-- From:
  W.Message'stateUpdate _ -> Left "stateUpdate not yet supported"
-- To:
  W.Message'stateUpdate (W.StateUpdate cidBs deltaW) -> do
    cid <- parseCellId cidBs
    delta <- gridDeltaFromWire deltaW
    Right $ MsgStateUpdate cid delta
```

**Step 6: Build**

Run: `nix develop -c cabal build all 2>&1 | tail -30`
Expected: Clean compile

**Step 7: Run tests**

Run: `nix develop -c cabal test 2>&1 | tail -30`
Expected: All tests pass, including the 4 new GridDelta round-trip tests from Task 4

**Step 8: Commit**

```bash
git add src/Tank/Core/Wire.hs
git commit -m "feat: implement Wire.hs serialization for GridDelta"
```

---

### Task 6: Router broadcasts MsgStateUpdate

**Files:**
- Modify: `src/Tank/Daemon/Router.hs:95` (change stub to Broadcast)
- Modify: `tests/Tank/Daemon/RouterSpec.hs` (add test)

**Step 1: Write failing test for MsgStateUpdate broadcast**

Add to `tests/Tank/Daemon/RouterSpec.hs`. Need these imports:

```haskell
import Tank.Core.CRDT (ReplicaId(..))
import Tank.Core.Types (GridDelta(..), CellUpdate(..), ViewportUpdate(..), EpochUpdate(..), GridSnapshot(..))
import Tank.Terminal.Grid (defaultCell, defaultAttrs)
```

Add this test case:

```haskell
  it "routes MsgStateUpdate as broadcast" $ do
    ds <- newDaemonState
    let cid = CellId nil
        delta = DeltaViewport (ViewportUpdate 10 100 (ReplicaId nil))
    result <- routeMessage ds stdin (mkEnvelope (MsgStateUpdate cid delta))
    result `shouldBe` [Broadcast cid (MsgStateUpdate cid delta)]
```

**Step 2: Run test to verify it fails**

Run: `nix develop -c cabal test 2>&1 | tail -30`
Expected: FAIL — router currently returns `[]` for MsgStateUpdate

**Step 3: Fix the router**

In `src/Tank/Daemon/Router.hs`, change line 95:

```haskell
-- From:
  MsgStateUpdate _cid _delta -> pure []
-- To:
  MsgStateUpdate cid delta ->
    pure [Broadcast cid (MsgStateUpdate cid delta)]
```

**Step 4: Run tests**

Run: `nix develop -c cabal test 2>&1 | tail -30`
Expected: All tests pass

**Step 5: Commit**

```bash
git add src/Tank/Daemon/Router.hs tests/Tank/Daemon/RouterSpec.hs
git commit -m "feat: router broadcasts MsgStateUpdate to attached plugs"
```

---

### Task 7: Add Wire round-trip test for ColorRGB and CellAttrs with blink/dim

**Files:**
- Modify: `tests/Tank/Core/WireSpec.hs` (add edge case tests)

**Step 1: Add tests for edge cases**

Add to `tests/Tank/Core/WireSpec.hs`:

```haskell
  it "MsgStateUpdate with ColorRGB and blink/dim attrs" $ do
    let attrs = CellAttrs True False True False True True  -- bold, underline, blink, dim
        cu = CellUpdate
              { cuAbsLine   = 0
              , cuCol       = 0
              , cuCell      = GridCell 'Z' (ColorRGB 255 128 0) (ColorRGB 0 0 0) attrs
              , cuEpoch     = 5
              , cuTimestamp = 999
              , cuReplicaId = ReplicaId nil
              }
        msg = MsgStateUpdate (CellId nil) (DeltaCells [cu])
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgStateUpdate with empty cells list" $ do
    let msg = MsgStateUpdate (CellId nil) (DeltaCells [])
    roundTrip msg `shouldBe` Right (mkEnvelope msg)
```

**Step 2: Run tests**

Run: `nix develop -c cabal test 2>&1 | tail -30`
Expected: All tests pass (these should pass with the Task 5 implementation)

**Step 3: Commit**

```bash
git add tests/Tank/Core/WireSpec.hs
git commit -m "test: add edge case Wire tests for ColorRGB and blink/dim attrs"
```
