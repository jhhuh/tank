# Plug Client & Terminal Daemon Wiring Design

## Goal

Create a reusable plug client library and wire Terminal.hs to optionally connect to the daemon, enabling multi-plug coordination while preserving the fast local PTY path.

## Context

The daemon router (Gap #1) and I/O routing (Gap #2) are complete. Terminal.hs runs standalone — it owns PTYs, reads output, handles input, and renders, all locally. It needs to speak the tank protocol so other plugs can attach to cells and receive output.

## Architecture

**Approach: Side-channel daemon connection.** Terminal.hs keeps its direct PTY I/O for local rendering (no latency regression). A daemon connection runs alongside for lifecycle management and forwarding output copies to other attached plugs.

### Tank.Plug.Client module

Reusable client library for any plug to connect to the daemon:

```haskell
data PlugClient = PlugClient
  { pcHandle :: !Handle
  , pcPlugId :: !PlugId
  }

-- Try connecting to daemon. Returns Nothing if daemon isn't running.
connectDaemon :: String -> PlugInfo -> IO (Maybe PlugClient)

-- Send a message envelope to the daemon.
sendMsg :: PlugClient -> MessageEnvelope -> IO ()

-- Read a message from the daemon. Returns Left on EOF/error.
recvMsg :: PlugClient -> IO (Either String MessageEnvelope)

-- Deregister and disconnect.
disconnectPlug :: PlugClient -> IO ()
```

`connectDaemon` tries the socket, registers via MsgPlugRegister, waits for MsgPlugRegistered ack. Returns `Nothing` on connection failure (daemon not running). This makes daemon connection optional.

### Terminal.hs changes

| Component | Change |
|-----------|--------|
| `TermState` | Add `tsDaemon :: IORef (Maybe PlugClient)` |
| `Pane` | Add `pCellId :: !(Maybe CellId)` |
| `createPane` | If connected: generate CellId, send `MsgCellCreate` + `MsgCellAttach` |
| `paneReaderThread` | After feeding VTerm, also send `MsgOutput cid bytes` if connected |
| New: `daemonReaderThread` | Background thread reading daemon messages; handles `MsgInput` from remote sources, `MsgOutput` from remote cells |
| Pane close | Send `MsgCellDetach` + `MsgCellDestroy` if connected |
| `runTerminalPlug` | Try `connectDaemon` at startup, store in TermState |

### Input multiplexing

`inputLoop` continues blocking on `threadWaitRead stdInput`. A separate `daemonReaderThread` (spawned via `forkIO`) reads daemon messages independently. This matches the existing `paneReaderThread` pattern — each source has its own blocking reader thread.

### Message flow (connected mode)

```
Local user input:
  stdin → inputLoop → writePty(pane) [direct, unchanged]

Local PTY output:
  PTY fd → paneReaderThread → vtFeed(VTerm) → render [direct, unchanged]
                            → sendMsg(MsgOutput cid bytes) [side-channel to daemon]

Remote input (future):
  daemon → daemonReaderThread → MsgInput → writePty(matching pane)

Other plug receives output:
  daemon broadcasts MsgOutput to all attached plugs
```

### Testing

- Unit: Client connect → register → send/recv round-trip
- Integration: Terminal plug registers, creates cell, sends MsgOutput; second client receives broadcast

## Key Decisions

1. **Optional daemon** — Terminal.hs works standalone if daemon isn't running
2. **Direct PTY path preserved** — No latency regression for local rendering
3. **Separate reader thread** — Consistent with existing paneReaderThread pattern, simpler than fd multiplexing
4. **Reusable Client module** — Any future plug (operator, devshell) uses the same library
5. **CellId on Pane** — Maps local pane ID to daemon cell for message routing
