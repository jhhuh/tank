# Tank Development Log

Append-only. Newest entries at the bottom.

---

## 2026-03-04 — Project inception

**Why tank exists:**
Inspired by tmux's terminal multiplexer architecture, but designed from scratch
as a protocol-centric workspace system. The tmux codebase was analyzed and found
to be highly monolithic (15+ global variables, no plugin system, tightly coupled
subsystems) — not suitable for forking or library use.

**Key design decisions:**
- Protocol-first: Cap'n Proto binary schema as the source of truth
- Everything is a plug: terminal UI, coding agents, devshell manager
- CRDT state sync with spatial jitter buffer for terminal screens
- Epoch-based clear screen (O(1) instead of O(W×H))
- Transport fallback: QUIC → TCP → WebSocket
- Hub daemon topology with tank-to-tank federation
- Named after Tank from The Matrix (the operator)
- Plugs called "plugs" (from "plugged in" to the Matrix)

**IDL decision:** Cap'n Proto chosen over FlatBuffers/Protobuf/MsgPack.
Reasons: zero-copy reads, mutable messages (for in-place CRDT cell updates),
canonical form (byte-equality for convergence checks), cache-friendly
fixed-offset reads (no vtable indirection).

**Language decision:** Haskell first (easiest to inspect for the author),
then Rust, then Zig. Protocol spec is language-agnostic.

**Terminal screen CRDT innovations:**
1. Spatial jitter buffer: hidden above (scrollback cache) + live screen +
   hidden below (absorbs early-arriving content). All addressed by absolute
   line numbers.
2. Epoch-based clear: clear screen increments an epoch counter (one CRDT op).
   Cells tagged with old epochs are treated as blank.
3. Viewport position as independent CRDT value: content and viewport updates
   can arrive in any order.

**References:**
- Protocol design: `docs-site/docs/protocol.md`
- Architecture: `docs-site/docs/architecture.md`
- Mosh paper: https://mosh.org/mosh-paper.pdf

---

## 2026-03-05 — Terminal multiplexer features + VT100 emulator

**Root cause of terminal freeze:** Missing `-threaded` GHC flag. Without it,
all `forkIO` green threads share one OS thread, so `threadWaitRead` on stdin
starved the PTY reader thread. Fixed by adding `-threaded -rtsopts -with-rtsopts=-N`.

**VT100 emulator:** Built from scratch (~600 lines). Supports: cursor movement,
SGR (16+256 colors, bold/dim/underline/inverse), erase (ED/EL/ECH), scroll
regions (DECSTBM), insert/delete line/char, alt screen, line wrapping, resize.
Scrollback buffer (1000 lines max). 46 tests.

**Multi-window + pane splitting:** Windows have layout trees
(`LPane | LSplit dir ratio l1 l2`). Ctrl-B c/n/p/0-9 for windows,
Ctrl-B %/" for splits, Ctrl-B o to cycle panes. Single-pane windows use
raw PTY passthrough; multi-pane renders from VTerm grid with SGR attributes.

**Agent overlay improvements:** Tool use/results now display in real-time via
progress callback. Overlay shows `[tool: execute: ls]` and `→ result...`
messages with status updates.

**Copy mode:** Ctrl-B [ enters copy mode. j/k/Ctrl-U/Ctrl-D to scroll through
scrollback. q/Escape to exit. Renders scrollback + screen with full SGR attrs.

**Key bugs fixed:**
- UTF-8 rendering: `BS8.pack` truncates Unicode > 0xFF. Use `encodeUtf8` everywhere.
- Overlay close: Ctrl-B was consumed by overlay handler. Restructured input loop
  so prefix detection happens before overlay routing.
- Scroll region: Set DECSTBM to confine PTY output above status line.

## 2026-03-06 — Concept mockup renderer + layout language vision

**Mockup renderer:**
Created `docs-site/docs/assets/concepts/render-concepts.py` — generates terminal
concept images showing how tank will look (8 scenarios: idle, overlay, tool-exec,
multi-pane, copy-mode, window switching, detach/reattach).

Evolution: SVG (manual) → ANSI+aha+wkhtmltoimage (HTML unstable) → **Pillow direct
rendering** (current). Pillow approach: ANSI output → parse into cell grid → render
each cell with DejaVu Sans Mono TTF → window chrome via Pillow drawing primitives.
Packaged as nix derivation (`nix build .#concept-images`). No HTML, no browser.

**Future: terminal layout DSL + independent rendering package**

User vision (captured from conversation):
- "Maybe a language that acts like HTML/CSS but for terminal console"
- "Layout language is what we need"
- "Independent cabal package so we can publish independently"
- "Can we use libvterm without GUI backend? Hijack the draw command stream"
- "UI/UX is very important — design is a key point of this project"

Proposed architecture for `tank-render` (independent cabal package):
1. **Layout DSL** — declarative terminal UI descriptions (panes, overlays,
   status bars, borders) analogous to HTML/CSS for terminals
2. **VT100 state machine** — libvterm FFI or tank's own parser. Feeds ANSI
   into a virtual screen buffer, reads back cell grid (char + attrs)
3. **Pixel renderer** — reads cell grid + monospace TTF font, renders to PNG.
   No xorg/GUI needed — just font rasterization (freetype) + image output
4. **Dual-target** — same layout description renders both to live terminal
   (ANSI output) and to static images (PNG for docs)

This package would serve both tank's documentation and its actual UI renderer,
ensuring the concept images exactly match the real product.

## 2026-03-06 — Task 7: PNG rendering backend

Added `Tank.Layout.Backend.PNG` module that renders `CellGrid` to PNG images
using JuicyPixels (image encoding), FontyFruity (font loading/metrics), and
Rasterific (vector graphics rasterization to JuicyPixels images).

**Architecture decisions:**
- Rasterific's `renderDrawing` produces `Image PixelRGBA8` directly, which
  JuicyPixels `encodePng` serializes. No intermediate bitmap manipulation needed.
- Font metrics via `stringBoundingBox` on "M" character determine monospace
  cell dimensions (same approach as the Python renderer).
- `printTextAt` from Rasterific handles glyph rasterization — FontyFruity alone
  only loads fonts, it doesn't render glyphs to pixels.

**What's implemented:**
- `renderPNG :: PNGConfig -> CellGrid -> IO LBS.ByteString` — full pipeline
- Window chrome: title bar, traffic light dots, rounded corners, centered title
- Tokyo Night palette matching render-concepts.py constants
- Per-cell background fill + foreground character rendering
- Configurable: font path, font size, title bar toggle, padding

**What's deferred (Task 8):**
- Box-drawing character special rendering (lines instead of font glyphs)
- Rounded corner clipping/masking on the window frame
- Bold/dim style modifiers in the PNG output
- Actual visual verification (test is `pendingWith` — needs TTF font at runtime)

---

## 2026-03-06 — Task 8: Concept image reproduction

**Goal:** Port the 9 concept scenarios from render-concepts.py to the Haskell eDSL.

**Render.hs fixes (prerequisites):**
1. `stampContent` for `Text` spans was losing all per-span styling. `spansToLines`
   concatenated all text into plain `Text`, then `stampLine` stamped with `Default`
   colors. Replaced with `stampSpans` that iterates character-by-character through
   spans, preserving fg color, bold, and dim from each `SpanStyle`.
2. `drawBorder` only rendered the left title. Added right hint title rendering
   (positioned at `rx + rw - 2 - hintLen`).

**Approach:**
- Span helpers: `s` (plain), `c` (colored), `b` (bold+color), `d` (dim+color)
- Layout helpers: `padLine`, `padTo`, `padInner`, `statusBar`, `interiorSep`
- Each scenario is a `Layout` value built with eDSL combinators
- Overlays use `Styled` with `Border Rounded blue` for the box, interior separators
  are horizontal line characters rendered as colored span content
- Scenario 09 (detach) stacks 3 grids vertically with gap rows between them

**All 9 scenarios generate successfully:**
01-idle, 02-overlay, 03-tool-exec, 04-multi-pane, 05-multi-agent,
06-windows, 07-services, 08-services-logs, 09-detach

**Remaining rough edges:**
- Scenario 09 renders as one tall window frame (no per-frame chrome or arrows)
- No background color support on status bar spans (barBg is approximated via styled text)
- Interior separator lines are content-based (horizontal line chars), not true box separators
- Bold/dim not visually distinct in PNG output (PNG backend doesn't vary font weight yet)
