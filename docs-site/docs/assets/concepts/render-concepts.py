#!/usr/bin/env python3
"""Generate terminal concept mockups for Tank.

Renders directly to PNG using Pillow — no HTML, no browser dependency.
Requires: python3, pillow, a monospace TTF font (DejaVu Sans Mono).

Usage:
  python3 render-concepts.py list                    # list all scenarios
  python3 render-concepts.py <name>                  # render one scenario
  python3 render-concepts.py all                     # render all (to files)
  python3 render-concepts.py all --font /path/to.ttf # explicit font
  python3 render-concepts.py all --outdir /tmp/out   # custom output dir
"""
import sys
import os
import re
import subprocess
import unicodedata
import argparse
from PIL import Image, ImageDraw, ImageFont

# --- ANSI helpers ---
RST = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
UL = "\033[4m"
INV = "\033[7m"

def fg(r, g, b): return f"\033[38;2;{r};{g};{b}m"
def bg(r, g, b): return f"\033[48;2;{r};{g};{b}m"

# Tokyo Night palette
BG      = bg(26, 27, 38)
BG_BAR  = bg(36, 40, 59)
FG      = fg(192, 202, 245)
FG_DIM  = fg(86, 95, 137)
FG_BLUE = fg(122, 162, 247)
FG_GRN  = fg(158, 206, 106)
FG_RED  = fg(247, 118, 142)
FG_YEL  = fg(224, 175, 104)
FG_PUR  = fg(187, 154, 247)
FG_ORG  = fg(255, 158, 100)
FG_CYAN = fg(125, 207, 255)
FG_GREY = fg(169, 177, 214)

W = 120  # terminal width (columns)
H = 36   # terminal height (rows, for padding shorter scenarios)

ANSI_RE = re.compile(r'\033\[[^m]*m')

def display_width(s):
    """Calculate display width of a string, accounting for wide chars."""
    clean = ANSI_RE.sub('', s)
    w = 0
    for ch in clean:
        eaw = unicodedata.east_asian_width(ch)
        if eaw in ('W', 'F'):
            w += 2
        else:
            w += 1
    return w


def char_width(ch):
    """Display width of a single character."""
    eaw = unicodedata.east_asian_width(ch)
    return 2 if eaw in ('W', 'F') else 1


# --- ANSI parser ---

# Default colors (Tokyo Night)
DEF_FG = (0xc0, 0xca, 0xf5)
DEF_BG = (0x1a, 0x1b, 0x26)


def parse_ansi(text):
    """Parse ANSI text into a list of lines, each a list of (char, fg, bg, bold)."""
    lines = []
    cur = []
    fg, bg_c, bold = DEF_FG, DEF_BG, False
    i = 0
    n = len(text)
    while i < n:
        if text[i] == '\033' and i + 1 < n and text[i + 1] == '[':
            # Scan for 'm'
            j = i + 2
            while j < n and text[j] != 'm':
                j += 1
            params = text[i + 2:j]
            i = j + 1
            # Parse SGR params
            parts = params.split(';') if params else ['0']
            k = 0
            while k < len(parts):
                p = int(parts[k]) if parts[k].isdigit() else 0
                if p == 0:
                    fg, bg_c, bold = DEF_FG, DEF_BG, False
                elif p == 1:
                    bold = True
                elif p == 2:
                    pass  # dim — colors already handle this
                elif p == 38 and k + 4 < len(parts) and parts[k + 1] == '2':
                    fg = (int(parts[k + 2]), int(parts[k + 3]), int(parts[k + 4]))
                    k += 4
                elif p == 48 and k + 4 < len(parts) and parts[k + 1] == '2':
                    bg_c = (int(parts[k + 2]), int(parts[k + 3]), int(parts[k + 4]))
                    k += 4
                k += 1
        elif text[i] == '\n':
            lines.append(cur)
            cur = []
            i += 1
        else:
            cur.append((text[i], fg, bg_c, bold))
            i += 1
    if cur:
        lines.append(cur)
    return lines


# --- Font discovery ---

# --- Box-drawing: draw as lines, not font glyphs (like tmux ACS) ---

def _draw_box(draw, ch, x, y, w, h, color):
    """Draw a box-drawing character as actual lines/arcs for pixel-perfect connection."""
    cx = x + w // 2  # center x
    cy = y + h // 2  # center y
    rx = x + w       # right edge
    bt = y + h       # bottom edge
    lw = max(1, w // 8)  # line width
    cr = w // 2      # corner radius for rounded chars

    # Straight-line characters
    straight = {
        '│': [(cx, y, cx, bt)],
        '─': [(x, cy, rx, cy)],
        '├': [(cx, y, cx, bt), (cx, cy, rx, cy)],
        '┤': [(cx, y, cx, bt), (x, cy, cx, cy)],
        '┬': [(x, cy, rx, cy), (cx, cy, cx, bt)],
        '┴': [(x, cy, rx, cy), (cx, y, cx, cy)],
        '┼': [(cx, y, cx, bt), (x, cy, rx, cy)],
        '┌': [(cx, cy, cx, bt), (cx, cy, rx, cy)],
        '┐': [(cx, cy, cx, bt), (x, cy, cx, cy)],
        '└': [(cx, y, cx, cy), (cx, cy, rx, cy)],
        '┘': [(cx, y, cx, cy), (x, cy, cx, cy)],
    }
    segs = straight.get(ch)
    if segs is not None:
        for x1, y1, x2, y2 in segs:
            draw.line([(x1, y1), (x2, y2)], fill=color, width=lw)
        return True

    # Rounded corners — draw arcs + connecting lines
    if ch == '╭':  # top-left: lines go down + right, arc in bottom-right
        draw.arc([cx, cy, cx + 2 * cr, cy + 2 * cr], 180, 270, fill=color, width=lw)
        draw.line([(cx, cy + cr), (cx, bt)], fill=color, width=lw)
        draw.line([(cx + cr, cy), (rx, cy)], fill=color, width=lw)
    elif ch == '╮':  # top-right: lines go down + left, arc in bottom-left
        draw.arc([cx - 2 * cr, cy, cx, cy + 2 * cr], 270, 360, fill=color, width=lw)
        draw.line([(cx, cy + cr), (cx, bt)], fill=color, width=lw)
        draw.line([(x, cy), (cx - cr, cy)], fill=color, width=lw)
    elif ch == '╰':  # bottom-left: lines go up + right, arc in top-right
        draw.arc([cx, cy - 2 * cr, cx + 2 * cr, cy], 90, 180, fill=color, width=lw)
        draw.line([(cx, y), (cx, cy - cr)], fill=color, width=lw)
        draw.line([(cx + cr, cy), (rx, cy)], fill=color, width=lw)
    elif ch == '╯':  # bottom-right: lines go up + left, arc in top-left
        draw.arc([cx - 2 * cr, cy - 2 * cr, cx, cy], 0, 90, fill=color, width=lw)
        draw.line([(cx, y), (cx, cy - cr)], fill=color, width=lw)
        draw.line([(x, cy), (cx - cr, cy)], fill=color, width=lw)
    else:
        return False
    return True


BOX_CHARS = set('│─╭╮╰╯├┤┬┴┼┌┐└┘')


def find_font():
    """Locate DejaVu Sans Mono TTF."""
    try:
        r = subprocess.run(
            ["fc-match", "-f", "%{file}", "DejaVu Sans Mono"],
            capture_output=True, text=True)
        p = r.stdout.strip()
        if p and os.path.exists(p):
            return p
    except FileNotFoundError:
        pass
    for p in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
    ]:
        if os.path.exists(p):
            return p
    return None

_lines = 0

def line(text="", pad=True):
    """Print a line, padded to terminal width with background color."""
    global _lines
    _lines += 1
    if pad:
        text += " " * max(0, W - display_width(text))
    print(f"{BG}{text}{RST}")

def bar(text):
    """Status bar line."""
    global _lines
    _lines += 1
    text += " " * max(0, W - display_width(text))
    print(f"{BG_BAR}{text}{RST}")

def blank(n=1):
    for _ in range(n):
        line()

def pad_remaining(fill_fn=None):
    """Pad content rows to H-1 (leaving room for status bar)."""
    global _lines
    while _lines < H - 1:
        if fill_fn:
            fill_fn()
        else:
            blank()

def reset_lines():
    global _lines
    _lines = 0

def fullbar(text, bg_color, fg_color):
    """Print a full-width highlighted bar (e.g., copy mode, detach message)."""
    global _lines
    _lines += 1
    text += " " * max(0, W - len(text))
    print(f"{bg_color}{fg_color}{BOLD}{text}{RST}")

def prompt(path="~/projects/webapp"):
    return f"{FG_BLUE}{path}{RST}{BG} {FG_GRN}>${RST}{BG} "

# Box drawing with rounded corners
def box_top(x, w):
    pad = " " * x
    return f"{pad}{FG_BLUE}╭{'─' * (w-2)}╮{RST}{BG}"

def box_mid(x, w, content=""):
    pad = " " * x
    inner = w - 4
    content += " " * max(0, inner - display_width(content))
    return f"{pad}{FG_BLUE}│{RST}{BG} {content} {FG_BLUE}│{RST}{BG}"

def box_sep(x, w):
    pad = " " * x
    return f"{pad}{FG_BLUE}├{'─' * (w-2)}┤{RST}{BG}"

def box_bot(x, w):
    pad = " " * x
    return f"{pad}{FG_BLUE}╰{'─' * (w-2)}╯{RST}{BG}"


# --- Scenarios ---

def scenario_01_idle():
    """Single pane -- idle terminal with status bar"""
    line(f" {prompt()} git status")
    line(f" {FG_GREY}On branch main{RST}{BG}")
    line(f" {FG_GREY}Changes not staged for commit:{RST}{BG}")
    line(f"   {FG_RED}modified:   src/App.tsx{RST}{BG}")
    line(f"   {FG_RED}modified:   src/api/client.ts{RST}{BG}")
    line(f" {FG_GREY}Untracked files:{RST}{BG}")
    line(f"   {FG_GRN}src/components/Dashboard.tsx{RST}{BG}")
    blank()
    line(f" {prompt()} npm test")
    line(f" {FG_GREY}PASS  src/App.test.tsx{RST}{BG}")
    line(f"   {FG_GRN}ok renders without crashing (12ms){RST}{BG}")
    line(f"   {FG_GRN}ok displays navigation (8ms){RST}{BG}")
    line(f" {FG_RED}FAIL  src/api/client.test.ts{RST}{BG}")
    line(f"   {FG_RED}x  handles timeout errors (15ms){RST}{BG}")
    line(f" {FG_GREY}Tests: 1 failed, 2 passed, 3 total{RST}{BG}")
    blank()
    line(f" {prompt()} _")
    pad_remaining()
    bar(f" {FG_GRN}{BOLD}tank{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_BLUE}0:bash{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}~/projects/webapp{RST}{BG_BAR}                              {FG_DIM}Ctrl-B a: agent{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}idle{RST}{BG_BAR}")


def scenario_02_overlay():
    """Agent overlay open -- fixed-height overlay pinned to bottom"""
    # Terminal content visible above overlay
    line(f" {prompt()} npm test")
    line(f" {FG_GREY}PASS  src/App.test.tsx{RST}{BG}")
    line(f"   {FG_GRN}ok renders without crashing (12ms){RST}{BG}")
    line(f" {FG_RED}FAIL  src/api/client.test.ts{RST}{BG}")
    line(f"   {FG_RED}x  handles timeout errors (15ms){RST}{BG}")
    line(f" {FG_GREY}Tests: 1 failed, 2 passed, 3 total{RST}{BG}")
    blank()
    line(f" {prompt()} _")
    # Pin overlay at bottom: 17 rows (top+title+sep+11 content+sep+input+bot)
    overlay_h = 17
    while _lines < H - 1 - overlay_h:
        blank()
    ox, ow = 0, W
    inner = ow - 4
    tgap = " " * (inner - len("operator") - len("Esc: close"))
    line(box_top(ox, ow))
    line(box_mid(ox, ow, f"{FG_BLUE}{BOLD}operator{RST}{BG}{tgap}{FG_DIM}Esc: close{RST}{BG}"))
    line(box_sep(ox, ow))
    line(box_mid(ox, ow, f"{FG_DIM}you{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG}The timeout test is failing. Can you fix src/api/client.ts so it properly handles{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG}timeout errors?{RST}{BG}"))
    line(box_mid(ox, ow))
    line(box_mid(ox, ow, f"{FG_BLUE}agent{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG}I'll take a look at the test and the client code.{RST}{BG}"))
    line(box_mid(ox, ow))
    line(box_mid(ox, ow, f"{FG_YEL}> read_file: src/api/client.test.ts{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG_GRN}  -> 42 lines read{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG_YEL}> read_file: src/api/client.ts{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG_PUR}  ~ reading...{RST}{BG}"))
    line(box_sep(ox, ow))
    line(box_mid(ox, ow, f"{FG_DIM}> _{RST}{BG}"))
    line(box_bot(ox, ow))
    bar(f" {FG_GRN}{BOLD}tank{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_BLUE}0:bash{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}~/projects/webapp{RST}{BG_BAR}                            {FG_DIM}Esc: close overlay{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_YEL}reading{RST}{BG_BAR}")


def scenario_03_tool_exec():
    """Agent executes tools -- full pane overlay, reads files, writes fix, runs tests"""
    ox, ow = 0, W
    inner = ow - 4
    tgap = " " * (inner - len("operator") - len("Esc: close"))
    line(box_top(ox, ow))
    line(box_mid(ox, ow, f"{FG_BLUE}{BOLD}operator{RST}{BG}{tgap}{FG_DIM}Esc: close{RST}{BG}"))
    line(box_sep(ox, ow))
    line(box_mid(ox, ow, f"{FG_YEL}> read_file: src/api/client.test.ts{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG_GRN}  -> 42 lines read{RST}{BG}"))
    line(box_mid(ox, ow))
    line(box_mid(ox, ow, f"{FG_YEL}> read_file: src/api/client.ts{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG_GRN}  -> 87 lines read{RST}{BG}"))
    line(box_mid(ox, ow))
    line(box_mid(ox, ow, f"{FG_BLUE}agent{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG}The issue is in `fetchWithRetry`. The catch block doesn't distinguish timeout errors{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG}from network errors. I'll add an AbortController timeout check.{RST}{BG}"))
    line(box_mid(ox, ow))
    line(box_mid(ox, ow, f"{FG_YEL}> write_file: src/api/client.ts{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG_GRN}  -> written (91 lines){RST}{BG}"))
    line(box_mid(ox, ow))
    line(box_mid(ox, ow, f"{FG_YEL}> execute: npm test{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG_GRN}  -> Tests: 3 passed, 3 total{RST}{BG}"))
    line(box_mid(ox, ow))
    line(box_mid(ox, ow, f"{FG_BLUE}agent{RST}{BG}"))
    line(box_mid(ox, ow, f"{FG}Fixed! Added `AbortError` handling in the catch block. All 3 tests pass now.{RST}{BG}"))
    while _lines < H - 1 - 3:
        line(box_mid(ox, ow))
    line(box_sep(ox, ow))
    line(box_mid(ox, ow, f"{FG_DIM}> _{RST}{BG}"))
    line(box_bot(ox, ow))
    bar(f" {FG_GRN}{BOLD}tank{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_BLUE}0:bash{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}~/projects/webapp{RST}{BG_BAR}                                                   {FG_DIM}|{RST}{BG_BAR} {FG_GRN}done{RST}{BG_BAR}")


def scenario_04_multi_pane():
    """Multi-pane layout -- vertical split, editor + tests"""
    half = W // 2
    def dual(left, right):
        left += " " * max(0, half - 1 - display_width(left))
        right += " " * max(0, half - 1 - display_width(right))
        line(f"{left}{FG_GRN}│{RST}{BG}{right}")

    dual(f" {FG_DIM}src/api/client.ts{RST}{BG}", f" {prompt()}")
    dual(f" {FG_DIM} 1{RST}{BG}  {FG_PUR}import{RST}{BG} {{ TimeoutError }} {FG_PUR}from{RST}{BG} {FG_GRN}'./errors'{RST}{BG}",
         f" npm test -- --watch")
    dual(f" {FG_DIM} 2{RST}{BG}", f" {FG_GREY}PASS  src/App.test.tsx{RST}{BG}")
    dual(f" {FG_DIM} 3{RST}{BG}  {FG_PUR}export async function{RST}{BG} {FG_BLUE}fetchWithRetry{RST}{BG}(",
         f"   {FG_GRN}ok renders without crashing (12ms){RST}{BG}")
    dual(f" {FG_DIM} 4{RST}{BG}    url: {FG_GRN}string{RST}{BG},",
         f"   {FG_GRN}ok displays navigation (8ms){RST}{BG}")
    dual(f" {FG_DIM} 5{RST}{BG}    retries = {FG_ORG}3{RST}{BG},",
         f" {FG_GREY}PASS  src/api/client.test.ts{RST}{BG}")
    dual(f" {FG_DIM} 6{RST}{BG}    timeout = {FG_ORG}5000{RST}{BG}",
         f"   {FG_GRN}ok fetches data successfully (5ms){RST}{BG}")
    dual(f" {FG_DIM} 7{RST}{BG}  ) {{",
         f"   {FG_GRN}ok retries on failure (23ms){RST}{BG}")
    dual(f" {FG_DIM} 8{RST}{BG}    {FG_PUR}const{RST}{BG} ctrl = {FG_PUR}new{RST}{BG} {FG_BLUE}AbortController{RST}{BG}()",
         f"   {FG_GRN}ok handles timeout errors (11ms){RST}{BG}")
    dual(f" {FG_DIM} 9{RST}{BG}    {FG_PUR}const{RST}{BG} id = setTimeout(",
         f"")
    dual(f" {FG_DIM}10{RST}{BG}      () => ctrl.abort(), timeout",
         f" {FG_GRN}{BOLD}Tests: 5 passed, 5 total{RST}{BG}")
    dual(f" {FG_DIM}11{RST}{BG}    )",
         f" {FG_GREY}Ran all test suites.{RST}{BG}")
    dual(f" {FG_DIM}12{RST}{BG}    {FG_PUR}try{RST}{BG} {{",
         f"")
    dual(f" {FG_DIM}13{RST}{BG}      {FG_PUR}return await{RST}{BG} {FG_BLUE}fetch{RST}{BG}(url, {{",
         f" {FG_DIM}Watching for changes...{RST}{BG}")
    dual(f" {FG_DIM}14{RST}{BG}        signal: ctrl.signal",
         f"")
    dual(f" {FG_DIM}15{RST}{BG}      }})",
         f"")
    dual(f" {FG_DIM}16{RST}{BG}    }} {FG_PUR}catch{RST}{BG} (e) {{",
         f"")
    dual(f" {FG_DIM}17{RST}{BG}      {FG_PUR}if{RST}{BG} (e.name === {FG_GRN}'AbortError'{RST}{BG})",
         f"")
    dual(f" {FG_DIM}18{RST}{BG}        {FG_PUR}throw new{RST}{BG} {FG_BLUE}TimeoutError{RST}{BG}(url)",
         f"")
    pad_remaining(lambda: dual("", ""))
    bar(f" {FG_GRN}{BOLD}tank{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_BLUE}0:edit{RST}{BG_BAR} {FG_GREY}1:test{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}2 panes{RST}{BG_BAR}                                    {FG_DIM}Ctrl-B a: agent{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}idle{RST}{BG_BAR}")


def scenario_05_multi_agent():
    """Multi-pane with fixed-height agent overlays on both panes"""
    half = W // 2
    lw = half - 1   # left pane: 59 cols
    rw = half       # right pane: 60 cols
    li = lw - 4     # left inner: 55
    ri = rw - 4     # right inner: 56

    def lmid(content=""):
        content += " " * max(0, li - display_width(content))
        return f"{FG_BLUE}│{RST}{BG} {content} {FG_BLUE}│{RST}{BG}"
    def rmid(content=""):
        content += " " * max(0, ri - display_width(content))
        return f"{FG_BLUE}│{RST}{BG} {content} {FG_BLUE}│{RST}{BG}"
    def dual(left, right):
        left += " " * max(0, lw - display_width(left))
        right += " " * max(0, rw - display_width(right))
        line(f"{left}{FG_DIM}│{RST}{BG}{right}")

    # Terminal content visible above overlays
    dual(f" {prompt()} npm test -- --watch",
         f" {prompt()} git log --oneline -3")
    dual(f" {FG_GREY}PASS  src/App.test.tsx{RST}{BG}",
         f" {FG_GREY}a1b2c3d fix: handle timeout errors{RST}{BG}")
    dual(f"   {FG_GRN}ok renders without crashing{RST}{BG}",
         f" {FG_GREY}e4f5g6h feat: add retry logic{RST}{BG}")
    dual(f" {FG_GREY}PASS  src/api/client.test.ts{RST}{BG}",
         f" {FG_GREY}f7g8h9i refactor: split client{RST}{BG}")
    dual(f"   {FG_GRN}ok fetches data successfully{RST}{BG}",
         f"")
    dual(f"   {FG_GRN}ok retries on failure{RST}{BG}",
         f" {prompt()} _")
    dual(f"   {FG_RED}x  handles concurrent requests{RST}{BG}",
         f"")
    dual(f" {FG_RED}Tests: 1 failed, 3 passed{RST}{BG}",
         f"")
    dual(f" {FG_DIM}Watching for changes...{RST}{BG}",
         f"")

    # Pin overlays at bottom: 16 rows each (top+title+sep+10 content+sep+input+bot)
    overlay_h = 16
    while _lines < H - 1 - overlay_h:
        dual("", "")

    # Overlay rows — each pane has its own box
    def dual_box(l, r):
        """Emit a row where left/right are pre-built box elements."""
        line(f"{l}{FG_DIM}│{RST}{BG}{r}")

    # Top
    dual_box(f"{FG_BLUE}╭{'─' * (lw - 2)}╮{RST}{BG}",
             f"{FG_BLUE}╭{'─' * (rw - 2)}╮{RST}{BG}")
    # Title
    lgap = " " * (li - len("operator") - len("Esc"))
    rgap = " " * (ri - len("operator") - len("Esc"))
    dual_box(lmid(f"{FG_BLUE}{BOLD}operator{RST}{BG}{lgap}{FG_DIM}Esc{RST}{BG}"),
             rmid(f"{FG_BLUE}{BOLD}operator{RST}{BG}{rgap}{FG_DIM}Esc{RST}{BG}"))
    # Sep
    dual_box(f"{FG_BLUE}├{'─' * (lw - 2)}┤{RST}{BG}",
             f"{FG_BLUE}├{'─' * (rw - 2)}┤{RST}{BG}")
    # Content — left: fixing concurrent requests, right: code review
    left_content = [
        f" {FG_DIM}you{RST}{BG}",
        f" {FG}Concurrent requests test{RST}{BG}",
        f" {FG}failing. Investigate?{RST}{BG}",
        "",
        f" {FG_YEL}> read_file: client.test.ts{RST}{BG}",
        f" {FG_GRN}  -> 58 lines{RST}{BG}",
        "",
        f" {FG_BLUE}agent{RST}{BG}",
        f" {FG}AbortController is shared.{RST}{BG}",
        f" {FG}Each call needs its own.{RST}{BG}",
    ]
    right_content = [
        f" {FG_DIM}you{RST}{BG}",
        f" {FG}Review error handling in{RST}{BG}",
        f" {FG}the API client module.{RST}{BG}",
        "",
        f" {FG_YEL}> read_file: client.ts{RST}{BG}",
        f" {FG_GRN}  -> 93 lines{RST}{BG}",
        "",
        f" {FG_BLUE}agent{RST}{BG}",
        f" {FG}Retry logic looks solid.{RST}{BG}",
        f" {FG}Adding exponential backoff.{RST}{BG}",
    ]
    # Pad content to 10 rows
    while len(left_content) < 10:
        left_content.append("")
    while len(right_content) < 10:
        right_content.append("")
    for lc, rc in zip(left_content, right_content):
        dual_box(lmid(lc), rmid(rc))
    # Sep
    dual_box(f"{FG_BLUE}├{'─' * (lw - 2)}┤{RST}{BG}",
             f"{FG_BLUE}├{'─' * (rw - 2)}┤{RST}{BG}")
    # Input
    dual_box(lmid(f" {FG_DIM}> _{RST}{BG}"), rmid(f" {FG_DIM}> _{RST}{BG}"))
    # Bot
    dual_box(f"{FG_BLUE}╰{'─' * (lw - 2)}╯{RST}{BG}",
             f"{FG_BLUE}╰{'─' * (rw - 2)}╯{RST}{BG}")
    bar(f" {FG_GRN}{BOLD}tank{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}0:test{RST}{BG_BAR} {FG_BLUE}1:shell{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}2 panes{RST}{BG_BAR}                   {FG_DIM}Esc: close overlay{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_YEL}writing{RST}{BG_BAR} {FG_GRN}done{RST}{BG_BAR}")


def scenario_07_windows():
    """Window switching -- tmux-like Ctrl-B n/p/0-9 with keybinding help"""
    # Background: docker logs (normal, not dimmed)
    line(f" {prompt()} docker compose logs -f api")
    line(f" {FG_GREY}api  | 2026-03-06 14:22:01 INFO  Server started on :8080{RST}{BG}")
    line(f" {FG_GREY}api  | 2026-03-06 14:22:03 INFO  Connected to postgres{RST}{BG}")
    line(f" {FG_GRN}api  | 2026-03-06 14:22:15 INFO  GET /api/users 200 12ms{RST}{BG}")
    line(f" {FG_GRN}api  | 2026-03-06 14:22:16 INFO  GET /api/tasks 200 8ms{RST}{BG}")
    line(f" {FG_YEL}api  | 2026-03-06 14:22:18 WARN  Slow query (245ms){RST}{BG}")
    line(f" {FG_GRN}api  | 2026-03-06 14:22:20 INFO  POST /api/tasks 201 15ms{RST}{BG}")
    line(f" {FG_RED}api  | 2026-03-06 14:22:22 ERROR Connection reset by peer{RST}{BG}")
    line(f" {FG_GRN}api  | 2026-03-06 14:22:24 INFO  Reconnected to postgres{RST}{BG}")
    # Centered command palette
    ow = 70
    ox = (W - ow) // 2
    palette_h = 8  # top + title + sep + 5 commands + bot
    center_start = (H - 1 - palette_h) // 2
    while _lines < center_start:
        blank()
    line(box_top(ox, ow))
    line(box_mid(ox, ow, f"{FG_YEL}{BOLD}Ctrl-B commands (prefix mode){RST}{BG}"))
    line(box_sep(ox, ow))
    line(box_mid(ox, ow, f" {FG_BLUE}c{RST}{BG}       new window          {FG_BLUE}o{RST}{BG}       cycle panes"))
    line(box_mid(ox, ow, f" {FG_BLUE}n / p{RST}{BG}   next / prev window  {FG_BLUE}[{RST}{BG}       copy mode (scroll)"))
    line(box_mid(ox, ow, f" {FG_BLUE}0-9{RST}{BG}     switch to window N  {FG_GRN}{BOLD}a{RST}{BG}       {FG_GRN}agent overlay{RST}{BG}"))
    line(box_mid(ox, ow, f" {FG_BLUE}%{RST}{BG}       vertical split      {FG_BLUE}d{RST}{BG}       detach session"))
    line(box_mid(ox, ow, f' {FG_BLUE}"{RST}{BG}       horizontal split    {FG_BLUE}x{RST}{BG}       close pane'))
    line(box_bot(ox, ow))
    pad_remaining()
    bar(f" {FG_GRN}{BOLD}tank{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}0:edit{RST}{BG_BAR} {FG_GREY}1:test{RST}{BG_BAR} {bg(122,162,247)}{fg(26,27,38)} 2:logs {RST}{BG_BAR} {FG_GREY}3:shell{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}session: webapp-dev{RST}{BG_BAR}              {FG_DIM}Ctrl-B ?: help{RST}{BG_BAR}")


def scenario_08a_detach():
    """Frame 1: active tank session with docker logs"""
    line(f" {prompt()} docker compose logs -f api")
    line(f" {FG_GRN}api  | 2026-03-06 14:23:05 INFO  Deploy v2.3.1 complete{RST}{BG}")
    line(f" {FG_GREY}api  | 2026-03-06 14:23:10 INFO  GET /api/health 200 1ms{RST}{BG}")
    line(f" {FG_GRN}api  | 2026-03-06 14:23:12 INFO  GET /api/users 200 5ms{RST}{BG}")
    line(f" {FG_GREY}api  | 2026-03-06 14:23:15 INFO  POST /api/tasks 201 12ms{RST}{BG}")
    pad_remaining()
    bar(f" {FG_GRN}{BOLD}tank{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}0:edit{RST}{BG_BAR} {FG_GREY}1:test{RST}{BG_BAR} {bg(122,162,247)}{fg(26,27,38)} 2:logs {RST}{BG_BAR} {FG_GREY}3:shell{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}webapp-dev{RST}{BG_BAR}                     {FG_DIM}|{RST}{BG_BAR} {FG_GREY}idle{RST}{BG_BAR}")


def scenario_08b_shell():
    """Frame 2: normal shell after detach, listing sessions"""
    fullbar(" [detached (from session webapp-dev)]",
            bg(224, 175, 104), fg(26, 27, 38))
    blank()
    line(f" {fg(200,200,200)}${RST}{BG} {FG}tank list-sessions{RST}{BG}")
    line(f" {FG_GRN}webapp-dev{RST}{BG}: 4 windows (attached: 0) {FG_GREY}[created 2h ago]{RST}{BG}")
    line(f" {FG_GREY}backend{RST}{BG}:    2 windows (attached: 0) {FG_GREY}[created 5h ago]{RST}{BG}")
    blank()
    line(f" {fg(200,200,200)}${RST}{BG} {FG}tank attach webapp-dev{RST}{BG}")
    pad_remaining()


def scenario_08c_reattach():
    """Frame 3: reattached tank session, logs continued"""
    fullbar(" [reattached to session webapp-dev -- 4 windows, all intact]",
            bg(158, 206, 106), fg(26, 27, 38))
    blank()
    line(f" {FG_GREY}api  | ...2 hours of logs continued while detached...{RST}{BG}")
    line(f" {FG_GRN}api  | 2026-03-06 16:45:12 INFO  GET /api/users 200 3ms{RST}{BG}")
    line(f" {FG_GRN}api  | 2026-03-06 16:45:15 INFO  GET /api/tasks 200 4ms{RST}{BG}")
    line(f" {FG_GREY}api  | 2026-03-06 16:45:20 INFO  GET /api/health 200 1ms{RST}{BG}")
    pad_remaining()
    bar(f" {FG_GRN}{BOLD}tank{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}0:edit{RST}{BG_BAR} {FG_GREY}1:test{RST}{BG_BAR} {bg(122,162,247)}{fg(26,27,38)} 2:logs {RST}{BG_BAR} {FG_GREY}3:shell{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}webapp-dev{RST}{BG_BAR}                           {FG_DIM}|{RST}{BG_BAR} {FG_GREY}idle{RST}{BG_BAR}")


def scenario_10_services_logs():
    """Services overlay with daemon logs stacked on left, tree view on right."""
    ow = W - 8   # overlay width
    ox = 4        # left margin
    # Count fixed overlay rows: top(1)+title(1)+sep(1)+22 content+sep(1)+shortcuts(1)+bot(1) = 28
    fixed_h = 28
    total_avail = H - 1
    fill = (total_avail - fixed_h) % 2
    overlay_h = fixed_h + fill
    margin = (total_avail - overlay_h) // 2
    # Terminal content visible above overlay
    line(f" {prompt()} npm start")
    line(f" {FG_GREY}Server running on http://localhost:3000{RST}{BG}")
    line(f" {FG_GREY}Compiled successfully in 1.2s{RST}{BG}")
    blank()
    line(f" {prompt()} _")
    while _lines < margin:
        blank()
    line(box_top(ox, ow))
    line(box_mid(ox, ow, f"{FG_CYAN}{BOLD}services{RST}{BG}  {FG_DIM}logs view{RST}{BG}                                                        {FG_DIM}Tab: tree  Esc: close{RST}{BG}"))
    line(box_sep(ox, ow))
    # Two-column: stacked logs (left, wider) | tree view (right, narrower)
    rw = 32  # right panel width (tree view)
    def svc_row(left, right):
        lw = ow - 4 - rw - 3  # left panel width: 3 for " │ "
        left += " " * max(0, lw - display_width(left))
        right += " " * max(0, rw - display_width(right))
        line(box_mid(ox, ow, f"{left} {FG_DIM}│{RST}{BG} {right}"))
    def log_hdiv(label=""):
        """Horizontal divider inside log pane area with ┼ at column divider."""
        lw = ow - 4 - rw - 3
        if label:
            dashes = lw - display_width(label) - 2
            left = f" {label} {'─' * max(0, dashes)}"
        else:
            left = "─" * lw
        left += " " * max(0, lw - display_width(left))
        right = " " * rw
        line(box_mid(ox, ow, f"{FG_DIM}{left}{RST}{BG} {FG_DIM}│{RST}{BG} {right}"))
    # Header
    svc_row(f" {FG_CYAN}{BOLD}api{RST}{BG} {FG_DIM}:8080{RST}{BG}",
            f" {FG_BLUE}{BOLD}Services{RST}{BG}")
    svc_row(f" {FG_GREY}14:22:15 GET /api/users 200 12ms{RST}{BG}",
            f" {FG_DIM}{'─' * 30}{RST}{BG}")
    svc_row(f" {FG_GREY}14:22:16 GET /api/tasks 200 8ms{RST}{BG}",
            f" {FG_GRN}●{RST}{BG} {FG}{BOLD}api{RST}{BG}      {FG_GRN}running{RST}{BG} {FG_DIM}:8080{RST}{BG}")
    svc_row(f" {FG_YEL}14:22:18 WARN Slow query (245ms){RST}{BG}",
            f" {FG_GRN}●{RST}{BG} {FG}worker{RST}{BG}   {FG_GRN}running{RST}{BG}")
    svc_row(f" {FG_GREY}14:22:20 POST /api/tasks 201{RST}{BG}",
            f" {FG_RED}●{RST}{BG} {FG}db{RST}{BG}       {FG_RED}crashed{RST}{BG}")
    svc_row(f" {FG_GREY}14:22:22 GET /api/health 200 1ms{RST}{BG}",
            f" {FG_GRN}●{RST}{BG} {FG}redis{RST}{BG}    {FG_GRN}running{RST}{BG} {FG_DIM}:6379{RST}{BG}")
    log_hdiv(f"{FG_CYAN}worker{RST}{BG}{FG_DIM}")
    svc_row(f" {FG_GRN}14:22:10 Job #4481 started{RST}{BG}",
            f" {FG_YEL}●{RST}{BG} {FG}proxy{RST}{BG}    {FG_YEL}starting{RST}{BG} {FG_DIM}:443{RST}{BG}")
    svc_row(f" {FG_GRN}14:22:14 Job #4481 done (3.2s){RST}{BG}",
            f"")
    svc_row(f" {FG_GREY}14:22:20 Polling queue...{RST}{BG}",
            f" {FG_DIM}5 services | 3 running{RST}{BG}")
    svc_row(f" {FG_GRN}14:22:25 Job #4482 started{RST}{BG}",
            f" {FG_DIM}1 crashed | 1 starting{RST}{BG}")
    log_hdiv(f"{FG_CYAN}db{RST}{BG} {FG_RED}crashed{RST}{BG}{FG_DIM}")
    svc_row(f" {FG_YEL}14:22:15 WARN checkpoints frequent{RST}{BG}",
            f"")
    svc_row(f" {FG_RED}14:22:18 FATAL data dir corrupted{RST}{BG}",
            f"")
    svc_row(f" {FG_RED}14:22:18 server process exit 1{RST}{BG}",
            f"")
    svc_row(f" {FG_RED}14:22:19 shutting down{RST}{BG}",
            f"")
    svc_row(f" {FG_YEL}14:22:20 restarting in 5s...{RST}{BG}",
            f"")
    log_hdiv(f"{FG_CYAN}redis{RST}{BG} {FG_DIM}:6379{RST}{BG}{FG_DIM}")
    svc_row(f" {FG_GREY}14:22:15 # DB 0: 847 keys{RST}{BG}",
            f"")
    svc_row(f" {FG_GREY}14:22:20 # Background saving OK{RST}{BG}",
            f"")
    svc_row(f" {FG_GREY}14:22:25 # DB 0: 851 keys{RST}{BG}",
            f"")
    svc_row(f" {FG_GREY}14:22:30 # 11 clients connected{RST}{BG}",
            f"")
    # Fill rows to make margins equal
    for _ in range(fill):
        svc_row("", "")
    # Bottom border with shortcuts
    line(box_sep(ox, ow))
    line(box_mid(ox, ow, f" {FG_DIM}r: restart  s: stop  Tab: tree view  j/k: scroll  Enter: attach  q: quit{RST}{BG}"))
    line(box_bot(ox, ow))
    # Bottom margin -- terminal content continues below
    line(f" {prompt()} _")
    pad_remaining()
    bar(f" {FG_GRN}{BOLD}tank{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_BLUE}0:bash{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}~/projects/webapp{RST}{BG_BAR}                          {FG_DIM}Ctrl-B s: services{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_RED}1 crashed{RST}{BG_BAR}")


def scenario_09_services():
    """Per-project services overlay -- tree view + service definition"""
    ow = W - 8   # overlay width
    ox = 4        # left margin
    # Fixed overlay: top(1) + title(1) + sep(1) + 16 svc_rows + sep(1) + shortcuts(1) + bot(1) = 22
    fixed_h = 22
    # Make margins equal: add fill rows so (H-1 - overlay_h) is even
    total_avail = H - 1
    fill = (total_avail - fixed_h) % 2  # 1 if odd gap, 0 if even
    overlay_h = fixed_h + fill
    margin = (total_avail - overlay_h) // 2
    # Two-column layout inside the box: tree view (left) | service def (right)
    lw = 35
    def svc_row(left, right):
        left += " " * max(0, lw - display_width(left))
        inner = ow - 4 - lw - 3
        right += " " * max(0, inner - display_width(right))
        line(box_mid(ox, ow, f"{left} {FG_DIM}│{RST}{BG} {right}"))
    # Terminal content visible above overlay
    line(f" {prompt()} npm start")
    line(f" {FG_GREY}Server running on http://localhost:3000{RST}{BG}")
    line(f" {FG_GREY}Compiled successfully in 1.2s{RST}{BG}")
    blank()
    line(f" {prompt()} _")
    while _lines < margin:
        blank()
    line(box_top(ox, ow))
    inner = ow - 4
    tl = "services  Procfile: ~/projects/webapp/Procfile"
    tr = "Esc: close"
    tgap = " " * (inner - len(tl) - len(tr))
    line(box_mid(ox, ow, f"{FG_CYAN}{BOLD}services{RST}{BG}  {FG_DIM}Procfile: ~/projects/webapp/Procfile{RST}{BG}{tgap}{FG_DIM}Esc: close{RST}{BG}"))
    line(box_sep(ox, ow))
    # Header
    svc_row(f" {FG_BLUE}{BOLD}Services{RST}{BG}", f" {FG_BLUE}{BOLD}Procfile Definition{RST}{BG}")
    svc_row(f" {FG_DIM}{'─' * 33}{RST}{BG}", f" {FG_DIM}{'─' * (ow - 4 - lw - 4)}{RST}{BG}")
    # Tree view with status indicators
    svc_row(f" {FG_GRN}●{RST}{BG} {FG}{BOLD}api{RST}{BG}          {FG_GRN}running{RST}{BG} {FG_DIM}:8080{RST}{BG}",
            f" {FG_DIM}# API server{RST}{BG}")
    svc_row(f"   {FG_DIM}pid 42381 | 2m uptime{RST}{BG}",
            f" {FG_PUR}api:{RST}{BG} node dist/server.js")
    svc_row(f" {FG_GRN}●{RST}{BG} {FG}worker{RST}{BG}       {FG_GRN}running{RST}{BG}",
            f"")
    svc_row(f"   {FG_DIM}pid 42382 | 2m uptime{RST}{BG}",
            f" {FG_DIM}# Background job worker{RST}{BG}")
    svc_row(f" {FG_RED}●{RST}{BG} {FG}db{RST}{BG}           {FG_RED}crashed{RST}{BG}",
            f" {FG_PUR}worker:{RST}{BG} node dist/worker.js")
    svc_row(f"   {FG_RED}exit 1 | restarting...{RST}{BG}",
            f"")
    svc_row(f" {FG_GRN}●{RST}{BG} {FG}redis{RST}{BG}        {FG_GRN}running{RST}{BG} {FG_DIM}:6379{RST}{BG}",
            f" {FG_DIM}# Database{RST}{BG}")
    svc_row(f"   {FG_DIM}pid 42384 | 2m uptime{RST}{BG}",
            f" {FG_PUR}db:{RST}{BG} postgres -D data/")
    svc_row(f" {FG_YEL}●{RST}{BG} {FG}proxy{RST}{BG}        {FG_YEL}starting{RST}{BG} {FG_DIM}:443{RST}{BG}",
            f"")
    svc_row(f"   {FG_DIM}pid 42385 | 0s uptime{RST}{BG}",
            f" {FG_DIM}# Redis cache{RST}{BG}")
    svc_row(f"", f" {FG_PUR}redis:{RST}{BG} redis-server")
    svc_row(f" {FG_DIM}5 services | 3 running{RST}{BG}",
            f"")
    svc_row(f" {FG_DIM}1 crashed | 1 starting{RST}{BG}",
            f" {FG_DIM}# Reverse proxy{RST}{BG}")
    svc_row(f"", f" {FG_PUR}proxy:{RST}{BG} caddy run")
    # Fill rows to make margins equal
    for _ in range(fill):
        svc_row("", "")
    line(box_sep(ox, ow))
    line(box_mid(ox, ow, f" {FG_DIM}r: restart  s: stop  l: logs  Enter: connect to service  q: quit{RST}{BG}"))
    line(box_bot(ox, ow))
    # Bottom margin -- terminal content continues below
    line(f" {prompt()} _")
    pad_remaining()
    bar(f" {FG_GRN}{BOLD}tank{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_BLUE}0:bash{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_GREY}~/projects/webapp{RST}{BG_BAR}                          {FG_DIM}Ctrl-B s: services{RST}{BG_BAR} {FG_DIM}|{RST}{BG_BAR} {FG_RED}1 crashed{RST}{BG_BAR}")


SCENARIOS = {
    "01-idle": ("Single pane -- idle terminal", "tank — bash", scenario_01_idle),
    "02-overlay": ("Agent overlay open", "tank — bash", scenario_02_overlay),
    "03-tool-exec": ("Agent executes tools, writes fix", "tank — bash", scenario_03_tool_exec),
    "04-multi-pane": ("Multi-pane layout (vertical split)", "tank — editor + tests", scenario_04_multi_pane),
    "05-multi-agent": ("Multi-pane with per-pane agents", "tank — tests + shell", scenario_05_multi_agent),
    "06-windows": ("Window switching + keybinding help", "tank — docker logs", scenario_07_windows),
    "07-services": ("Per-project services overlay", "tank — bash", scenario_09_services),
    "08-services-logs": ("Services -- daemon logs in multi-pane", "tank — logs", scenario_10_services_logs),
    "09-detach": ("Detach/reattach (session persistence)", [
        ("tank — webapp-dev", scenario_08a_detach, 12),
        ("Terminal", scenario_08b_shell, 10),
        ("tank — webapp-dev", scenario_08c_reattach, 12),
    ]),
}


TITLEBAR_H = 38
OUTER_PAD = 20
FRAME_RADIUS = 10
C_BODY = (0x13, 0x14, 0x1c)
C_TBAR = (0x24, 0x28, 0x3b)
C_BORDER = (0x3b, 0x42, 0x61)
C_TITLE_TEXT = (0x56, 0x5f, 0x89)


def _capture_grid(fn):
    """Capture scenario ANSI output, parse into cell grid."""
    import io
    reset_lines()
    old = sys.stdout
    sys.stdout = buf = io.StringIO()
    fn()
    sys.stdout = old
    return parse_ansi(buf.getvalue())


def _setup_font(font_path):
    """Return (font, title_font, cell_w, cell_h)."""
    font = ImageFont.truetype(font_path, 14)
    bbox = font.getbbox("M")
    cell_w = bbox[2] - bbox[0]
    ascent, descent = font.getmetrics()
    cell_h = ascent + descent
    title_font = ImageFont.truetype(font_path, 12)
    return font, title_font, cell_w, cell_h


def _draw_frame(img, grid, win_x, win_y, win_title, font, title_font, cell_w, cell_h):
    """Draw a window frame with terminal content. Returns (win_w, win_h)."""
    draw = ImageDraw.Draw(img)
    term_w = W * cell_w
    term_h = len(grid) * cell_h
    win_w = term_w
    win_h = term_h + TITLEBAR_H
    r = FRAME_RADIUS

    # Border + fill
    draw.rounded_rectangle(
        [win_x - 1, win_y - 1, win_x + win_w + 1, win_y + win_h + 1],
        radius=r + 1, outline=C_BORDER)
    draw.rounded_rectangle(
        [win_x, win_y, win_x + win_w, win_y + win_h],
        radius=r, fill=DEF_BG)

    # Title bar
    draw.rounded_rectangle(
        [win_x, win_y, win_x + win_w, win_y + TITLEBAR_H],
        radius=r, fill=C_TBAR)
    draw.rectangle(
        [win_x, win_y + TITLEBAR_H - r, win_x + win_w, win_y + TITLEBAR_H],
        fill=C_TBAR)

    # Traffic lights
    btn_cy = win_y + TITLEBAR_H // 2
    for bx, bc in [(win_x + 18, (0xff, 0x5f, 0x56)),
                    (win_x + 38, (0xff, 0xbd, 0x2e)),
                    (win_x + 58, (0x27, 0xc9, 0x3f))]:
        draw.ellipse([bx - 7, btn_cy - 7, bx + 7, btn_cy + 7], fill=bc)

    # Title text
    tb = title_font.getbbox(win_title)
    tw = tb[2] - tb[0]
    draw.text((win_x + (win_w - tw) // 2, win_y + 11), win_title,
              fill=C_TITLE_TEXT, font=title_font)

    # Terminal content
    cy = win_y + TITLEBAR_H
    for row_idx, cells in enumerate(grid):
        y = cy + row_idx * cell_h
        bx = win_x
        spans = []
        for cell in cells:
            ch, fg_c, bg_c, bld = cell
            cw = char_width(ch)
            spans.append((ch, fg_c, bg_c, bld, bx, cw * cell_w))
            bx += cw * cell_w
        for ch, fg_c, bg_c, bld, cx, pw in spans:
            draw.rectangle([cx, y, cx + pw, y + cell_h], fill=bg_c)
            if ch in BOX_CHARS:
                _draw_box(draw, ch, cx, y, cell_w, cell_h, fg_c)
            elif ch not in (' ', '\t'):
                draw.text((cx, y), ch, fill=fg_c, font=font)

    return win_w, win_h


def _clip_frame(img, win_x, win_y, win_w, win_h):
    """Clip just the corners of this frame to rounded rect (preserves rest of image)."""
    r = FRAME_RADIUS
    iw, ih = img.size
    # Mask: white everywhere (preserve) except this frame's corners
    mask = Image.new("L", (iw, ih), 255)
    md = ImageDraw.Draw(mask)
    # Black out the frame rectangle, then white back the rounded area
    md.rectangle([win_x, win_y, win_x + win_w, win_y + win_h], fill=0)
    md.rounded_rectangle([win_x, win_y, win_x + win_w, win_y + win_h],
                         radius=r, fill=255)
    bg_img = Image.new("RGB", (iw, ih), C_BODY)
    img = Image.composite(img, bg_img, mask)
    fd = ImageDraw.Draw(img)
    fd.rounded_rectangle(
        [win_x - 1, win_y - 1, win_x + win_w + 1, win_y + win_h + 1],
        radius=r + 1, outline=C_BORDER)
    return img


def render_to_file(name, desc, win_title, fn, outdir, font_path):
    """Render single-frame scenario to PNG."""
    grid = _capture_grid(fn)
    font, title_font, cell_w, cell_h = _setup_font(font_path)
    term_w = W * cell_w
    term_h = len(grid) * cell_h
    win_w = term_w
    win_h = term_h + TITLEBAR_H
    img_w = win_w + 2 * OUTER_PAD
    img_h = win_h + 2 * OUTER_PAD

    img = Image.new("RGB", (img_w, img_h), C_BODY)
    wx, wy = OUTER_PAD, OUTER_PAD
    _draw_frame(img, grid, wx, wy, win_title, font, title_font, cell_w, cell_h)
    img = _clip_frame(img, wx, wy, win_w, win_h)

    png_path = os.path.join(outdir, f"{name}.png")
    img.save(png_path, "PNG", optimize=True)
    print(f"  ok {name}: {desc} -> {png_path}")


def render_multi_to_file(name, desc, frames, outdir, font_path):
    """Render multi-frame scenario (stacked vertically) to PNG."""
    global H
    old_H = H
    font, title_font, cell_w, cell_h = _setup_font(font_path)
    term_w = W * cell_w
    gap = 40

    # Capture each frame with its own H
    grids = []
    titles = []
    for title, fn, h_rows in frames:
        H = h_rows
        grids.append(_capture_grid(fn))
        titles.append(title)
    H = old_H

    # Compute total image size
    frame_heights = []
    for grid in grids:
        th = len(grid) * cell_h + TITLEBAR_H
        frame_heights.append(th)
    total_h = sum(frame_heights) + gap * (len(grids) - 1) + 2 * OUTER_PAD
    img_w = term_w + 2 * OUTER_PAD

    img = Image.new("RGB", (img_w, int(total_h)), C_BODY)
    y_off = OUTER_PAD
    for i, (grid, title, fh) in enumerate(zip(grids, titles, frame_heights)):
        win_w = term_w
        win_h = fh
        _draw_frame(img, grid, OUTER_PAD, y_off, title, font, title_font, cell_w, cell_h)
        img = _clip_frame(img, OUTER_PAD, y_off, win_w, win_h)
        # Draw arrow between frames
        if i < len(grids) - 1:
            arrow_y = y_off + win_h + gap // 2
            draw = ImageDraw.Draw(img)
            ax = img_w // 2
            draw.line([(ax, y_off + win_h + 8), (ax, arrow_y + 8)],
                      fill=C_BORDER, width=2)
            draw.polygon([(ax - 6, arrow_y + 4), (ax + 6, arrow_y + 4),
                          (ax, arrow_y + 14)], fill=C_BORDER)
        y_off += win_h + gap

    png_path = os.path.join(outdir, f"{name}.png")
    img.save(png_path, "PNG", optimize=True)
    print(f"  ok {name}: {desc} -> {png_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate Tank concept mockup PNGs")
    parser.add_argument("command", help="list | all | <scenario-name>")
    parser.add_argument("--font", help="Path to monospace TTF font")
    parser.add_argument("--outdir", help="Output directory (default: script dir)")
    args = parser.parse_args()

    if args.command == "list":
        for name, entry in SCENARIOS.items():
            print(f"  {name}: {entry[0]}")
        sys.exit(0)

    # Resolve font
    font_path = args.font or find_font()
    if not font_path:
        print("Error: no monospace font found. Use --font PATH.", file=sys.stderr)
        sys.exit(1)
    print(f"Using font: {font_path}")

    outdir = args.outdir or os.path.dirname(os.path.abspath(__file__))

    def render_one(name, entry):
        desc = entry[0]
        if isinstance(entry[1], list):
            render_multi_to_file(name, desc, entry[1], outdir, font_path)
        else:
            _, title, fn = entry
            render_to_file(name, desc, title, fn, outdir, font_path)

    if args.command == "all":
        for name, entry in SCENARIOS.items():
            render_one(name, entry)
        print("\nDone!")
    elif args.command in SCENARIOS:
        render_one(args.command, SCENARIOS[args.command])
    else:
        print(f"Unknown: {args.command}. Use 'list' for available scenarios.")
        sys.exit(1)
