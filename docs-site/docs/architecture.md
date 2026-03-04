# Architecture

## Overview

Tank uses a **hub daemon** model. A central daemon owns all state and
coordinates plugs via a Cap'n Proto binary protocol.

```
┌──────────────────────────────────────────┐
│              tank daemon                 │
│                                          │
│  ┌──────────┐ ┌────────┐ ┌───────────┐  │
│  │  state   │ │ router │ │federation │  │
│  │  (CRDT)  │ │        │ │(tank↔tank)│  │
│  └────┬─────┘ └───┬────┘ └─────┬─────┘  │
│       │            │            │        │
└───────┼────────────┼────────────┼────────┘
        │            │            │
   ┌────┴──┐   ┌─────┴───┐  ┌────┴─────┐
   │term UI│   │ operator │  │ devshell │   ...more plugs
   │ plug  │   │  plug    │  │  plug    │
   └───────┘   └──────────┘  └──────────┘
```

## Everything Is a Plug

The terminal UI, coding agent, devshell manager, and process manager are all
plugs. They connect to the daemon via the same protocol, register their
capabilities, and communicate through CRDT state updates.

A plug:

1. Connects to the daemon (Unix socket or network)
2. Sends `PlugRegister` with its capabilities
3. Receives `CellAttach` when assigned to cells
4. Reads/writes CRDT state for its cells
5. Optionally subscribes to other plugs' state changes

## Cells

A **cell** is the fundamental unit of work. Cells have:

- **ID**: globally unique UUID (for federation)
- **Directory**: working directory (drives devshell activation)
- **Environment**: key-value env vars (inheritable)
- **Attached plugs**: which plugs are active on this cell
- **State**: CRDT-replicated state owned by each plug

Cells are not limited to terminal panes. A cell can be:

- A terminal pane (term UI plug provides terminal emulation)
- A background process group (process manager plug)
- An agent workspace (operator plug manages conversation state)
- A construct (ephemeral sandbox cell)

## CRDT State Model

All shared state uses conflict-free replicated data types (CRDTs):

| State type | CRDT type | Use |
|------------|-----------|-----|
| Terminal grid | Epoch-tagged LWW per cell | Screen sync |
| Grid epoch | LWW (monotonic u64) | Clear screen |
| Viewport position | LWW (monotonic u64) | Scroll anchor |
| Environment vars | OR-Map of LWW-Registers | Devshell env |
| Agent history | Grow-only sequence | Conversation log |
| Process list | OR-Set | Running services |

CRDTs guarantee convergence regardless of message delivery order, enabling
correct operation on any transport (QUIC, TCP, WebSocket).

## Transport

```
Preferred:   QUIC (unreliable datagrams + reliable streams)
Fallback 1:  TCP + TLS
Fallback 2:  WebSocket over TLS on port 443
Local:       Unix domain socket
```

## Federation

Tank daemons can federate to migrate sessions across machines:

1. Discovery (manual config, mDNS, or registry)
2. Handshake (auth, capabilities, transport negotiation)
3. Cell migration: CRDT snapshot → dual-write phase → redirect → cleanup
4. Split execution: some plugs local, others remote on the same cell
