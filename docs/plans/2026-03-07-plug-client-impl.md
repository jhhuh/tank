# Plug Client & Terminal Daemon Wiring Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a reusable plug client library and wire Terminal.hs to optionally connect to the daemon for cell lifecycle and output broadcasting.

**Architecture:** Side-channel daemon connection. Terminal.hs keeps direct PTY I/O for local rendering. A new `Tank.Plug.Client` module handles daemon registration and messaging. Terminal.hs connects at startup (optional — works standalone if daemon isn't running), maps panes to cells, and forwards PTY output as MsgOutput. A background thread reads daemon messages for remote input.

**Tech Stack:** Haskell, GHC 9.6+, Cap'n Proto framing via `Tank.Daemon.Socket`, `uuid` for CellId generation, `network` for Unix sockets.

---

### Task 1: Create Tank.Plug.Client module

Create the reusable plug client library that any plug uses to connect to the daemon.

**Files:**
- Create: `src/Tank/Plug/Client.hs`
- Create: `tests/Tank/Plug/ClientSpec.hs`
- Modify: `tank.cabal` (add module to exposed-modules, add test module to other-modules)

**Step 1: Write the failing test**

Create `tests/Tank/Plug/ClientSpec.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Tank.Plug.ClientSpec (spec) where

import Test.Hspec
import Control.Concurrent (forkIO, threadDelay, killThread)
import qualified Data.Set as Set
import System.IO.Temp (withSystemTempDirectory)

import Tank.Core.Types (PlugId(..), PlugInfo(..), PlugCapability(..))
import Tank.Daemon.Main (startDaemonAt)
import Tank.Plug.Client (connectDaemon, disconnectPlug, pcPlugId)

spec :: Spec
spec = describe "Plug.Client" $ do
  it "connects to daemon and registers plug" $ do
    withSystemTempDirectory "tank-client" $ \dir -> do
      let sockPath = dir ++ "/test.sock"
      daemonThread <- forkIO $ startDaemonAt sockPath
      threadDelay 200000

      let info name caps = PlugInfo
            { piId = undefined  -- connectDaemon generates the ID
            , piName = name
            , piCapabilities = caps
            }

      result <- connectDaemon sockPath "terminal" (Set.singleton CapTerminal)
      case result of
        Nothing -> expectationFailure "connectDaemon returned Nothing"
        Just client -> do
          -- pcPlugId should be a valid PlugId (not nil)
          let _pid = pcPlugId client
          disconnectPlug client
          pure ()

      killThread daemonThread

  it "returns Nothing when daemon is not running" $ do
    withSystemTempDirectory "tank-client" $ \dir -> do
      let sockPath = dir ++ "/nonexistent.sock"
      result <- connectDaemon sockPath "terminal" (Set.singleton CapTerminal)
      result `shouldBe` Nothing
```

**Step 2: Register the test module**

Add `Tank.Plug.ClientSpec` to `tank.cabal` under `test-suite tank-tests` → `other-modules`.

**Step 3: Run test to verify it fails**

Run: `nix develop -c cabal test 2>&1 | grep -E '(FAIL|PASS|Could not find|examples)'`
Expected: FAIL — `Tank.Plug.Client` module does not exist

**Step 4: Write minimal implementation**

Create `src/Tank/Plug/Client.hs`:

```haskell
{-# LANGUAGE ScopedTypeVariables #-}
module Tank.Plug.Client
  ( PlugClient(..)
  , connectDaemon
  , sendMsg
  , recvMsg
  , disconnectPlug
  ) where

import Control.Exception (IOException, try)
import Data.Set (Set)
import Data.Text (Text)
import Data.UUID.V4 (nextRandom)
import System.IO (Handle, hClose)

import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Core.Types (PlugId(..), PlugInfo(..), PlugCapability)
import Tank.Daemon.Socket (connectSocket, socketHandle, readEnvelope, writeEnvelope)

-- | A connected plug client.
data PlugClient = PlugClient
  { pcHandle :: !Handle
  , pcPlugId :: !PlugId
  } deriving (Show)

-- | Connect to the daemon, register as a plug.
-- Returns Nothing if the daemon is not running or registration fails.
connectDaemon :: FilePath -> Text -> Set PlugCapability -> IO (Maybe PlugClient)
connectDaemon sockPath name caps = do
  result <- try (connectSocket sockPath) :: IO (Either IOException _)
  case result of
    Left _ -> pure Nothing
    Right sock -> do
      h <- socketHandle sock
      uid <- nextRandom
      let pid = PlugId uid
          info = PlugInfo pid name caps
          env = MessageEnvelope 1 pid TargetBroadcast 1
                  (MsgPlugRegister info)
      writeEnvelope h env
      resp <- readEnvelope h
      case resp of
        Right rEnv | MsgPlugRegistered rpid <- mePayload rEnv, rpid == pid ->
          pure $ Just (PlugClient h pid)
        _ -> do
          hClose h
          pure Nothing

-- | Send a message envelope to the daemon.
sendMsg :: PlugClient -> MessageEnvelope -> IO ()
sendMsg client = writeEnvelope (pcHandle client)

-- | Read a message from the daemon. Returns Left on EOF/error.
recvMsg :: PlugClient -> IO (Either String MessageEnvelope)
recvMsg client = readEnvelope (pcHandle client)

-- | Deregister from the daemon and close the connection.
disconnectPlug :: PlugClient -> IO ()
disconnectPlug client = do
  let env = MessageEnvelope 1 (pcPlugId client) TargetBroadcast 0
              (MsgPlugDeregister (pcPlugId client))
  result <- try (writeEnvelope (pcHandle client) env) :: IO (Either IOException ())
  case result of
    Left _ -> pure ()
    Right () -> pure ()
  hClose (pcHandle client)
```

Add `Tank.Plug.Client` to `tank.cabal` under `library` → `exposed-modules`.

**Step 5: Run test to verify it passes**

Run: `nix develop -c cabal test 2>&1 | grep -E '(FAIL|PASS|examples)'`
Expected: 88 examples, 0 failures (2 new tests)

**Step 6: Commit**

```bash
git add src/Tank/Plug/Client.hs tests/Tank/Plug/ClientSpec.hs tank.cabal
git commit -m "feat: add Tank.Plug.Client module for daemon connection"
```

---

### Task 2: Add CellId to Pane and daemon ref to TermState

Wire the data structures so Terminal.hs can map panes to cells and hold an optional daemon connection.

**Files:**
- Modify: `src/Tank/Plug/Terminal.hs:57-93` (Pane and TermState data types)

**Step 1: Add pCellId to Pane**

In `src/Tank/Plug/Terminal.hs`, add a new field to `Pane`:

```haskell
data Pane = Pane
  { pPty     :: !Pty
  , pRunning :: !(IORef Bool)
  , pOverlay :: !(IORef OverlayState)
  , pAgent   :: !(IORef AgentState)
  , pVTerm   :: !(IORef VTerm)
  , pCellId  :: !(Maybe CellId)        -- NEW: maps to daemon cell (Nothing in standalone)
  }
```

**Step 2: Add tsDaemon to TermState**

```haskell
data TermState = TermState
  { tsPanes     :: !(IORef (IM.IntMap Pane))
  , tsWindows   :: !(IORef (IM.IntMap Window))
  , tsActiveWin :: !(IORef Int)
  , tsNextPaneId :: !(IORef Int)
  , tsNextWinId  :: !(IORef Int)
  , tsRunning   :: !(IORef Bool)
  , tsPrefix    :: !(IORef Bool)
  , tsCols      :: !(IORef Int)
  , tsShell     :: !String
  , tsCopyScroll :: !(IORef Int)
  , tsDaemon    :: !(IORef (Maybe PlugClient))  -- NEW: optional daemon connection
  }
```

**Step 3: Add needed imports**

At the top of `src/Tank/Plug/Terminal.hs`, add:

```haskell
import Tank.Core.Types (CellId(..))
import Tank.Plug.Client (PlugClient)
```

**Step 4: Fix all construction sites**

In `runTerminalPlug`, initialize `tsDaemon`:

```haskell
      daemonRef  <- newIORef Nothing
      pure TermState
        { ...
        , tsDaemon     = daemonRef
        }
```

In `createPane`, add `pCellId = Nothing` to the Pane constructor:

```haskell
  let pane = Pane pty pRunRef pOvRef pAgRef pVtRef Nothing
```

**Step 5: Build to verify it compiles**

Run: `nix develop -c cabal build all 2>&1 | grep -E '(error|Building|Linking)'`
Expected: Builds successfully

**Step 6: Run tests**

Run: `nix develop -c cabal test 2>&1 | grep -E '(FAIL|PASS|examples)'`
Expected: 88 examples, 0 failures (no behavior change, just data structure additions)

**Step 7: Commit**

```bash
git add src/Tank/Plug/Terminal.hs
git commit -m "feat: add daemon ref and CellId to Terminal data structures"
```

---

### Task 3: Connect to daemon at startup and create cells for panes

Wire `runTerminalPlug` to optionally connect to the daemon. When connected, `createPane` registers cells with the daemon.

**Files:**
- Modify: `src/Tank/Plug/Terminal.hs:96-175` (runTerminalPlug and createPane)

**Step 1: Wire daemon connection in runTerminalPlug**

After creating TermState, try connecting to the daemon. Add this after `tsDaemon` initialization and before `installHandler`:

```haskell
    -- Try connecting to daemon (optional — works standalone if not running)
    daemonSockPath <- socketPath "default"
    mClient <- connectDaemon daemonSockPath "terminal" (Set.singleton CapTerminal)
    writeIORef (tsDaemon ts) mClient
    case mClient of
      Just client -> hPutStrLn stderr $
        "tank: connected to daemon as " ++ show (pcPlugId client)
      Nothing -> hPutStrLn stderr "tank: running standalone (no daemon)"
```

Add needed imports:

```haskell
import qualified Data.Set as Set
import Tank.Core.Types (CellId(..), PlugCapability(..))
import Tank.Plug.Client (PlugClient, connectDaemon, sendMsg, disconnectPlug, pcPlugId)
import Tank.Daemon.Socket (socketPath)
import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Data.UUID.V4 (nextRandom)
```

**Step 2: Wire cell creation in createPane**

After creating the pane and inserting into tsPanes, send MsgCellCreate + MsgCellAttach if connected:

```haskell
createPane :: TermState -> Int -> Int -> IO Int
createPane ts cols rows = do
  paneId <- readIORef (tsNextPaneId ts)
  modifyIORef' (tsNextPaneId ts) (+ 1)
  (pty, ph) <- spawnWithPty Nothing True (tsShell ts) ["-l"] (cols, rows)
  pRunRef  <- newIORef True
  pOvRef   <- newIORef newOverlayState
  pAgRef   <- newIORef =<< newAgentState
  pVtRef   <- newIORef (mkVTerm cols rows)

  -- Generate CellId if connected to daemon
  mClient <- readIORef (tsDaemon ts)
  mCid <- case mClient of
    Nothing -> pure Nothing
    Just client -> do
      cuid <- nextRandom
      let cid = CellId cuid
          pid = pcPlugId client
      sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
        (MsgCellCreate cid ".")
      sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
        (MsgCellAttach cid pid)
      pure (Just cid)

  let pane = Pane pty pRunRef pOvRef pAgRef pVtRef mCid
  modifyIORef' (tsPanes ts) (IM.insert paneId pane)
  void $ forkIO $ paneReaderThread ts pane paneId
  void $ forkIO $ paneProcessWatcher ts paneId ph
  pure paneId
```

**Step 3: Disconnect on exit**

In `runTerminalPlug`, after `inputLoop ts`, add daemon disconnect in the `finally` block:

```haskell
    inputLoop ts `finally` do
      -- Disconnect from daemon
      mClient <- readIORef (tsDaemon ts)
      case mClient of
        Just client -> disconnectPlug client
        Nothing -> pure ()
      -- Restore terminal
      (_, finalRows) <- getTermSize
      ...
```

**Step 4: Build to verify it compiles**

Run: `nix develop -c cabal build all 2>&1 | grep -E '(error|Building|Linking)'`
Expected: Builds successfully

**Step 5: Run tests**

Run: `nix develop -c cabal test 2>&1 | grep -E '(FAIL|PASS|examples)'`
Expected: 88 examples, 0 failures

**Step 6: Commit**

```bash
git add src/Tank/Plug/Terminal.hs
git commit -m "feat: wire Terminal to daemon at startup and create cells for panes"
```

---

### Task 4: Forward PTY output as MsgOutput

When connected to daemon, `paneReaderThread` sends a copy of PTY output as MsgOutput so other attached plugs receive it.

**Files:**
- Modify: `src/Tank/Plug/Terminal.hs:260-295` (paneReaderThread)

**Step 1: Add MsgOutput forwarding**

In `paneReaderThread`, after the line `modifyIORef' (pVTerm pane) (vtFeed bs)`, add:

```haskell
              -- Forward to daemon for other plugs
              case pCellId pane of
                Nothing -> pure ()
                Just cid -> do
                  mClient <- readIORef (tsDaemon ts)
                  case mClient of
                    Nothing -> pure ()
                    Just client -> do
                      let pid = pcPlugId client
                      sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
                            (MsgOutput cid bs)
```

This goes right after `vtFeed` and before the rendering code.

**Step 2: Build to verify it compiles**

Run: `nix develop -c cabal build all 2>&1 | grep -E '(error|Building|Linking)'`
Expected: Builds successfully

**Step 3: Run tests**

Run: `nix develop -c cabal test 2>&1 | grep -E '(FAIL|PASS|examples)'`
Expected: 88 examples, 0 failures

**Step 4: Commit**

```bash
git add src/Tank/Plug/Terminal.hs
git commit -m "feat: forward PTY output to daemon as MsgOutput"
```

---

### Task 5: Daemon reader thread for remote input

Add a background thread that reads messages from the daemon and handles MsgInput from remote sources.

**Files:**
- Modify: `src/Tank/Plug/Terminal.hs` (add daemonReaderThread, spawn it at startup)

**Step 1: Add daemonReaderThread**

Add this function to `src/Tank/Plug/Terminal.hs`:

```haskell
-- | Background thread reading messages from the daemon.
-- Handles MsgInput from remote sources by writing to the appropriate PTY.
daemonReaderThread :: TermState -> PlugClient -> IO ()
daemonReaderThread ts client = go
  where
    go = do
      alive <- readIORef (tsRunning ts)
      when alive $ do
        result <- recvMsg client
        case result of
          Left _err -> pure ()  -- daemon disconnected, stop thread
          Right env -> do
            case mePayload env of
              MsgInput _cid bytes -> do
                -- Find pane with matching CellId and write to its PTY
                panes <- readIORef (tsPanes ts)
                let matching = [ p | p <- IM.elems panes
                               , pCellId p == Just _cid ]
                case matching of
                  (pane:_) -> writePty (pPty pane) bytes
                  []       -> pure ()
              _ -> pure ()  -- ignore other messages for now
            go
```

Add `recvMsg` to the Client import:

```haskell
import Tank.Plug.Client (PlugClient, connectDaemon, sendMsg, recvMsg, disconnectPlug, pcPlugId)
```

**Step 2: Spawn the thread at startup**

In `runTerminalPlug`, after writing `mClient` to `tsDaemon`, spawn the reader thread:

```haskell
    case mClient of
      Just client -> do
        hPutStrLn stderr $ "tank: connected to daemon as " ++ show (pcPlugId client)
        void $ forkIO $ daemonReaderThread ts client
      Nothing -> hPutStrLn stderr "tank: running standalone (no daemon)"
```

**Step 3: Build to verify it compiles**

Run: `nix develop -c cabal build all 2>&1 | grep -E '(error|Building|Linking)'`
Expected: Builds successfully

**Step 4: Run tests**

Run: `nix develop -c cabal test 2>&1 | grep -E '(FAIL|PASS|examples)'`
Expected: 88 examples, 0 failures

**Step 5: Commit**

```bash
git add src/Tank/Plug/Terminal.hs
git commit -m "feat: add daemon reader thread for remote MsgInput"
```

---

### Task 6: Cell cleanup on pane close

When a pane closes and it has a CellId, send MsgCellDetach and MsgCellDestroy to the daemon.

**Files:**
- Modify: `src/Tank/Plug/Terminal.hs:308-349` (paneProcessWatcher)

**Step 1: Add cell cleanup**

In `paneProcessWatcher`, after `modifyIORef' (tsPanes ts) (IM.delete paneId)` and before the window layout cleanup, add:

```haskell
      -- Notify daemon about cell destruction
      case pCellId pane of
        Nothing -> pure ()
        Just cid -> do
          mClient <- readIORef (tsDaemon ts)
          case mClient of
            Nothing -> pure ()
            Just client -> do
              let pid = pcPlugId client
              sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
                (MsgCellDetach cid pid)
              sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
                (MsgCellDestroy cid)
```

Note: the `pane` variable is already in scope from the `Just pane ->` pattern match. Access `pCellId pane` there.

**Step 2: Build to verify it compiles**

Run: `nix develop -c cabal build all 2>&1 | grep -E '(error|Building|Linking)'`
Expected: Builds successfully

**Step 3: Run tests**

Run: `nix develop -c cabal test 2>&1 | grep -E '(FAIL|PASS|examples)'`
Expected: 88 examples, 0 failures

**Step 4: Commit**

```bash
git add src/Tank/Plug/Terminal.hs
git commit -m "feat: send cell cleanup messages on pane close"
```

---

### Task 7: Integration test — plug client round-trip with daemon

Verify the full flow: client connects, creates cell, sends output, second client receives broadcast.

**Files:**
- Modify: `tests/Tank/Plug/ClientSpec.hs` (add integration test)

**Step 1: Write the integration test**

Add this test to `ClientSpec.hs`:

```haskell
  it "client creates cell and broadcasts output to second client" $ do
    withSystemTempDirectory "tank-client" $ \dir -> do
      let sockPath = dir ++ "/test.sock"
      daemonThread <- forkIO $ startDaemonAt sockPath
      threadDelay 200000

      -- Connect terminal plug (client 1)
      Just client1 <- connectDaemon sockPath "terminal" (Set.singleton CapTerminal)

      -- Connect observer plug (client 2)
      Just client2 <- connectDaemon sockPath "observer" Set.empty

      let pid1 = pcPlugId client1
          pid2 = pcPlugId client2

      -- Client 1 creates a cell
      cuid <- nextRandom
      let cid = CellId cuid
      sendMsg client1 $ MessageEnvelope 1 pid1 TargetBroadcast 0
        (MsgCellCreate cid "/tmp")
      threadDelay 50000

      -- Both attach
      sendMsg client1 $ MessageEnvelope 1 pid1 TargetBroadcast 0
        (MsgCellAttach cid pid1)
      sendMsg client2 $ MessageEnvelope 1 pid2 TargetBroadcast 0
        (MsgCellAttach cid pid2)
      threadDelay 50000

      -- Client 1 sends output
      sendMsg client1 $ MessageEnvelope 1 pid1 TargetBroadcast 0
        (MsgOutput cid "hello world")

      -- Both should receive broadcast
      resp1 <- recvMsg client1
      case resp1 of
        Right env -> mePayload env `shouldBe` MsgOutput cid "hello world"
        Left err  -> expectationFailure $ "client1 broadcast failed: " ++ err

      resp2 <- recvMsg client2
      case resp2 of
        Right env -> mePayload env `shouldBe` MsgOutput cid "hello world"
        Left err  -> expectationFailure $ "client2 broadcast failed: " ++ err

      disconnectPlug client1
      disconnectPlug client2
      killThread daemonThread
```

Add needed imports at the top:

```haskell
import Control.Concurrent (forkIO, threadDelay, killThread)
import Data.UUID.V4 (nextRandom)
import Tank.Core.Types (CellId(..), PlugId(..), PlugInfo(..), PlugCapability(..))
import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Plug.Client (connectDaemon, sendMsg, recvMsg, disconnectPlug, pcPlugId)
```

**Step 2: Run test to verify it passes**

Run: `nix develop -c cabal test 2>&1 | grep -E '(FAIL|PASS|examples)'`
Expected: 89 examples, 0 failures (1 new test)

**Step 3: Commit**

```bash
git add tests/Tank/Plug/ClientSpec.hs
git commit -m "test: add plug client integration test for output broadcast"
```

---

## Summary

| Task | What | Tests added |
|------|------|-------------|
| 1 | `Tank.Plug.Client` module | 2 (connect + no-daemon) |
| 2 | Add `pCellId` to Pane, `tsDaemon` to TermState | 0 (data only) |
| 3 | Connect to daemon at startup, create cells | 0 (wiring) |
| 4 | Forward PTY output as MsgOutput | 0 (side-channel) |
| 5 | Daemon reader thread for remote input | 0 (background thread) |
| 6 | Cell cleanup on pane close | 0 (lifecycle) |
| 7 | Integration test — full round-trip | 1 |

Total: 3 new tests, ~120 lines of new code, ~30 lines modified.
