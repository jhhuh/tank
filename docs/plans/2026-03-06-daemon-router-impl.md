# Daemon Router Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire up the tank daemon so plugs can register, cells can be created/attached, and messages flow over Unix sockets using Cap'n Proto serialization.

**Architecture:** Fix haskell-capnp for GHC 9.10, generate types from schema, add wire conversion layer between domain ADTs and Cap'n Proto parsed types, implement message framing in Socket.hs, spawn per-client handler threads, then implement router handlers for all message types.

**Tech Stack:** Haskell (GHC 9.10.3), capnp (haskell-capnp 0.18.0.0 with GHC 9.10 patches), Nix flakes, HSpec

**Prior work:**
- Design: `docs/plans/2026-03-06-daemon-router-design.md`
- Schema source of truth: `schema/protocol.capnp`, `schema/grid.capnp`
- Existing domain types: `src/Tank/Core/Types.hs`, `src/Tank/Core/Protocol.hs`
- Existing daemon: `src/Tank/Daemon/Main.hs`, `src/Tank/Daemon/State.hs`, `src/Tank/Daemon/Router.hs`, `src/Tank/Daemon/Socket.hs`

**Key design decisions:**
- Domain ADTs (`Core/Protocol.hs`) stay as the router's internal types — clean pattern matching, no capnp dependency in router logic
- Wire conversion isolated in `Core/Wire.hs` — converts between domain `MessageEnvelope` and `C.Parsed` Cap'n Proto types
- Socket layer reads/writes Cap'n Proto framed messages, converts to/from domain types
- Generated Cap'n Proto Haskell files checked into `src/Tank/Gen/`
- haskell-capnp fixed via Nix overlay: `doJailbreak` + `DuplicateRecordFields` patch

---

### Task 1: Fix haskell-capnp in Nix flake

Add haskell-capnp as a dependency with GHC 9.10 compatibility fixes.

**Files:**
- Modify: `flake.nix`

**Step 1: Update flake.nix to add capnp with doJailbreak and source patch**

The haskell-capnp library (0.18.0.0) doesn't build on GHC 9.10 due to:
1. Tight upper bounds on ghc-prim, containers, text, bytestring, primitive, template-haskell
2. One actual code error: `Capnp.GenHelpers.Rpc` needs `DuplicateRecordFields` pragma

Fix with Nix's `doJailbreak` (relaxes all bounds) and `appendPatch` or inline source override.

```nix
# In flake.nix, update haskellPackages override:
haskellPackages = pkgs.haskellPackages.override {
  overrides = hself: hsuper: {
    tank = hself.callCabal2nix "tank" ./. {};
    tank-layout = hself.callCabal2nix "tank-layout" ./tank-layout {};

    # Fix haskell-capnp for GHC 9.10:
    # - doJailbreak: relax upper bounds (ghc-prim, containers, text, etc.)
    # - overrideSrc or appendPatch: add DuplicateRecordFields to GenHelpers/Rpc.hs
    capnp = pkgs.haskell.lib.doJailbreak (hsuper.capnp.overrideAttrs (old: {
      patches = (old.patches or []) ++ [
        (pkgs.writeText "ghc910-dup-record-fields.patch" ''
          --- a/lib/Capnp/GenHelpers/Rpc.hs
          +++ b/lib/Capnp/GenHelpers/Rpc.hs
          @@ -1,6 +1,7 @@
           {-# LANGUAGE DataKinds #-}
          +{-# LANGUAGE DuplicateRecordFields #-}
           {-# LANGUAGE FlexibleContexts #-}
           {-# LANGUAGE TypeFamilies #-}
        '')
      ];
    }));
  };
};
```

**Note:** The exact patch mechanism may need adjustment — `overrideAttrs` vs `overrideCabal` vs `appendPatch`. Try `overrideAttrs` first; if that doesn't work, try:
```nix
capnp = pkgs.haskell.lib.doJailbreak (
  pkgs.haskell.lib.appendPatch hsuper.capnp ./patches/capnp-ghc910.patch
);
```

Also add `capnpc-haskell` is NOT needed in devShell since we're checking in generated code. But `capnproto` (the C++ tool) is already in devShell.

**Step 2: Add capnp to tank.cabal build-depends**

In `tank.cabal`, add to the library's `build-depends`:
```
    , capnp          >= 0.18  && < 1
```

**Step 3: Verify the build**

Run: `nix develop -c cabal build all`
Expected: Builds successfully (capnp library compiles with GHC 9.10)

**Step 4: Commit**

```bash
git add flake.nix tank.cabal
git commit -m "build: add haskell-capnp dependency with GHC 9.10 fixes"
```

---

### Task 2: Generate and check in Cap'n Proto Haskell types

Run the capnp code generator on our schema files and check the output into the repo.

**Files:**
- Create: `src/Tank/Gen/Protocol.hs`
- Create: `src/Tank/Gen/Grid.hs`
- Create: `src/Tank/Gen/ById/*.hs` (generated ID-based modules)
- Modify: `tank.cabal` (add Gen modules to exposed-modules)

**Step 1: Generate Haskell types from schema**

First, build the capnpc-haskell code generator:
```bash
# If capnpc-haskell is available via nix (from the capnp package):
nix develop -c bash -c "mkdir -p src/Tank/Gen && cd src/Tank && capnp compile -ohaskell ../../schema/protocol.capnp -I ../../schema --src-prefix=../../schema"
```

If `capnpc-haskell` isn't on PATH, build it from the haskell-capnp source:
```bash
cd /tmp/haskell-capnp && nix develop /path/to/tank -c cabal build exe:capnpc-haskell --allow-newer
```
Then use the built binary path with `capnp compile -o /path/to/capnpc-haskell`.

The codegen produces:
- `Capnp/Gen/Protocol.hs` — all protocol message types
- `Capnp/Gen/Grid.hs` — grid CRDT types (imported by Protocol.hs as `Capnp.Gen.ById.Xa3e8f1b2c4d56789`)
- `Capnp/Gen/ById/X*.hs` — ID-based re-exports

**Step 2: Move generated files into `src/Tank/Gen/`**

The generated files use `module Capnp.Gen.Protocol`. We need to rename them to `Tank.Gen.Protocol` etc:
- `Capnp/Gen/Protocol.hs` → `src/Tank/Gen/Protocol.hs` (update module declaration)
- `Capnp/Gen/ById/Xb7c5e3a9f1d24680.hs` → `src/Tank/Gen/ById/Xb7c5e3a9f1d24680.hs` (protocol ID)
- `Capnp/Gen/ById/Xa3e8f1b2c4d56789.hs` → `src/Tank/Gen/ById/Xa3e8f1b2c4d56789.hs` (grid ID)

Update `module` declarations and `import` paths from `Capnp.Gen.*` to `Tank.Gen.*`.

**Step 3: Add modules to tank.cabal**

```cabal
  exposed-modules:
    -- ... existing ...
    Tank.Gen.Protocol
    Tank.Gen.Grid
    Tank.Gen.ById.Xb7c5e3a9f1d24680
    Tank.Gen.ById.Xa3e8f1b2c4d56789
```

**Step 4: Verify the build**

Run: `nix develop -c cabal build all`
Expected: Builds with generated modules compiling against capnp library

**Step 5: Commit**

```bash
git add src/Tank/Gen/ tank.cabal
git commit -m "feat: add generated Cap'n Proto Haskell types from schema"
```

---

### Task 3: Wire conversion layer (domain ↔ Cap'n Proto)

Create `Core/Wire.hs` with functions to convert between domain types (`Core/Protocol.hs` ADTs) and Cap'n Proto generated parsed types.

**Files:**
- Create: `src/Tank/Core/Wire.hs`
- Create: `tests/Tank/Core/WireSpec.hs`
- Modify: `tank.cabal` (add module + test deps)

**Step 1: Write failing round-trip tests**

```haskell
-- tests/Tank/Core/WireSpec.hs
module Tank.Core.WireSpec (spec) where

import Test.Hspec
import Data.UUID (nil)
import Tank.Core.Types (CellId(..), PlugId(..))
import Tank.Core.Protocol
import Tank.Core.Wire (toWire, fromWire)

spec :: Spec
spec = describe "Wire conversion" $ do
  it "round-trips MsgListCells" $ do
    let env = MessageEnvelope 1 (PlugId nil) TargetBroadcast 42 MsgListCells
    fromWire (toWire env) `shouldBe` Right env

  it "round-trips MsgPlugRegister" $ do
    let info = PlugInfo (PlugId nil) "test" mempty
        env = MessageEnvelope 1 (PlugId nil) TargetBroadcast 1 (MsgPlugRegister info)
    fromWire (toWire env) `shouldBe` Right env

  it "round-trips MsgCellCreate" $ do
    let env = MessageEnvelope 1 (PlugId nil) (TargetCell (CellId nil)) 1
              (MsgCellCreate (CellId nil) "/tmp")
    fromWire (toWire env) `shouldBe` Right env
```

**Step 2: Run tests to verify they fail**

Run: `nix develop -c cabal test tank-tests`
Expected: FAIL (module not found)

**Step 3: Implement Wire.hs**

```haskell
-- src/Tank/Core/Wire.hs
module Tank.Core.Wire
  ( toWire
  , fromWire
  ) where

import qualified Data.ByteString as BS
import Data.UUID (UUID, toByteString, fromByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64)
import Data.Set (Set)
import qualified Data.Set as Set

import Tank.Core.Types
import Tank.Core.Protocol
import qualified Tank.Gen.Protocol as CP
import qualified Capnp.Classes as C

-- Convert domain MessageEnvelope to Cap'n Proto parsed type
toWire :: MessageEnvelope -> C.Parsed CP.MessageEnvelope
toWire (MessageEnvelope ver src tgt seq_ payload) = CP.MessageEnvelope
  { CP.version  = fromIntegral ver
  , CP.sourceId = uuidToBS (unPlugId src)
  , CP.target   = targetToWire tgt
  , CP.sequence = seq_
  , CP.payload  = payloadToWire payload
  }

-- Convert Cap'n Proto parsed type to domain MessageEnvelope
fromWire :: C.Parsed CP.MessageEnvelope -> Either String MessageEnvelope
fromWire cp = do
  src <- bsToPlugId (CP.sourceId cp)
  tgt <- targetFromWire (CP.target cp)
  payload <- payloadFromWire (CP.payload cp)
  Right $ MessageEnvelope
    (fromIntegral $ CP.version cp)
    src
    tgt
    (CP.sequence cp)
    payload

-- UUID <-> ByteString helpers
uuidToBS :: UUID -> BS.ByteString
uuidToBS = LBS.toStrict . toByteString

bsToUUID :: BS.ByteString -> Either String UUID
bsToUUID bs = case fromByteString (LBS.fromStrict bs) of
  Just u  -> Right u
  Nothing -> Left "invalid UUID bytes"

bsToPlugId :: BS.ByteString -> Either String PlugId
bsToPlugId bs = PlugId <$> bsToUUID bs

bsToCell :: BS.ByteString -> Either String CellId
bsToCell bs = CellId <$> bsToUUID bs

unPlugId :: PlugId -> UUID
unPlugId (PlugId u) = u

unCellId :: CellId -> UUID
unCellId (CellId u) = u

-- Target conversion
targetToWire :: Target -> C.Parsed CP.Target
-- ... pattern match on TargetCell/TargetPlug/TargetBroadcast
-- produce CP.Target { union' = CP.Target'cell / CP.Target'plug / CP.Target'broadcast }

targetFromWire :: C.Parsed CP.Target -> Either String Target
-- ... pattern match on CP.Target'cell / CP.Target'plug / CP.Target'broadcast

-- Message payload conversion
payloadToWire :: Message -> C.Parsed CP.Message
-- ... pattern match on all Message constructors
-- produce CP.Message { union' = CP.Message'plugRegister / ... }

payloadFromWire :: C.Parsed CP.Message -> Either String Message
-- ... pattern match on all CP.Message'* constructors
```

The full implementation requires converting all 14 message variants. Each conversion is mechanical: extract UUIDs from ByteStrings, convert Text fields, map between domain and wire enums.

**Step 4: Run tests**

Run: `nix develop -c cabal test tank-tests`
Expected: PASS

**Step 5: Commit**

```bash
git add src/Tank/Core/Wire.hs tests/Tank/Core/WireSpec.hs tank.cabal
git commit -m "feat: add wire conversion between domain and Cap'n Proto types"
```

---

### Task 4: Message framing in Socket.hs

Add read/write functions that handle Cap'n Proto message framing over Unix sockets.

**Files:**
- Modify: `src/Tank/Daemon/Socket.hs`
- Create: `tests/Tank/Daemon/SocketSpec.hs`
- Modify: `tank.cabal`

**Step 1: Write failing test for socket round-trip**

```haskell
-- tests/Tank/Daemon/SocketSpec.hs
module Tank.Daemon.SocketSpec (spec) where

import Test.Hspec
import Data.UUID (nil)
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar
import Network.Socket (accept, close)
import System.IO.Temp (withSystemTempDirectory)

import Tank.Core.Types (PlugId(..))
import Tank.Core.Protocol
import Tank.Daemon.Socket

spec :: Spec
spec = describe "Socket message framing" $ do
  it "round-trips a MessageEnvelope over Unix socket" $ do
    withSystemTempDirectory "tank-test" $ \dir -> do
      let path = dir ++ "/test.sock"
          env = MessageEnvelope 1 (PlugId nil) TargetBroadcast 42 MsgListCells
      result <- newEmptyMVar
      -- Server
      serverSock <- listenSocket path
      _ <- forkIO $ do
        (clientSock, _) <- accept serverSock
        msg <- readEnvelope clientSock
        putMVar result msg
        close clientSock
        close serverSock
      -- Client
      clientSock <- connectSocket path
      writeEnvelope clientSock env
      close clientSock
      -- Verify
      received <- takeMVar result
      received `shouldBe` Right env
```

**Step 2: Run test to verify it fails**

Run: `nix develop -c cabal test tank-tests`
Expected: FAIL (readEnvelope/writeEnvelope not defined)

**Step 3: Implement readEnvelope/writeEnvelope in Socket.hs**

```haskell
-- Add to Socket.hs exports:
-- , readEnvelope
-- , writeEnvelope

import System.IO (Handle, hSetBinaryMode, hSetBuffering, BufferMode(..))
import Network.Socket (socketToHandle)
import qualified Capnp.IO as CIO
import qualified Tank.Gen.Protocol as CP
import Tank.Core.Wire (toWire, fromWire)
import Tank.Core.Protocol (MessageEnvelope)

-- | Read a framed Cap'n Proto message from a socket, decode to domain type.
readEnvelope :: Socket -> IO (Either String MessageEnvelope)
readEnvelope sock = do
  h <- socketToHandle sock ReadWriteMode
  hSetBinaryMode h True
  hSetBuffering h NoBuffering
  parsed <- CIO.hGetParsed @CP.MessageEnvelope h maxBound
  pure $ fromWire parsed

-- | Encode a domain MessageEnvelope and write as framed Cap'n Proto to socket.
writeEnvelope :: Socket -> MessageEnvelope -> IO ()
writeEnvelope sock env = do
  h <- socketToHandle sock ReadWriteMode
  hSetBinaryMode h True
  hSetBuffering h NoBuffering
  CIO.hPutParsed @CP.MessageEnvelope h (toWire env)
```

**Important:** `socketToHandle` consumes the socket — the Handle owns it after that. So we should convert once and pass the Handle around, not call socketToHandle repeatedly. Adjust the API:

```haskell
-- Better API: work with Handles after initial conversion
socketToHandlePair :: Socket -> IO Handle
socketToHandlePair sock = do
  h <- socketToHandle sock ReadWriteMode
  hSetBinaryMode h True
  hSetBuffering h (BlockBuffering Nothing)
  pure h

readEnvelope :: Handle -> IO (Either String MessageEnvelope)
writeEnvelope :: Handle -> MessageEnvelope -> IO ()
```

**Step 4: Run test**

Run: `nix develop -c cabal test tank-tests`
Expected: PASS

**Step 5: Commit**

```bash
git add src/Tank/Daemon/Socket.hs tests/Tank/Daemon/SocketSpec.hs tank.cabal
git commit -m "feat: add Cap'n Proto message framing over Unix sockets"
```

---

### Task 5: Client handler threads

Modify `Daemon/Main.hs` to spawn a handler thread per client connection instead of immediately closing.

**Files:**
- Modify: `src/Tank/Daemon/Main.hs`
- Modify: `src/Tank/Daemon/State.hs` (add client Handle tracking)

**Step 1: Update DaemonState to track client handles**

In `State.hs`, change `PlugConn` to use Handle instead of Socket:

```haskell
import System.IO (Handle)

data PlugConn = PlugConn
  { pcInfo   :: !PlugInfo
  , pcHandle :: !Handle    -- was pcSocket :: !Socket
  }
```

**Step 2: Update acceptLoop to spawn handler threads**

```haskell
-- Daemon/Main.hs
import Control.Concurrent (forkFinally)
import System.IO (Handle, hClose)
import Tank.Daemon.Socket (socketToHandlePair, readEnvelope, writeEnvelope)
import Tank.Daemon.Router (routeMessage)
import Tank.Core.Protocol (MessageEnvelope(..))

acceptLoop :: DaemonState -> Socket -> IO ()
acceptLoop state sock = do
  (clientSock, _addr) <- accept sock
  hPutStrLn stderr "tank: client connected"
  h <- socketToHandlePair clientSock
  _ <- forkFinally (handleClient state h) (\_ -> do
    hPutStrLn stderr "tank: client disconnected"
    hClose h)
  acceptLoop state sock

handleClient :: DaemonState -> Handle -> IO ()
handleClient state h = do
  result <- readEnvelope h
  case result of
    Left err -> hPutStrLn stderr $ "tank: read error: " ++ err
    Right envelope -> do
      response <- routeMessage state envelope
      case response of
        Just respMsg -> writeEnvelope h (makeResponse envelope respMsg)
        Nothing -> pure ()
      handleClient state h  -- loop

-- Build a response envelope from request envelope + response payload
makeResponse :: MessageEnvelope -> Message -> MessageEnvelope
makeResponse req payload = MessageEnvelope
  { meVersion  = meVersion req
  , meSource   = PlugId nilUUID  -- daemon's own ID (could be a constant)
  , meTarget   = TargetPlug (meSource req)
  , meSequence = meSequence req + 1
  , mePayload  = payload
  }
```

**Step 3: Verify build**

Run: `nix develop -c cabal build all`
Expected: Builds successfully

**Step 4: Commit**

```bash
git add src/Tank/Daemon/Main.hs src/Tank/Daemon/State.hs
git commit -m "feat: spawn per-client handler threads in daemon"
```

---

### Task 6: Router message handlers

Implement all message handlers in `Router.hs`.

**Files:**
- Modify: `src/Tank/Daemon/Router.hs`
- Create: `tests/Tank/Daemon/RouterSpec.hs`
- Modify: `tank.cabal`

**Step 1: Write failing tests for router handlers**

```haskell
-- tests/Tank/Daemon/RouterSpec.hs
module Tank.Daemon.RouterSpec (spec) where

import Test.Hspec
import Data.UUID (nil)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Control.Concurrent.STM

import Tank.Core.Types
import Tank.Core.Protocol
import Tank.Daemon.State
import Tank.Daemon.Router

mkEnvelope :: Message -> MessageEnvelope
mkEnvelope = MessageEnvelope 1 (PlugId nil) TargetBroadcast 1

spec :: Spec
spec = describe "Router" $ do
  it "handles MsgListCells with empty state" $ do
    ds <- newDaemonState
    result <- routeMessage ds (mkEnvelope MsgListCells)
    result `shouldBe` Just (MsgListCellsResponse [])

  it "handles MsgPlugRegister" $ do
    ds <- newDaemonState
    let info = PlugInfo (PlugId nil) "test-plug" Set.empty
    result <- routeMessage ds (mkEnvelope (MsgPlugRegister info))
    result `shouldBe` Just (MsgPlugRegistered (PlugId nil))
    -- Verify plug was added to state
    plugs <- atomically $ readTVar (dsPlugs ds)
    Map.member (PlugId nil) plugs `shouldBe` True

  it "handles MsgCellCreate" $ do
    ds <- newDaemonState
    let cid = CellId nil
    result <- routeMessage ds (mkEnvelope (MsgCellCreate cid "/tmp"))
    -- Should succeed (no error response)
    result `shouldBe` Nothing  -- or an ack, depending on design
    -- Verify cell was created
    cells <- atomically $ readTVar (dsCells ds)
    Map.member cid cells `shouldBe` True

  it "handles MsgCellAttach" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    -- Create cell first
    _ <- routeMessage ds (mkEnvelope (MsgCellCreate cid "/tmp"))
    -- Attach
    _ <- routeMessage ds (mkEnvelope (MsgCellAttach cid pid))
    -- Verify
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> Set.member pid (cellPlugs cell) `shouldBe` True

  it "handles MsgListCells after creating cells" $ do
    ds <- newDaemonState
    let cid = CellId nil
    _ <- routeMessage ds (mkEnvelope (MsgCellCreate cid "/tmp"))
    result <- routeMessage ds (mkEnvelope MsgListCells)
    result `shouldBe` Just (MsgListCellsResponse [(cid, "/tmp")])
```

**Step 2: Run tests**

Run: `nix develop -c cabal test tank-tests`
Expected: FAIL (handlers not implemented)

**Step 3: Implement router handlers**

```haskell
-- src/Tank/Daemon/Router.hs
module Tank.Daemon.Router
  ( routeMessage
  ) where

import Control.Concurrent.STM
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Tank.Core.Types
import Tank.Core.Protocol
import Tank.Daemon.State
import Tank.Terminal.Grid (newGrid)

routeMessage :: DaemonState -> MessageEnvelope -> IO (Maybe Message)
routeMessage ds envelope = case mePayload envelope of

  -- Plug lifecycle
  MsgPlugRegister info -> do
    atomically $ addPlug ds (PlugConn info undefined)  -- Handle set by caller
    pure $ Just $ MsgPlugRegistered (piId info)

  MsgPlugDeregister pid -> do
    atomically $ do
      removePlug ds pid
      -- Detach from all cells
      cells <- readTVar (dsCells ds)
      let cells' = Map.map (\c -> c { cellPlugs = Set.delete pid (cellPlugs c) }) cells
      writeTVar (dsCells ds) cells'
    pure Nothing

  -- Cell lifecycle
  MsgCellCreate cid dir -> do
    let cell = Cell
          { cellId = cid
          , cellDirectory = dir
          , cellEnv = Map.empty
          , cellPlugs = Set.empty
          , cellGrid = newGrid 80 24 100 10  -- default size
          }
    atomically $ addCell ds cell
    pure Nothing

  MsgCellDestroy cid -> do
    atomically $ removeCell ds cid
    pure Nothing

  MsgCellAttach cid pid -> do
    atomically $ do
      mcell <- getCell ds cid
      case mcell of
        Nothing -> pure ()
        Just cell -> do
          let cell' = cell { cellPlugs = Set.insert pid (cellPlugs cell) }
          addCell ds cell'  -- overwrite
    pure Nothing

  MsgCellDetach cid pid -> do
    atomically $ do
      mcell <- getCell ds cid
      case mcell of
        Nothing -> pure ()
        Just cell -> do
          let cell' = cell { cellPlugs = Set.delete pid (cellPlugs cell) }
          addCell ds cell'
    pure Nothing

  -- Queries
  MsgListCells -> do
    cells <- atomically $ listCells ds
    pure $ Just $ MsgListCellsResponse cells

  -- I/O routing (forward to attached plugs — needs broadcast mechanism)
  MsgInput _cid _data -> pure Nothing   -- TODO: forward to PTY owner
  MsgOutput _cid _data -> pure Nothing  -- TODO: broadcast to viewers

  -- State sync (deferred)
  MsgStateUpdate _cid _delta -> pure Nothing

  -- Pass-through (responses shouldn't arrive at router)
  MsgPlugRegistered _ -> pure Nothing
  MsgListCellsResponse _ -> pure Nothing
  MsgFetchLines _ _ _ -> pure Nothing
  MsgFetchLinesResponse _ _ -> pure Nothing
```

**Note on PlugConn:** The `routeMessage` currently gets `MessageEnvelope` but not the client Handle. The plug registration needs the Handle to be set by the caller (in `handleClient`). The plan is:

1. `handleClient` receives `MsgPlugRegister` → stores the Handle in PlugConn
2. Router `routeMessage` gets a `RegistrationContext` or the Handle is passed separately
3. Or: `routeMessage` takes an extra `Handle` parameter for the source client

Adjust `routeMessage` signature to:
```haskell
routeMessage :: DaemonState -> Handle -> MessageEnvelope -> IO (Maybe Message)
```

So the Handle of the sending client is available for PlugRegister.

**Step 4: Run tests**

Run: `nix develop -c cabal test tank-tests`
Expected: PASS

**Step 5: Commit**

```bash
git add src/Tank/Daemon/Router.hs tests/Tank/Daemon/RouterSpec.hs tank.cabal
git commit -m "feat: implement router message handlers for plug/cell lifecycle"
```

---

### Task 7: Integration test

End-to-end test: start daemon, connect client, register plug, create cell, list cells.

**Files:**
- Create: `tests/Tank/Daemon/IntegrationSpec.hs`
- Modify: `tank.cabal`

**Step 1: Write integration test**

```haskell
-- tests/Tank/Daemon/IntegrationSpec.hs
module Tank.Daemon.IntegrationSpec (spec) where

import Test.Hspec
import Control.Concurrent (forkIO, threadDelay, killThread)
import Data.UUID (nil)
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import Network.Socket (close)

import Tank.Core.Types (CellId(..), PlugId(..))
import Tank.Core.Protocol
import Tank.Daemon.Main (startDaemonAt)  -- need a variant that takes path
import Tank.Daemon.Socket (connectSocket, socketToHandlePair, readEnvelope, writeEnvelope)

spec :: Spec
spec = describe "Daemon integration" $ do
  it "client can register, create cell, and list cells" $ do
    withSystemTempDirectory "tank-int" $ \dir -> do
      let sockPath = dir ++ "/test.sock"

      -- Start daemon in background
      daemonThread <- forkIO $ startDaemonAt sockPath

      -- Wait for socket to appear
      threadDelay 100000  -- 100ms

      -- Connect client
      clientSock <- connectSocket sockPath
      h <- socketToHandlePair clientSock

      -- Register as plug
      let pid = PlugId nil
          regMsg = MessageEnvelope 1 pid TargetBroadcast 1
                     (MsgPlugRegister (PlugInfo pid "test" mempty))
      writeEnvelope h regMsg
      resp1 <- readEnvelope h
      case resp1 of
        Right env -> mePayload env `shouldBe` MsgPlugRegistered pid
        Left err  -> expectationFailure $ "register failed: " ++ err

      -- Create cell
      let cid = CellId nil
          createMsg = MessageEnvelope 1 pid TargetBroadcast 2
                        (MsgCellCreate cid "/tmp")
      writeEnvelope h createMsg
      -- No response expected for cellCreate

      -- List cells
      let listMsg = MessageEnvelope 1 pid TargetBroadcast 3 MsgListCells
      writeEnvelope h listMsg
      resp2 <- readEnvelope h
      case resp2 of
        Right env -> mePayload env `shouldBe` MsgListCellsResponse [(cid, "/tmp")]
        Left err  -> expectationFailure $ "listCells failed: " ++ err

      -- Cleanup
      hClose h
      killThread daemonThread
```

**Note:** May need a `startDaemonAt :: FilePath -> IO ()` variant that takes a specific socket path instead of computing one from the daemon name. Add this to `Daemon/Main.hs`.

**Step 2: Run test**

Run: `nix develop -c cabal test tank-tests`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/Tank/Daemon/IntegrationSpec.hs src/Tank/Daemon/Main.hs tank.cabal
git commit -m "test: add daemon integration test for plug registration and cell lifecycle"
```

---

### Summary of changes

| File | Action | Description |
|------|--------|-------------|
| `flake.nix` | Modify | Add capnp with doJailbreak + GHC 9.10 patch |
| `tank.cabal` | Modify | Add capnp dep, Gen modules, test modules |
| `src/Tank/Gen/Protocol.hs` | Create | Generated Cap'n Proto types (protocol) |
| `src/Tank/Gen/Grid.hs` | Create | Generated Cap'n Proto types (grid) |
| `src/Tank/Gen/ById/*.hs` | Create | Generated ID-based modules |
| `src/Tank/Core/Wire.hs` | Create | Domain ↔ Cap'n Proto conversion |
| `src/Tank/Daemon/Socket.hs` | Modify | Add readEnvelope/writeEnvelope |
| `src/Tank/Daemon/Main.hs` | Modify | Per-client handler threads |
| `src/Tank/Daemon/Router.hs` | Modify | All message handlers |
| `src/Tank/Daemon/State.hs` | Modify | Handle in PlugConn |
| `tests/Tank/Core/WireSpec.hs` | Create | Wire round-trip tests |
| `tests/Tank/Daemon/SocketSpec.hs` | Create | Socket framing tests |
| `tests/Tank/Daemon/RouterSpec.hs` | Create | Router unit tests |
| `tests/Tank/Daemon/IntegrationSpec.hs` | Create | End-to-end test |
