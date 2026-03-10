# Tank

Plan 9 in Unix.

A programmable runtime for composing live computing environments,
disguised as a terminal multiplexer.

## Vision

Emacs brought the Lisp Machine into Unix — a live, introspectable,
programmable-all-the-way-down runtime wearing the skin of a text editor.

Tank brings Plan 9 into Unix — per-process namespaces, a semantic wire
protocol, and synthetic servers wearing the skin of a terminal multiplexer.

### Core ideas

- **Pane as virtual POSIX environment.** Each pane is an isolated namespace
  with its own cwd, env, fd table, and process group — logical overlays
  that sync to any backend (local shell, remote machine, container, DAG).
- **POSIX semantics as the universal interface.** `cd`, `ls`, `cat`, `stat`
  work everywhere — filesystems, git histories, k8s clusters, nix stores,
  arbitrary DAGs. The verbs are universal; backends decide what they mean.
- **Semantic wire protocol.** Not bytes over a pipe. The protocol speaks
  POSIX operations natively — spawn, signal, env change, cwd change — so
  the multiplexer can hook, route, intercept, and replay everything.
- **Backend-agnostic.** A pane connects to a backend plug over any transport.
  No SSH dependency. No kernel namespaces. Just a protocol.
- **Rendering is separate.** Pane data, visual presentation, and output
  target are three independent programmable layers.

### Previous work

The terminal multiplexer prototype lives on `archive/v0-multiplexer`.
