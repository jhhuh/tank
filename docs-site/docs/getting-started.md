# Getting Started

## Prerequisites

- [Nix](https://nixos.org/) with flakes enabled
- Linux (macOS support planned)

## Build

```bash
git clone <repo-url>
cd tank
nix develop        # Enter dev shell with all dependencies
cabal build all    # Build library, executable, and tests
```

## Run

### Standalone Terminal

```bash
cabal run tank
```

This launches a single terminal pane running your `$SHELL`. The status line
at the bottom shows tank's state.

### Key Bindings

| Keys | Action |
|------|--------|
| `Ctrl-B` | Prefix key (like tmux) |
| `Ctrl-B a` | Toggle agent overlay |
| `Ctrl-B q` | Quit |
| `Ctrl-B d` | Detach |
| `Ctrl-B b` | Send literal Ctrl-B to the shell |

### Agent Overlay

Tank includes a per-pane coding agent powered by the Claude API. To use it:

1. Set the `ANTHROPIC_API_KEY` environment variable
2. Press `Ctrl-B a` to open the agent overlay
3. Type a prompt and press Enter to send it to the agent
4. The agent can read/write files, execute commands, and grep your codebase
5. Press `Ctrl-B a` again or `Escape` to close the overlay

### Run Tests

```bash
cabal test --enable-tests
```

## Build Documentation

```bash
nix build .#docs    # Build static HTML docs
# or for live preview:
mkdocs serve -f docs-site/mkdocs.yml
```

## Project Structure

```
tank/
  schema/               Cap'n Proto protocol definitions
  src/Tank/
    Core/               CRDT types, protocol messages
    Daemon/             Hub daemon (socket, router, state)
    Plug/
      Terminal.hs       Terminal UI (raw ANSI, posix-pty)
      Operator.hs       Per-pane coding agent (Claude API)
      Operator/
        Overlay.hs      Agent overlay rendering
        Tools.hs        Agent tool implementations
    Terminal/
      Grid.hs           VT100 grid with CRDT cell storage
  app/                  CLI entry point
  tests/                HSpec test suites
  docs-site/            This documentation
```
