# I/O Routing & Plug Registration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the daemon router fully functional: plugs register with their Handle, MsgInput forwards to PTY owner, MsgOutput broadcasts to all attached plugs.

**Architecture:** Expand `routeMessage` return type from `Maybe Message` to `[RouteAction]` where `RouteAction` can be `Reply`, `SendTo`, or `Broadcast`. Add PTY ownership to `Cell`. Update `handleClient` to dispatch actions to the correct plug handles.

**Tech Stack:** Haskell (GHC 9.10.3), STM, HSpec

**Prior work:**
- Design: `docs/plans/2026-03-06-io-routing-design.md`
- Daemon router: `src/Tank/Daemon/Router.hs` (current handlers return `Maybe Message`)
- Client handler: `src/Tank/Daemon/Main.hs` (`handleClient` reads/routes/responds)
- State: `src/Tank/Daemon/State.hs` (`DaemonState`, `PlugConn`)
- Domain types: `src/Tank/Core/Types.hs` (`Cell`, `PlugInfo`)

---

### Task 1: Add cellPtyOwner to Cell and state helpers

Add PTY ownership tracking to Cell and new state query functions.

**Files:**
- Modify: `src/Tank/Core/Types.hs`
- Modify: `src/Tank/Daemon/State.hs`

**Step 1: Add cellPtyOwner field to Cell**

In `src/Tank/Core/Types.hs`, add a new field to `Cell`:

```haskell
data Cell = Cell
  { cellId        :: !CellId
  , cellDirectory :: !FilePath
  , cellEnv       :: !(Map Text Text)
  , cellPlugs     :: !(Set PlugId)
  , cellPtyOwner  :: !(Maybe PlugId)  -- plug that owns PTY for this cell
  , cellGrid      :: !Grid
  } deriving (Show)
```

**Step 2: Fix all Cell construction sites**

After adding the field, the build will break wherever `Cell` is constructed. Fix these:

In `src/Tank/Daemon/Router.hs` line 40-46, add `cellPtyOwner = Nothing` (will be updated in Task 3):
```haskell
    let cell = Cell
          { cellId = cid
          , cellDirectory = dir
          , cellEnv = Map.empty
          , cellPlugs = Set.empty
          , cellPtyOwner = Nothing
          , cellGrid = mkGrid (ReplicaId nil) 80 24 100 10
          }
```

**Step 3: Add state query helpers to State.hs**

Add to `src/Tank/Daemon/State.hs` exports and implementation:

```haskell
-- Add to module exports:
-- , lookupPlug
-- , getCellPlugs

-- | Look up a plug's connection by ID
lookupPlug :: DaemonState -> PlugId -> STM (Maybe PlugConn)
lookupPlug ds pid =
  Map.lookup pid <$> readTVar (dsPlugs ds)

-- | Get the set of plugs attached to a cell
getCellPlugs :: DaemonState -> CellId -> STM (Set PlugId)
getCellPlugs ds cid = do
  mcell <- getCell ds cid
  pure $ case mcell of
    Nothing   -> Set.empty
    Just cell -> cellPlugs cell
```

Import `Set` and add it to the import of `Data.Set`:
```haskell
import Data.Set (Set)
import qualified Data.Set as Set
```

Wait — `Set` is already imported via `Tank.Core.Types` (`Cell` has `cellPlugs :: Set PlugId`). But `State.hs` doesn't import `Set` directly. Add:
```haskell
import Data.Set (Set)
```

**Step 4: Verify build**

Run: `nix develop -c cabal build all`
Expected: Builds successfully

**Step 5: Commit**

```bash
git add src/Tank/Core/Types.hs src/Tank/Daemon/State.hs src/Tank/Daemon/Router.hs
git commit -m "feat: add cellPtyOwner field and state query helpers"
```

---

### Task 2: Add RouteAction type and update Router

Replace `routeMessage` return type and update all handlers.

**Files:**
- Modify: `src/Tank/Daemon/Router.hs`
- Modify: `tests/Tank/Daemon/RouterSpec.hs`

**Step 1: Update Router.hs with RouteAction type and new signature**

Replace the entire `src/Tank/Daemon/Router.hs`:

```haskell
{-# LANGUAGE LambdaCase #-}
module Tank.Daemon.Router
  ( RouteAction(..)
  , routeMessage
  ) where

import Control.Concurrent.STM
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.UUID (nil)
import System.IO (Handle)

import Tank.Core.CRDT (ReplicaId(..))
import Tank.Core.Types
import Tank.Core.Protocol
import Tank.Daemon.State
import Tank.Terminal.Grid (mkGrid)

-- | Routing decisions returned by the router.
data RouteAction
  = Reply Message              -- ^ Respond to the sender
  | SendTo PlugId Message      -- ^ Send to a specific plug
  | Broadcast CellId Message   -- ^ Send to all plugs attached to a cell
  deriving (Eq, Show)

-- | Route an incoming message. Returns a list of actions for the caller to dispatch.
routeMessage :: DaemonState -> Handle -> MessageEnvelope -> IO [RouteAction]
routeMessage ds handle envelope = case mePayload envelope of

  -- Plug lifecycle
  MsgPlugRegister info -> do
    let conn = PlugConn info handle
    atomically $ addPlug ds conn
    pure [Reply (MsgPlugRegistered (piId info))]

  MsgPlugDeregister pid -> do
    atomically $ do
      removePlug ds pid
      cells <- readTVar (dsCells ds)
      let cells' = Map.map (\c -> c { cellPlugs = Set.delete pid (cellPlugs c) }) cells
      writeTVar (dsCells ds) cells'
    pure []

  -- Cell lifecycle
  MsgCellCreate cid dir -> do
    let cell = Cell
          { cellId = cid
          , cellDirectory = dir
          , cellEnv = Map.empty
          , cellPlugs = Set.empty
          , cellPtyOwner = Just (meSource envelope)
          , cellGrid = mkGrid (ReplicaId nil) 80 24 100 10
          }
    atomically $ addCell ds cell
    pure []

  MsgCellDestroy cid -> do
    atomically $ removeCell ds cid
    pure []

  MsgCellAttach cid pid -> do
    atomically $ do
      mcell <- getCell ds cid
      case mcell of
        Nothing -> pure ()
        Just cell -> addCell ds cell { cellPlugs = Set.insert pid (cellPlugs cell) }
    pure []

  MsgCellDetach cid pid -> do
    atomically $ do
      mcell <- getCell ds cid
      case mcell of
        Nothing -> pure ()
        Just cell -> addCell ds cell { cellPlugs = Set.delete pid (cellPlugs cell) }
    pure []

  -- Queries
  MsgListCells -> do
    cells <- atomically $ listCells ds
    pure [Reply (MsgListCellsResponse cells)]

  -- I/O routing
  MsgInput cid bytes -> do
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> pure []
      Just cell -> case cellPtyOwner cell of
        Nothing -> pure []
        Just owner -> pure [SendTo owner (MsgInput cid bytes)]

  MsgOutput cid bytes -> do
    pure [Broadcast cid (MsgOutput cid bytes)]

  -- State sync (deferred)
  MsgStateUpdate _cid _delta -> pure []

  -- Response messages shouldn't arrive at router
  MsgPlugRegistered _ -> pure []
  MsgListCellsResponse _ -> pure []
  MsgFetchLines {} -> pure []
  MsgFetchLinesResponse _ _ -> pure []
```

**Step 2: Update RouterSpec.hs**

The tests need to change because:
1. `routeMessage` now takes a `Handle` parameter
2. Return type is `[RouteAction]` instead of `Maybe Message`
3. `MsgPlugRegister` now stores PlugConn (needs a real handle)

For tests, we need a dummy Handle. Use `System.IO (stdin)` as a placeholder since the router tests don't write to it.

Replace the entire `tests/Tank/Daemon/RouterSpec.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Tank.Daemon.RouterSpec (spec) where

import Test.Hspec
import Data.UUID (nil)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Control.Concurrent.STM
import System.IO (stdin)

import Tank.Core.Types
import Tank.Core.Protocol
import Tank.Daemon.State
import Tank.Daemon.Router

-- | Dummy handle for tests (router tests don't write to it)
dummyHandle :: System.IO.Handle
dummyHandle = stdin

mkEnvelope :: Message -> MessageEnvelope
mkEnvelope = MessageEnvelope 1 (PlugId nil) TargetBroadcast 1

spec :: Spec
spec = describe "Router" $ do
  it "handles MsgListCells with empty state" $ do
    ds <- newDaemonState
    result <- routeMessage ds dummyHandle (mkEnvelope MsgListCells)
    result `shouldBe` [Reply (MsgListCellsResponse [])]

  it "handles MsgPlugRegister and stores plug" $ do
    ds <- newDaemonState
    let info = PlugInfo (PlugId nil) "test-plug" Set.empty
    result <- routeMessage ds dummyHandle (mkEnvelope (MsgPlugRegister info))
    result `shouldBe` [Reply (MsgPlugRegistered (PlugId nil))]
    -- Verify plug was stored
    plugs <- atomically $ readTVar (dsPlugs ds)
    Map.member (PlugId nil) plugs `shouldBe` True

  it "handles MsgCellCreate with PTY owner" $ do
    ds <- newDaemonState
    let cid = CellId nil
    result <- routeMessage ds dummyHandle (mkEnvelope (MsgCellCreate cid "/tmp"))
    result `shouldBe` []
    -- Verify cell created with PTY owner
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> cellPtyOwner cell `shouldBe` Just (PlugId nil)

  it "handles MsgCellDestroy" $ do
    ds <- newDaemonState
    let cid = CellId nil
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellDestroy cid))
    cells <- atomically $ readTVar (dsCells ds)
    Map.member cid cells `shouldBe` False

  it "handles MsgCellAttach" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellAttach cid pid))
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> Set.member pid (cellPlugs cell) `shouldBe` True

  it "handles MsgCellDetach" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellAttach cid pid))
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellDetach cid pid))
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> Set.member pid (cellPlugs cell) `shouldBe` False

  it "lists cells after creating" $ do
    ds <- newDaemonState
    let cid = CellId nil
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellCreate cid "/tmp"))
    result <- routeMessage ds dummyHandle (mkEnvelope MsgListCells)
    result `shouldBe` [Reply (MsgListCellsResponse [(cid, "/tmp")])]

  it "handles MsgPlugDeregister and cleans up cells" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellAttach cid pid))
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgPlugDeregister pid))
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> Set.member pid (cellPlugs cell) `shouldBe` False

  it "routes MsgInput to PTY owner" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds dummyHandle (mkEnvelope (MsgCellCreate cid "/tmp"))
    result <- routeMessage ds dummyHandle (mkEnvelope (MsgInput cid "hello"))
    result `shouldBe` [SendTo pid (MsgInput cid "hello")]

  it "routes MsgOutput as broadcast" $ do
    ds <- newDaemonState
    let cid = CellId nil
    result <- routeMessage ds dummyHandle (mkEnvelope (MsgOutput cid "data"))
    result `shouldBe` [Broadcast cid (MsgOutput cid "data")]

  it "returns empty for MsgInput to nonexistent cell" $ do
    ds <- newDaemonState
    let cid = CellId nil
    result <- routeMessage ds dummyHandle (mkEnvelope (MsgInput cid "hello"))
    result `shouldBe` []
```

**Step 3: Verify build and tests**

Run: `nix develop -c cabal test tank-tests`
Expected: All tests pass (existing 8 router tests updated + 3 new = 11 router tests)

**Step 4: Commit**

```bash
git add src/Tank/Daemon/Router.hs tests/Tank/Daemon/RouterSpec.hs
git commit -m "feat: add RouteAction type and I/O routing handlers"
```

---

### Task 3: Update handleClient to dispatch RouteActions

Update `Main.hs` to process `[RouteAction]` instead of `Maybe Message`.

**Files:**
- Modify: `src/Tank/Daemon/Main.hs`

**Step 1: Update handleClient and add dispatchActions**

```haskell
module Tank.Daemon.Main
  ( startDaemon
  , startDaemonAt
  , stopDaemon
  ) where

import Control.Concurrent (forkFinally)
import Control.Concurrent.STM (atomically)
import Control.Exception (bracket, IOException, try)
import Control.Monad (forM_)
import Data.UUID (nil)
import Network.Socket (Socket, accept, close)
import System.Directory (removeFile)
import System.IO (Handle, hClose, hPutStrLn, stderr)
import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Core.Types (PlugId(..))
import Tank.Daemon.Router (RouteAction(..), routeMessage)
import Tank.Daemon.Socket (listenSocket, socketPath, socketHandle, readEnvelope, writeEnvelope)
import Tank.Daemon.State (DaemonState, newDaemonState, lookupPlug, getCellPlugs)
import qualified Data.Set as Set

startDaemon :: String -> IO ()
startDaemon name = do
  path <- socketPath name
  startDaemonAt path

startDaemonAt :: FilePath -> IO ()
startDaemonAt path = do
  hPutStrLn stderr $ "tank: starting daemon on " ++ path
  state <- newDaemonState
  bracket (listenSocket path) (cleanup path) (acceptLoop state)
  where
    cleanup p sock = do
      close sock
      removeFile p

acceptLoop :: DaemonState -> Socket -> IO ()
acceptLoop state sock = do
  (clientSock, _addr) <- accept sock
  hPutStrLn stderr "tank: client connected"
  h <- socketHandle clientSock
  _ <- forkFinally (handleClient state h) (\_ -> do
    hPutStrLn stderr "tank: client disconnected"
    hClose h)
  acceptLoop state sock

handleClient :: DaemonState -> Handle -> IO ()
handleClient state h = do
  result <- readEnvelope h
  case result of
    Left _err -> pure ()
    Right envelope -> do
      actions <- routeMessage state h envelope
      dispatchActions state h envelope actions
      handleClient state h

-- | Dispatch routing actions to the appropriate handles.
dispatchActions :: DaemonState -> Handle -> MessageEnvelope -> [RouteAction] -> IO ()
dispatchActions ds senderH req actions = forM_ actions $ \case
  Reply msg ->
    writeEnvelope senderH (makeResponse req msg)
  SendTo pid msg -> do
    mconn <- atomically $ lookupPlug ds pid
    case mconn of
      Just conn -> safeSend (pcHandle conn) (makeResponse req msg)
      Nothing -> pure ()
  Broadcast cid msg -> do
    plugIds <- atomically $ getCellPlugs ds cid
    forM_ (Set.toList plugIds) $ \pid -> do
      mconn <- atomically $ lookupPlug ds pid
      case mconn of
        Just conn -> safeSend (pcHandle conn) (makeResponse req msg)
        Nothing -> pure ()

-- | Write envelope, silently ignoring write errors (plug may have disconnected).
safeSend :: Handle -> MessageEnvelope -> IO ()
safeSend h env = do
  result <- try (writeEnvelope h env)
  case result of
    Left (_ :: IOException) -> pure ()
    Right () -> pure ()

makeResponse :: MessageEnvelope -> Message -> MessageEnvelope
makeResponse req payload = MessageEnvelope
  { meVersion  = meVersion req
  , meSource   = PlugId nil
  , meTarget   = TargetPlug (meSource req)
  , meSequence = meSequence req + 1
  , mePayload  = payload
  }

stopDaemon :: String -> IO ()
stopDaemon name = do
  path <- socketPath name
  hPutStrLn stderr $ "tank: stopping daemon at " ++ path
```

Note: `dispatchActions` needs `pcHandle` from `PlugConn`, which is currently accessible because `DaemonState` exports `PlugConn(..)`. Import `Tank.Daemon.State (PlugConn(..))` or use `pcHandle` accessor.

**Step 2: Verify build**

Run: `nix develop -c cabal build all`
Expected: Builds successfully

**Step 3: Commit**

```bash
git add src/Tank/Daemon/Main.hs
git commit -m "feat: dispatch RouteActions to plug handles in handleClient"
```

---

### Task 4: Update integration test for I/O broadcast

Add a second client to the integration test to verify MsgOutput broadcast.

**Files:**
- Modify: `tests/Tank/Daemon/IntegrationSpec.hs`

**Step 1: Update the integration test**

Add a new test case that:
1. Starts daemon
2. Connects two clients
3. Both register as plugs (need different PlugIds)
4. One creates a cell, both attach
5. One sends MsgOutput
6. The other receives the broadcast

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Tank.Daemon.IntegrationSpec (spec) where

import Test.Hspec
import Control.Concurrent (forkIO, threadDelay, killThread)
import Data.UUID (nil)
import Data.UUID.V4 (nextRandom)
import qualified Data.Set as Set
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)

import Tank.Core.Types (CellId(..), PlugId(..), PlugInfo(..))
import Tank.Core.Protocol
import Tank.Daemon.Main (startDaemonAt)
import Tank.Daemon.Socket (connectSocket, socketHandle, readEnvelope, writeEnvelope)

spec :: Spec
spec = describe "Daemon integration" $ do
  it "client can register, create cell, and list cells" $ do
    withSystemTempDirectory "tank-int" $ \dir -> do
      let sockPath = dir ++ "/test.sock"

      daemonThread <- forkIO $ startDaemonAt sockPath
      threadDelay 200000

      clientSock <- connectSocket sockPath
      h <- socketHandle clientSock

      let pid = PlugId nil
          regMsg = MessageEnvelope 1 pid TargetBroadcast 1
                     (MsgPlugRegister (PlugInfo pid "test" Set.empty))
      writeEnvelope h regMsg
      resp1 <- readEnvelope h
      case resp1 of
        Right env -> mePayload env `shouldBe` MsgPlugRegistered pid
        Left err  -> expectationFailure $ "register failed: " ++ err

      let cid = CellId nil
          createMsg = MessageEnvelope 1 pid TargetBroadcast 2
                        (MsgCellCreate cid "/tmp")
      writeEnvelope h createMsg
      threadDelay 50000

      let listMsg = MessageEnvelope 1 pid TargetBroadcast 3 MsgListCells
      writeEnvelope h listMsg
      resp2 <- readEnvelope h
      case resp2 of
        Right env -> mePayload env `shouldBe` MsgListCellsResponse [(cid, "/tmp")]
        Left err  -> expectationFailure $ "listCells failed: " ++ err

      hClose h
      killThread daemonThread

  it "broadcasts MsgOutput to attached plugs" $ do
    withSystemTempDirectory "tank-int" $ \dir -> do
      let sockPath = dir ++ "/test.sock"

      daemonThread <- forkIO $ startDaemonAt sockPath
      threadDelay 200000

      -- Connect two clients
      sock1 <- connectSocket sockPath
      h1 <- socketHandle sock1
      sock2 <- connectSocket sockPath
      h2 <- socketHandle sock2

      -- Generate unique plug IDs
      uid1 <- nextRandom
      uid2 <- nextRandom
      let pid1 = PlugId uid1
          pid2 = PlugId uid2
          cid = CellId nil

      -- Register plug 1
      writeEnvelope h1 $ MessageEnvelope 1 pid1 TargetBroadcast 1
        (MsgPlugRegister (PlugInfo pid1 "plug1" Set.empty))
      resp1 <- readEnvelope h1
      case resp1 of
        Right env -> mePayload env `shouldBe` MsgPlugRegistered pid1
        Left err  -> expectationFailure $ "plug1 register failed: " ++ err

      -- Register plug 2
      writeEnvelope h2 $ MessageEnvelope 1 pid2 TargetBroadcast 1
        (MsgPlugRegister (PlugInfo pid2 "plug2" Set.empty))
      resp2 <- readEnvelope h2
      case resp2 of
        Right env -> mePayload env `shouldBe` MsgPlugRegistered pid2
        Left err  -> expectationFailure $ "plug2 register failed: " ++ err

      -- Plug 1 creates cell
      writeEnvelope h1 $ MessageEnvelope 1 pid1 TargetBroadcast 2
        (MsgCellCreate cid "/tmp")
      threadDelay 50000

      -- Both attach to cell
      writeEnvelope h1 $ MessageEnvelope 1 pid1 TargetBroadcast 3
        (MsgCellAttach cid pid1)
      threadDelay 50000
      writeEnvelope h2 $ MessageEnvelope 1 pid2 TargetBroadcast 3
        (MsgCellAttach cid pid2)
      threadDelay 50000

      -- Plug 1 sends MsgOutput
      writeEnvelope h1 $ MessageEnvelope 1 pid1 TargetBroadcast 4
        (MsgOutput cid "hello from plug1")

      -- Plug 1 should receive broadcast (it's attached)
      resp3 <- readEnvelope h1
      case resp3 of
        Right env -> mePayload env `shouldBe` MsgOutput cid "hello from plug1"
        Left err  -> expectationFailure $ "plug1 broadcast failed: " ++ err

      -- Plug 2 should also receive broadcast
      resp4 <- readEnvelope h2
      case resp4 of
        Right env -> mePayload env `shouldBe` MsgOutput cid "hello from plug1"
        Left err  -> expectationFailure $ "plug2 broadcast failed: " ++ err

      hClose h1
      hClose h2
      killThread daemonThread
```

**IMPORTANT:** This test requires `uuid` package for `Data.UUID.V4 (nextRandom)`. Check if `uuid` is already in test build-depends (it is — `uuid >= 1.3 && < 2`). Good.

**Step 2: Verify build and tests**

Run: `nix develop -c cabal test tank-tests`
Expected: All tests pass including the new broadcast test

**Step 3: Commit**

```bash
git add tests/Tank/Daemon/IntegrationSpec.hs
git commit -m "test: add integration test for MsgOutput broadcast to attached plugs"
```

---

### Summary of changes

| File | Action | Description |
|------|--------|-------------|
| `src/Tank/Core/Types.hs` | Modify | Add `cellPtyOwner :: Maybe PlugId` to Cell |
| `src/Tank/Daemon/State.hs` | Modify | Add `lookupPlug`, `getCellPlugs` helpers |
| `src/Tank/Daemon/Router.hs` | Modify | Add `RouteAction` type, change return to `[RouteAction]`, add Handle param, implement I/O routing |
| `src/Tank/Daemon/Main.hs` | Modify | Add `dispatchActions`, `safeSend`, update `handleClient` |
| `tests/Tank/Daemon/RouterSpec.hs` | Modify | Update for new signature, add I/O routing tests |
| `tests/Tank/Daemon/IntegrationSpec.hs` | Modify | Add broadcast test with two clients |
