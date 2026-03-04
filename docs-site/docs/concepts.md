# Concepts

!!! warning "Work in Progress"

    These are concept mockups showing how Tank will look. They are generated
    programmatically from
    [`render-concepts.py`](https://github.com/jhhuh/tank/blob/master/docs-site/docs/assets/concepts/render-concepts.py)
    and reflect the current design direction — not a finished product.

    To regenerate: `nix build .#concept-images`

## 01 — Idle terminal

A single pane with a shell prompt. The status bar shows the session name,
active window, working directory, and available key bindings.

![Idle terminal](assets/concepts/01-idle.png)

## 02 — Agent overlay

Each pane has a per-pane coding agent called the **operator**. Press `Ctrl-B a`
to open the overlay. The overlay is a fixed-height popup pinned to the bottom
of the pane — terminal output remains visible above it.

![Agent overlay](assets/concepts/02-overlay.png)

## 03 — Agent tool execution

When the operator needs extended space for multi-step tool execution (reading
files, writing fixes, running tests), the overlay expands to fill the entire
pane area while maintaining its boundary box.

![Agent tool execution](assets/concepts/03-tool-exec.png)

## 04 — Multi-pane layout

Vertical and horizontal splits with independent shells. Each pane runs its own
PTY and can have its own operator instance.

![Multi-pane split](assets/concepts/04-multi-pane.png)

## 05 — Multi-pane with per-pane agents

Each pane gets its own independent operator. One pane's agent can fix tests
while another reviews code — they don't interfere with each other.

![Multi-pane agents](assets/concepts/05-multi-agent.png)

## 06 — Command palette

Window switching and keybinding help via a centered command palette overlay.
Similar to VS Code's command palette but for terminal workspace management.

![Command palette](assets/concepts/06-windows.png)

## 07 — Per-project services

The services overlay (`Ctrl-B s`) manages project daemons defined in a
Procfile. Shows a tree view of services with their status (running, crashed,
starting) alongside Procfile definitions. Start, stop, restart, and connect
to services from the overlay.

![Services overlay](assets/concepts/07-services.png)

## 08 — Services log view

Press `Tab` in the services overlay to switch to the log view. Daemon logs are
stacked on the left with labeled horizontal dividers per service. The tree view
sidebar on the right shows service status at a glance.

![Services logs](assets/concepts/08-services-logs.png)

## 09 — Detach and reattach

Sessions persist when you detach (`Ctrl-B d`). Processes keep running in the
daemon. Reattach from any terminal — even a different machine once federation
is implemented.

![Detach and reattach](assets/concepts/09-detach.png)
