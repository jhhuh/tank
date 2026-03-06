# tank-layout: Terminal Layout Language

**Date**: 2026-03-06
**Status**: Approved

## Problem

Tank needs a way to describe terminal UI layouts declaratively. Currently:

- `render-concepts.py` (1000+ lines Python) manually constructs concept images
  with repetitive `line()`, `box_top()`, `box_mid()` calls
- `Overlay.hs` manually builds ANSI escape sequences for the agent popup
- `Terminal.hs` has a basic `Layout = LPane | LSplit` tree with no rendering

These three systems share no code and describe the same UI differently. Changes
to the UI design require editing Python, then separately editing Haskell.

## Solution

`tank-layout` — an independent Haskell cabal package providing:

1. A **layout tree** data type for declarative terminal UI structure
2. A **Haskell eDSL** for constructing layouts
3. A **solver** that resolves the tree into positioned cells
4. **Two backends**: ANSI terminal output and PNG image output

Tank depends on `tank-layout`. The package has zero dependency on Tank internals.

## Design Decisions

- **Approach A (split-tree + overlays)** chosen over flexbox or immediate-mode.
  Directly models Tank's three layout concerns: spatial splits, floating
  overlays, and decorated boxes.
- **Haskell eDSL as primary**, with optional text format parser planned later.
- **Pure Haskell PNG rendering** via JuicyPixels + FontyFruity. No Python dependency.
- **Both ANSI and PNG from day one** — same layout tree renders to both targets.

## Package Structure

```
tank-layout/
  tank-layout.cabal
  src/
    Tank/Layout.hs                -- re-export module
    Tank/Layout/Types.hs          -- layout tree, style, cell types
    Tank/Layout/DSL.hs            -- eDSL combinators
    Tank/Layout/Render.hs         -- solver: tree -> positioned cells -> cell grid
    Tank/Layout/Cell.hs           -- cell grid type and operations
    Tank/Layout/Backend/
      ANSI.hs                     -- cell grid -> ANSI ByteString
      PNG.hs                      -- cell grid -> PNG image (JuicyPixels)
  test/
    Spec.hs
    Tank/Layout/RenderSpec.hs
    Tank/Layout/Backend/ANSISpec.hs
```

Dependencies: `text`, `bytestring`, `vector`, `containers`, `JuicyPixels`,
`FontyFruity`.

## Core Types

```haskell
-- Cell: the universal intermediate representation
data Cell = Cell
  { cellChar  :: !Char
  , cellFg    :: !Color
  , cellBg    :: !Color
  , cellBold  :: !Bool
  , cellDim   :: !Bool
  }

data Color = Default | RGB !Word8 !Word8 !Word8

-- Layout tree
data Layout
  = Leaf Content                        -- terminal content
  | Split Dir Ratio Layout Layout       -- binary split
  | Layers Layout [(Anchor, Layout)]    -- base + positioned overlays
  | Styled Style Layout                 -- decoration wrapper

data Dir = Horizontal | Vertical
type Ratio = Float

-- Overlay positioning
data Anchor
  = Center
  | Bottom
  | Absolute Int Int                    -- row, col from parent origin

-- Box decoration
data Style = Style
  { sBorder   :: Maybe Border
  , sPadding  :: !Edges
  , sTitle    :: Maybe (Text, Text)     -- left title, right hint
  , sBg       :: Maybe Color
  }

data Border = Border
  { bStyle :: BorderStyle               -- Single | Rounded | Double | Heavy
  , bColor :: Color
  }

data Edges = Edges !Int !Int !Int !Int  -- top right bottom left

-- Content: what fills a leaf
data Content
  = Text [Span]
  | Fill Char Color
  | CellGrid (Vector (Vector Cell))    -- pre-rendered (e.g., VTerm output)

data Span = Span !Text !SpanStyle
data SpanStyle = SpanStyle
  { spanFg   :: Maybe Color
  , spanBold :: Bool
  , spanDim  :: Bool
  }
```

## eDSL Combinators

```haskell
-- Splitting
hsplit :: Ratio -> Layout -> Layout -> Layout
vsplit :: Ratio -> Layout -> Layout -> Layout
hsplit2, vsplit2 :: Layout -> Layout -> Layout

-- Overlays
overlay :: Anchor -> Layout -> Layout -> Layout
centered :: Layout -> Layout -> Layout
bottomPinned :: Layout -> Layout -> Layout

-- Decoration
bordered :: Layout -> Layout
roundBordered :: Layout -> Layout
titled :: Text -> Layout -> Layout
titled' :: Text -> Text -> Layout -> Layout

-- Content
text :: Text -> Layout
styled :: Color -> Text -> Layout
spans :: [Span] -> Layout
fill :: Char -> Layout
cells :: Vector (Vector Cell) -> Layout

-- Common patterns
withStatusBar :: Layout -> [Span] -> Layout
```

## Rendering Pipeline

```
Layout tree (user constructs via eDSL)
      |
      v
Solver: allocate(tree, Rect) -> [(Rect, Content, Style)]
  - Splits divide rect by ratio
  - Overlays compute anchor position within parent rect
  - Styled nodes shrink inner rect by padding + border
      |
      v
Cell grid: stamp positioned content into W x H grid
  - Later layers overwrite earlier (overlay compositing)
  - Borders drawn as box-drawing characters
      |
      v
Backend:
  - ANSI: iterate grid -> emit SGR sequences + characters
  - PNG:  iterate grid -> rasterize chars with FontyFruity
                        -> compose image with JuicyPixels
                        -> window chrome (title bar, traffic lights, corners)
```

## PNG Backend

Replaces the Python Pillow renderer with pure Haskell:

- **Font**: FontyFruity loads TTF, rasterizes glyphs
- **Image**: JuicyPixels creates image, draws cell backgrounds, composites glyphs
- **Chrome**: Title bar, traffic lights, rounded corners as image primitives
- **Output**: `encodePng` to file

## Scope Boundaries

**In scope (v0.1):**

- Core types and eDSL
- Layout solver
- ANSI backend
- PNG backend with window chrome
- Reproduce all 9 concept images using the eDSL
- HSpec tests for solver and ANSI output

**Out of scope (future):**

- Text format parser (eDSL first)
- Multi-frame / animation support
- Live terminal event loop (Tank owns this)
- Color themes (hardcode Tokyo Night, parameterize later)

## Example

The concept mockup "02-overlay" expressed in the eDSL:

```haskell
scenario02 :: Layout
scenario02 =
  withStatusBar content statusSpans
  where
    content = bottomPinned terminalOutput agentOverlay

    terminalOutput = text $ T.unlines
      [ "$ npm test"
      , "PASS  src/App.test.tsx"
      , "  ok renders without crashing (12ms)"
      , "FAIL  src/api/client.test.ts"
      , "  x  handles timeout errors (15ms)"
      ]

    agentOverlay = titled' "operator" "Esc: close" $
      spans [ user "The timeout test is failing..."
            , agent "I'll take a look..."
            ]

    statusSpans = [green "tank", dim " | ", blue "0:bash"]
```

This replaces ~40 lines of manual `line()`, `box_top()`, `box_mid()` calls
with a declarative description of intent.
