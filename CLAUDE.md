# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Tank is a protocol-centric workspace system. Named after Tank from The Matrix
(the operator who loads programs, monitors the crew, and runs the console).

Tank is NOT a terminal multiplexer — terminal multiplexing is one capability
among many. Tank manages developer workspaces: terminal panes, coding agents,
devshells, per-project services, and seamless migration across machines.

## Build Commands

```bash
nix develop             # Enter dev shell
cabal build all         # Build everything
cabal test              # Run tests
cabal run tank          # Run the tank binary
```

## Directory Layout

```
tank/
  schema/               Cap'n Proto protocol definitions (source of truth)
  src/Tank/
    Core/               CRDT types, protocol messages, core types
    Daemon/             Hub daemon: socket server, router, state management
    Plug/
      Terminal.hs       Terminal UI plug (raw ANSI, posix-pty, input handling)
      Operator.hs       Per-pane coding agent (Claude API integration)
      Operator/
        Overlay.hs      Agent overlay rendering (ANSI popup over terminal)
        Tools.hs        Agent tool implementations (read, write, execute, grep)
    Terminal/
      Grid.hs           VT100 grid with CRDT-compatible cell storage
  app/                  CLI entry point
  tests/                HSpec test suites
  docs-site/            MkDocs Material documentation site
  artifacts/
    devlog.md           Design decisions and history (append-only)
    logs/               Test output, build logs
```

## Architecture

- **Hub daemon** owns all state, coordinates plugs via Cap'n Proto over Unix sockets
- **Everything is a plug**: terminal UI, coding agent, devshell manager
- **Cells** are the universal unit: panes, agents, devshells, processes
- **CRDT state model**: epoch-tagged LWW grid with spatial jitter buffer
- **Federation**: tank-to-tank CRDT replication (future)

## Conventions

- Haskell, GHC 9.6+, cabal build system
- Tests with HSpec, TDD workflow
- Cap'n Proto schema in `schema/` is the protocol source of truth
- Commit messages: conventional commits, prefix-strip safe for subtree split

## Agent Overlay

Each terminal pane has a per-pane coding agent (Operator) powered by the Claude API.

- **Toggle**: `Ctrl-B a` opens/closes the agent overlay popup
- **Input**: Type a prompt and press Enter to send to the agent
- **Tools**: The agent can read/write files, execute commands, and grep
- **Env var**: Set `ANTHROPIC_API_KEY` to enable agent functionality

## Key Design Documents

- `artifacts/devlog.md` — project history and decisions
- Protocol design: `docs-site/docs/protocol.md`
- Architecture: `docs-site/docs/architecture.md`
- Screen sync (CRDT jitter buffer): `docs-site/docs/screen-sync.md`

## Vocabulary

| Term | Meaning |
|------|---------|
| tank | The daemon and the system |
| plug | A capability module that speaks the tank protocol |
| cell | A unit of work: pane, process, agent context |
| operator | Per-cell coding agent |
| construct | Ephemeral scratchpad/sandbox |
