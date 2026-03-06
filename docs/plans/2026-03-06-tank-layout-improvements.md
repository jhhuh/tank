# tank-layout Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Harden tank-layout with comprehensive tests, optimize the ANSI backend, unify overlay rendering, and complete the Terminal.hs migration to tank-layout.

**Architecture:** Bottom-up approach — fix tests and optimize backends first (Tasks 1-3), then unify Overlay.hs rendering (Task 4), then migrate Terminal.hs pane rendering (Tasks 5-7). Each phase is independently valuable and can be shipped.

**Tech Stack:** Haskell (GHC 9.6+), HSpec, Cairo (PNG backend), cabal

**Prior work:** `docs/plans/2026-03-06-tank-layout-impl.md` (original 10-task plan, completed)

---

### Task 1: Add Render.hs edge case tests

The layout solver has zero tests for its internal helpers. These are the most likely sources of visual bugs.

**Files:**
- Modify: `tank-layout/test/Tank/Layout/RenderSpec.hs`

**Step 1: Write failing tests for splitRect edge cases**

```haskell
-- Add to existing RenderSpec.hs, inside the "renderLayout" describe block

    it "splitRect negative ratio gives 1-row to second child" $ do
      -- withStatusBar uses ratio=-1, meaning second child gets 1 row
      let layout = withStatusBar (text "main") [plainSpan "bar"]
          grid = renderLayout 10 5 layout
      -- Last row (row 4) should have "bar"
      map (\c -> cellChar (getCell grid c 4)) [0..2] `shouldBe` "bar"
      -- Row 3 should still be part of main content (empty/space)
      cellChar (getCell grid 0 3) `shouldBe` ' '

    it "vertical split divides rows" $ do
      let layout = vsplit 0.5 (text "TOP") (text "BOTTOM")
          grid = renderLayout 10 6 layout
      -- TOP at row 0
      map (\c -> cellChar (getCell grid c 0)) [0..2] `shouldBe` "TOP"
      -- BOTTOM at row 3 (6 * 0.5 = 3)
      map (\c -> cellChar (getCell grid c 3)) [0..5] `shouldBe` "BOTTOM"

    it "zero-size rect produces no content" $ do
      let layout = hsplit 1.0 (text "ALL") (text "NONE")
          grid = renderLayout 10 3 layout
      -- ratio=1.0 gives all width to left, none to right
      map (\c -> cellChar (getCell grid c 0)) [0..2] `shouldBe` "ALL"
```

**Step 2: Write tests for multiline text and clipping**

```haskell
    it "renders multiline text with newlines" $ do
      let layout = spans [plainSpan "AB\nCD"]
          grid = renderLayout 10 3 layout
      map (\c -> cellChar (getCell grid c 0)) [0..1] `shouldBe` "AB"
      map (\c -> cellChar (getCell grid c 1)) [0..1] `shouldBe` "CD"

    it "clips text exceeding rect width" $ do
      let layout = hsplit 0.5 (text "LONGTEXT") (text "R")
          grid = renderLayout 6 1 layout
      -- Left pane gets 3 cols, so "LONGTEXT" is clipped to "LON"
      map (\c -> cellChar (getCell grid c 0)) [0..2] `shouldBe` "LON"

    it "border on small rect (2x2) draws only corners" $ do
      let layout = bordered (text "X")
          grid = renderLayout 2 2 layout
      cellChar (getCell grid 0 0) `shouldBe` '\x250C'  -- ┌
      cellChar (getCell grid 1 0) `shouldBe` '\x2510'  -- ┐
      cellChar (getCell grid 0 1) `shouldBe` '\x2514'  -- └
      cellChar (getCell grid 1 1) `shouldBe` '\x2518'  -- ┘
```

**Step 3: Write tests for styled backgrounds and padding**

```haskell
    it "styled background fills rect" $ do
      let green = RGB 0 255 0
          layout = Styled defaultStyle { sBg = Just green } (text "hi")
          grid = renderLayout 5 3 layout
      -- All cells should have green background
      cellBg (getCell grid 4 2) `shouldBe` green
      -- Content cell should also have green bg (preserved by stampSpans)
      cellBg (getCell grid 0 0) `shouldBe` green

    it "padding insets content" $ do
      let layout = Styled defaultStyle { sPadding = Edges 1 1 1 1 }
                     (text "X")
          grid = renderLayout 5 5 layout
      -- Content should be at (1,1) due to padding
      cellChar (getCell grid 1 1) `shouldBe` 'X'
      cellChar (getCell grid 0 0) `shouldBe` ' '
```

**Step 4: Write tests for overlay anchoring**

```haskell
    it "bottom-pinned overlay appears at bottom" $ do
      let layout = bottomPinned (fill '.') (bordered (text "pop"))
          grid = renderLayout 20 10 layout
      -- Bottom row of the grid should have border characters
      -- The overlay should be near the bottom
      cellChar (getCell grid 0 9) `shouldNotBe` '.'

    it "absolute-positioned overlay at specific coords" $ do
      let base = fill '.'
          popup = text "HI"
          layout = Layers base [(Absolute 2 3, popup)]
          grid = renderLayout 20 10 layout
      -- "HI" should appear at col=3, row=2
      cellChar (getCell grid 3 2) `shouldBe` 'H'
      cellChar (getCell grid 4 2) `shouldBe` 'I'
      -- Surrounding cells should still be '.'
      cellChar (getCell grid 0 0) `shouldBe` '.'
```

**Step 5: Run tests**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: All tests PASS (these test existing behavior, not new features)

**Step 6: Commit**

```bash
git add tank-layout/test/Tank/Layout/RenderSpec.hs
git commit -m "test(tank-layout): add edge case tests for Render.hs"
```

---

### Task 2: Add PNG backend smoke tests

The PNG backend has no rendering tests. Add smoke tests that verify basic output properties without pixel-perfect comparison.

**Files:**
- Modify: `tank-layout/test/Tank/Layout/Backend/PNGSpec.hs`

**Step 1: Write PNG rendering smoke tests**

```haskell
-- Replace the existing pendingWith test with actual tests
module Tank.Layout.Backend.PNGSpec (spec) where

import Test.Hspec
import qualified Data.ByteString.Lazy as LBS
import Tank.Layout.Backend.PNG
import Tank.Layout.Cell

spec :: Spec
spec = do
  describe "PNGConfig" $ do
    it "has sensible defaults" $ do
      pngFontSize defaultPNGConfig `shouldBe` 14
      pngTitleBar defaultPNGConfig `shouldBe` True

  describe "renderPNG" $ do
    it "produces non-empty PNG output" $ do
      let grid = stampText (mkGrid 10 3) 0 0 Default Default "hello"
      bs <- renderPNG defaultPNGConfig grid
      LBS.length bs `shouldSatisfy` (> 0)

    it "PNG starts with valid PNG signature" $ do
      let grid = mkGrid 5 2
      bs <- renderPNG defaultPNGConfig grid
      -- PNG magic bytes: 0x89 P N G
      LBS.take 4 bs `shouldBe` LBS.pack [0x89, 0x50, 0x4E, 0x47]

    it "renders without title bar when disabled" $ do
      let config = defaultPNGConfig { pngTitleBar = False }
          grid = mkGrid 5 2
      bs <- renderPNG config grid
      LBS.length bs `shouldSatisfy` (> 0)

  describe "renderMultiPNG" $ do
    it "renders multiple frames" $ do
      let grid1 = stampText (mkGrid 10 3) 0 0 Default Default "frame1"
          grid2 = stampText (mkGrid 10 3) 0 0 Default Default "frame2"
      bs <- renderMultiPNG defaultPNGConfig
              [("Window 1", grid1), ("Window 2", grid2)]
      LBS.length bs `shouldSatisfy` (> 0)

    it "multi-frame PNG is larger than single-frame" $ do
      let grid = mkGrid 10 3
      single <- renderPNG defaultPNGConfig grid
      multi <- renderMultiPNG defaultPNGConfig
                 [("A", grid), ("B", grid)]
      LBS.length multi `shouldSatisfy` (> LBS.length single)
```

**Step 2: Run tests**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: PASS (requires Cairo and font at test time — works in `nix develop`)

**Step 3: Commit**

```bash
git add tank-layout/test/Tank/Layout/Backend/PNGSpec.hs
git commit -m "test(tank-layout): add PNG backend smoke tests"
```

---

### Task 3: Optimize ANSI backend with delta-encoding

Current ANSI backend emits full SGR codes for every cell. For a 120x40 terminal, that's 4800 redundant attribute changes. Delta-encoding only emits SGR when attributes change.

**Files:**
- Modify: `tank-layout/src/Tank/Layout/Backend/ANSI.hs`
- Modify: `tank-layout/test/Tank/Layout/Backend/ANSISpec.hs`

**Step 1: Write test for delta-encoding behavior**

```haskell
-- Add to ANSISpec.hs

    it "does not emit redundant SGR codes for identical adjacent cells" $ do
      -- Two red 'A' cells in a row should only emit the color SGR once
      let red = RGB 255 0 0
          cell = Cell 'A' red Default False False
          grid = setCell (setCell (mkGrid 3 1) 0 0 cell) 1 0 cell
          bs = renderANSI grid
          str = B8.unpack bs
          -- Count occurrences of the red foreground SGR
          count = length $ filter (== True)
                    [ s == "\ESC[38;2;255;0;0m"
                    | s <- tails str, isPrefixOf "\ESC[38;2;255;0;0m" s
                    ]
      -- Should appear only once (at the start), not twice
      count `shouldBe` 1

    it "emits new SGR when color changes between cells" $ do
      let red = RGB 255 0 0
          blue = RGB 0 0 255
          grid = setCell (setCell (mkGrid 2 1) 0 0 (Cell 'R' red Default False False))
                         1 0 (Cell 'B' blue Default False False)
          bs = renderANSI grid
          str = B8.unpack bs
      str `shouldContain` "\ESC[38;2;255;0;0m"
      str `shouldContain` "\ESC[38;2;0;0;255m"
```

Add imports at top of ANSISpec.hs:
```haskell
import Data.List (tails, isPrefixOf)
```

**Step 2: Run tests to verify they fail**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: FAIL — the redundant-SGR test fails because current impl emits SGR per cell

**Step 3: Implement delta-encoding in ANSI.hs**

Replace the current `renderANSI` with a stateful version that tracks previous cell attributes:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.Backend.ANSI
  ( renderANSI
  ) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder, toLazyByteString, char8, string7)
import qualified Data.ByteString.Lazy as LBS
import Data.Word (Word8)
import qualified Data.Vector as V
import Tank.Layout.Cell

-- | Cell attributes that affect SGR output.
data Attrs = Attrs
  { aFg   :: !Color
  , aBg   :: !Color
  , aBold :: !Bool
  , aDim  :: !Bool
  } deriving (Eq)

-- | Initial attributes (nothing set yet — forces first cell to emit all SGRs).
noAttrs :: Attrs
noAttrs = Attrs Default Default False False

cellAttrs :: Cell -> Attrs
cellAttrs (Cell _ fg bg bold dim_) = Attrs fg bg bold dim_

renderANSI :: CellGrid -> ByteString
renderANSI (CellGrid rows) =
  LBS.toStrict $ toLazyByteString $
    snd (V.ifoldl' (\(prev, b) rowIdx row ->
      let nl = if rowIdx < V.length rows - 1 then string7 "\n" else mempty
          (prev', rowB) = renderRow prev row
      in (prev', b <> rowB <> nl)
    ) (noAttrs, mempty) rows)
    <> string7 "\ESC[0m"

renderRow :: Attrs -> V.Vector Cell -> (Attrs, Builder)
renderRow prev row =
  V.foldl' (\(p, b) cell ->
    let a = cellAttrs cell
        sgrB = diffSGR p a
    in (a, b <> sgrB <> char8 (cellChar cell))
  ) (prev, mempty) row

-- | Emit only the SGR codes that differ from previous attributes.
diffSGR :: Attrs -> Attrs -> Builder
diffSGR prev cur =
  let fgB = if aFg prev /= aFg cur then sgrFg (aFg cur) else mempty
      bgB = if aBg prev /= aBg cur then sgrBg (aBg cur) else mempty
      boldB = if aBold prev /= aBold cur then sgrBold (aBold cur) else mempty
      dimB = if aDim prev /= aDim cur then sgrDim (aDim cur) else mempty
  in fgB <> bgB <> boldB <> dimB

sgrFg :: Color -> Builder
sgrFg Default     = string7 "\ESC[39m"
sgrFg (RGB r g b) = string7 "\ESC[38;2;" <> w8 r <> semi <> w8 g <> semi <> w8 b <> string7 "m"

sgrBg :: Color -> Builder
sgrBg Default     = string7 "\ESC[49m"
sgrBg (RGB r g b) = string7 "\ESC[48;2;" <> w8 r <> semi <> w8 g <> semi <> w8 b <> string7 "m"

sgrBold :: Bool -> Builder
sgrBold True  = string7 "\ESC[1m"
sgrBold False = string7 "\ESC[22m"

sgrDim :: Bool -> Builder
sgrDim True  = string7 "\ESC[2m"
sgrDim False = string7 "\ESC[22m"

semi :: Builder
semi = string7 ";"

w8 :: Word8 -> Builder
w8 = string7 . show
```

**Step 4: Run tests**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: All ANSI tests PASS

**Step 5: Commit**

```bash
git add tank-layout/src/Tank/Layout/Backend/ANSI.hs tank-layout/test/Tank/Layout/Backend/ANSISpec.hs
git commit -m "perf(tank-layout): delta-encode SGR in ANSI backend"
```

---

### Task 4: Unify Overlay.hs ANSI rendering with Backend.ANSI

`Overlay.hs` has its own `cellToANSI` function (lines 124-137) that duplicates ANSI backend logic. It also does per-cell SGR (no delta-encoding). Unify it to use the optimized backend.

**Files:**
- Modify: `tank-layout/src/Tank/Layout/Backend/ANSI.hs` (export row-level helper)
- Modify: `src/Tank/Plug/Operator/Overlay.hs`

**Step 1: Export row rendering from ANSI backend**

Add to `Tank.Layout.Backend.ANSI` exports:

```haskell
module Tank.Layout.Backend.ANSI
  ( renderANSI
  , renderRowANSI  -- NEW: render a single row with delta-encoding
  ) where
```

Add public wrapper:

```haskell
-- | Render a single row of cells to ANSI, with delta-encoding from given
-- previous attributes. Returns (final attrs, builder).
-- Useful for stamping rows at arbitrary terminal positions.
renderRowANSI :: V.Vector Cell -> ByteString
renderRowANSI row =
  LBS.toStrict $ toLazyByteString $
    snd (renderRow noAttrs row) <> string7 "\ESC[0m"
```

**Step 2: Read current Overlay.hs rendering code**

Read `src/Tank/Plug/Operator/Overlay.hs` lines 110-140 to understand the current `renderGridRow` and `cellToANSI` functions. They do:
- Move cursor to absolute position with `\ESC[row;colH`
- Emit per-cell SGR + character
- Reset at end of row

**Step 3: Replace Overlay.hs ANSI helpers with backend import**

In `Overlay.hs`, replace the custom `renderGridRow`/`cellToANSI` with:

```haskell
import Tank.Layout.Backend.ANSI (renderRowANSI)
```

Keep the cursor-positioning logic (that's terminal-specific), but delegate cell rendering to the backend.

Replace:
```haskell
renderGridRow :: Int -> Int -> V.Vector Cell -> Builder
renderGridRow screenRow screenCol row =
  cursorTo screenRow screenCol <> V.foldl' (\b cell -> b <> cellToANSI cell) mempty row <> resetSGR
```

With:
```haskell
renderGridRow :: Int -> Int -> V.Vector Cell -> Builder
renderGridRow screenRow screenCol row =
  cursorTo screenRow screenCol <> byteString (renderRowANSI row)
```

Remove the now-unused `cellToANSI` function.

**Step 4: Run tests**

Run: `nix develop -c cabal test`
Expected: All tests PASS (both tank and tank-layout)

**Step 5: Commit**

```bash
git add tank-layout/src/Tank/Layout/Backend/ANSI.hs src/Tank/Plug/Operator/Overlay.hs
git commit -m "refactor: unify overlay ANSI rendering with tank-layout backend"
```

---

### Task 5: Create VTerm-to-CellGrid adapter

Terminal.hs uses `VTerm` grids with `Color256` colors. Tank-layout uses `CellGrid` with `RGB` colors. Bridge them with a conversion module.

**Files:**
- Create: `src/Tank/Terminal/CellAdapter.hs`
- Create: `tests/Tank/Terminal/CellAdapterSpec.hs`
- Modify: `tank.cabal` (add new module)

**Step 1: Write failing test**

```haskell
-- tests/Tank/Terminal/CellAdapterSpec.hs
module Tank.Terminal.CellAdapterSpec (spec) where

import Test.Hspec
import Tank.Terminal.CellAdapter
import qualified Tank.Terminal.Grid as VT
import qualified Tank.Layout.Cell as LC

spec :: Spec
spec = do
  describe "vTermToLayoutGrid" $ do
    it "converts a VTerm grid to a CellGrid" $ do
      -- Create a small VTerm grid, convert, check dimensions match
      let vtGrid = VT.newGrid 10 3
      let lcGrid = vTermToLayoutGrid vtGrid
      LC.gridWidth lcGrid `shouldBe` 10
      LC.gridHeight lcGrid `shouldBe` 3

    it "preserves character content" $ do
      let vtGrid = VT.writeChar (VT.newGrid 5 1) 0 0 'X'
          lcGrid = vTermToLayoutGrid vtGrid
      LC.cellChar (LC.getCell lcGrid 0 0) `shouldBe` 'X'
```

Note: Exact VTerm API calls depend on `Tank.Terminal.Grid` exports. Read the module to confirm function names before implementing.

**Step 2: Run test to verify it fails**

Run: `nix develop -c cabal test`
Expected: FAIL — module not found

**Step 3: Read Tank.Terminal.Grid to understand VTerm cell structure**

Read: `src/Tank/Terminal/Grid.hs`

Key types to find:
- VTerm cell type (character + foreground + background + attributes)
- Color representation (Color256? ANSI palette? Direct RGB?)
- Grid accessor functions

**Step 4: Implement CellAdapter.hs**

```haskell
-- src/Tank/Terminal/CellAdapter.hs
module Tank.Terminal.CellAdapter
  ( vTermToLayoutGrid
  ) where

import qualified Tank.Terminal.Grid as VT
import qualified Tank.Layout.Cell as LC
import qualified Data.Vector as V

-- | Convert a VTerm grid region to a tank-layout CellGrid.
-- Copies characters and converts colors from VTerm's color model to RGB.
vTermToLayoutGrid :: VT.Grid -> LC.CellGrid
vTermToLayoutGrid vtGrid =
  let w = VT.gridWidth vtGrid
      h = VT.gridHeight vtGrid
      rows = V.generate h $ \r ->
        V.generate w $ \c ->
          convertCell (VT.getCell vtGrid c r)
  in LC.CellGrid rows

convertCell :: VT.Cell -> LC.Cell
convertCell vc = LC.Cell
  { LC.cellChar = VT.cellChar vc
  , LC.cellFg   = convertColor (VT.cellFg vc)
  , LC.cellBg   = convertColor (VT.cellBg vc)
  , LC.cellBold = VT.cellBold vc
  , LC.cellDim  = False  -- VTerm may not track dim
  }

-- | Convert VTerm color to tank-layout Color.
-- Adapt this based on actual VTerm color representation.
convertColor :: VT.Color -> LC.Color
convertColor VT.DefaultColor = LC.Default
convertColor (VT.Color256 n) = LC.RGB r g b
  where (r, g, b) = ansi256ToRGB n
convertColor (VT.DirectRGB r g b) = LC.RGB r g b

-- | ANSI 256-color palette to RGB lookup.
-- Standard: 0-7 normal, 8-15 bright, 16-231 color cube, 232-255 grayscale.
ansi256ToRGB :: Word8 -> (Word8, Word8, Word8)
ansi256ToRGB n
  | n < 16    = ansi16 !! fromIntegral n
  | n < 232   = let n' = n - 16
                    r = (n' `div` 36) * 51
                    g = ((n' `mod` 36) `div` 6) * 51
                    b = (n' `mod` 6) * 51
                in (r, g, b)
  | otherwise = let g = 8 + (n - 232) * 10
                in (g, g, g)

-- Standard ANSI 16-color palette (approximate)
ansi16 :: [(Word8, Word8, Word8)]
ansi16 =
  [ (0,0,0), (170,0,0), (0,170,0), (170,85,0)
  , (0,0,170), (170,0,170), (0,170,170), (170,170,170)
  , (85,85,85), (255,85,85), (85,255,85), (255,255,85)
  , (85,85,255), (255,85,255), (85,255,255), (255,255,255)
  ]
```

Note: The exact `VT.Color` type and `VT.Cell` accessors must be confirmed by reading `Tank.Terminal.Grid`. The implementation above is a template — adapt field names to match.

**Step 5: Add module to cabal, run tests**

Run: `nix develop -c cabal test`
Expected: PASS

**Step 6: Commit**

```bash
git add src/Tank/Terminal/CellAdapter.hs tests/Tank/Terminal/CellAdapterSpec.hs tank.cabal
git commit -m "feat: add VTerm-to-CellGrid adapter for tank-layout integration"
```

---

### Task 6: Migrate Terminal.hs pane rendering to tank-layout

Replace `renderPaneLayout` (the manual recursive renderer with inline border drawing) with a function that converts the `PaneLayout` tree to a `Tank.Layout.Layout`, calls `renderLayout`, and emits the result.

**Files:**
- Modify: `src/Tank/Plug/Terminal.hs`

**Step 1: Read Terminal.hs rendering functions**

Read: `src/Tank/Plug/Terminal.hs:443-501`

Understand:
- `renderPaneLayout` recursively walks `PaneLayout`, computing regions and drawing borders
- `renderVTermAt` stamps VTerm cells at screen positions with delta-encoded ANSI
- Border characters: `│` (U+2502) and `─` (U+2500) drawn between split children

**Step 2: Create layout conversion function**

Add to Terminal.hs (or a new helper module):

```haskell
import Tank.Terminal.CellAdapter (vTermToLayoutGrid)
import Tank.Layout.Types (Layout(..), Content(..), Dir(..))
import Tank.Layout.Cell (CellGrid)
import Tank.Layout.Render (renderLayout)

-- | Convert a PaneLayout tree to a tank-layout Layout tree.
-- Each LPane leaf becomes a CellContent node with the VTerm grid converted.
paneLayoutToLayout :: Map Int Pane -> PaneLayout -> Layout
paneLayoutToLayout panes (LPane pId) =
  case Map.lookup pId panes of
    Just pane -> Leaf (CellContent (vTermToLayoutGrid (paneVTerm pane)))
    Nothing   -> Leaf (Fill ' ' Default)
paneLayoutToLayout panes (LSplit dir ratio l r) =
  Split (convertDir dir) ratio
    (paneLayoutToLayout panes l)
    (paneLayoutToLayout panes r)

convertDir :: PaneSplit -> Dir
convertDir PHorizontal = Horizontal
convertDir PVertical   = Vertical
```

**Step 3: Replace renderPaneLayout**

Replace the body of `renderPaneLayout` with:

```haskell
renderPaneLayout :: TermState -> Int -> Int -> Builder
renderPaneLayout st w h =
  let layout = paneLayoutToLayout (tsPanes st) (winLayout (tsActiveWindow st))
      grid = renderLayout w h layout
  in gridToANSI grid  -- use Backend.ANSI or custom stamping
```

Note: The exact replacement depends on how the current rendering interacts with cursor positioning and scroll regions. The key insight is that `renderLayout` produces a `CellGrid` that can be emitted with the ANSI backend. If absolute cursor positioning is needed (e.g., partial screen updates), keep the region-based approach but use `vTermToLayoutGrid` for cell conversion.

**Step 4: Handle active-pane border highlighting**

Current code draws borders in different colors based on which pane is active. To preserve this in tank-layout:

- Wrap each `Split` node in `Styled` with a border whose color depends on whether the active pane is in the left or right subtree
- Or: post-process the `CellGrid` to recolor border cells adjacent to the active pane

The simpler approach: keep the existing border rendering for now and only migrate content stamping. This is an incremental migration — full border unification can come later.

**Step 5: Run tests**

Run: `nix develop -c cabal test`
Expected: All existing terminal tests PASS

**Step 6: Manual verification**

Run: `nix develop -c cabal run tank`
Verify: Pane splits render correctly, borders show between panes, content matches.

**Step 7: Commit**

```bash
git add src/Tank/Plug/Terminal.hs
git commit -m "refactor: migrate Terminal.hs pane rendering to tank-layout"
```

---

### Task 7: Remove dead layout code from Terminal.hs

After migration, remove the inline rendering functions that are now replaced by tank-layout.

**Files:**
- Modify: `src/Tank/Plug/Terminal.hs`

**Step 1: Identify dead code**

After Task 6, the following functions should be unused:
- `renderVTermAt` (replaced by CellAdapter + renderLayout)
- Manual border-drawing code within `renderPaneLayout` (replaced by tank-layout borders)
- Any helper functions only called by the old rendering path

**Step 2: Remove dead functions**

Delete the identified functions. Keep `findPaneRegion` — it's still needed for cursor positioning and resize calculations.

**Step 3: Verify no compilation errors**

Run: `nix develop -c cabal build all`
Expected: Clean build

**Step 4: Run full test suite**

Run: `nix develop -c cabal test`
Expected: All PASS

**Step 5: Commit**

```bash
git add src/Tank/Plug/Terminal.hs
git commit -m "refactor: remove dead inline layout rendering code"
```

---

## Task Dependency Graph

```
Task 1 (render tests)     Task 2 (PNG tests)
      │                        │
      └──────┬─────────────────┘
             │
        Task 3 (ANSI delta-encoding)
             │
        Task 4 (unify overlay ANSI)
             │
        Task 5 (VTerm adapter)
             │
        Task 6 (Terminal.hs migration)
             │
        Task 7 (dead code removal)
```

Tasks 1 and 2 are independent and can be parallelized.
Tasks 3-7 are sequential (each builds on the previous).
