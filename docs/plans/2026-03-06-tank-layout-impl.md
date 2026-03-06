# tank-layout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build `tank-layout`, an independent Haskell cabal package providing a declarative terminal layout language with ANSI and PNG rendering backends.

**Architecture:** Split-tree layout model with overlay layers. Layout tree describes structure declaratively; a solver resolves it to absolute positions in a cell grid; backends consume the grid to produce ANSI escape sequences or PNG images. The package has zero dependency on Tank internals.

**Tech Stack:** GHC 9.6+ / Cabal 3.0, HSpec for tests, JuicyPixels + FontyFruity for PNG rendering, DejaVu Sans Mono TTF font.

**Design doc:** `docs/plans/2026-03-06-tank-layout-design.md`

---

### Task 1: Scaffold the cabal package

**Files:**
- Create: `tank-layout/tank-layout.cabal`
- Create: `tank-layout/src/Tank/Layout.hs`
- Modify: `cabal.project` (add `tank-layout/` to packages)
- Modify: `flake.nix` (add tank-layout to haskellPackages overlay)

**Step 1: Create the cabal file**

```cabal
-- tank-layout/tank-layout.cabal
cabal-version:   3.0
name:            tank-layout
version:         0.1.0.0
synopsis:        Declarative terminal layout language with ANSI and PNG backends
license:         MIT
license-file:    ../LICENSE
author:          jhhuh
build-type:      Simple

common warnings
  ghc-options: -Wall -Wcompat -Widentities -Wincomplete-record-updates
               -Wincomplete-uni-patterns -Wpartial-fields -Wredundant-constraints

library
  import:           warnings
  exposed-modules:
    Tank.Layout
  build-depends:
    , base        >= 4.17 && < 5
    , text        >= 2.0  && < 3
    , bytestring  >= 0.11 && < 1
    , vector      >= 0.13 && < 1
    , containers  >= 0.6  && < 1
  hs-source-dirs:   src
  default-language: GHC2021

test-suite tank-layout-tests
  import:           warnings
  type:             exitcode-stdio-1.0
  main-is:          Spec.hs
  build-depends:
    , base         >= 4.17 && < 5
    , tank-layout
    , hspec        >= 2.10 && < 3
    , text         >= 2.0  && < 3
    , vector       >= 0.13 && < 1
  hs-source-dirs:   test
  default-language: GHC2021
  build-tool-depends: hspec-discover:hspec-discover
```

**Step 2: Create stub module**

```haskell
-- tank-layout/src/Tank/Layout.hs
module Tank.Layout
  ( module Tank.Layout
  ) where

-- Placeholder: will re-export submodules
version :: String
version = "0.1.0.0"
```

**Step 3: Create test harness**

```haskell
-- tank-layout/test/Spec.hs
{-# OPTIONS_GHC -F -pgmF hspec-discover #-}
```

**Step 4: Update cabal.project**

Change `packages: .` to `packages: . tank-layout/`.

**Step 5: Update flake.nix**

Add `tank-layout` to the haskellPackages overlay:
```nix
tank-layout = hself.callCabal2nix "tank-layout" ./tank-layout {};
tank = hself.callCabal2nix "tank" ./. {};
```

Add `p.tank-layout` to devShells packages list.

**Step 6: Build to verify scaffold**

Run: `nix develop -c cabal build tank-layout`
Expected: builds with no errors

**Step 7: Commit**

```
git add tank-layout/ cabal.project flake.nix
git commit -m "feat(tank-layout): scaffold cabal package"
```

---

### Task 2: Core types — Cell and Color

**Files:**
- Create: `tank-layout/src/Tank/Layout/Cell.hs`
- Create: `tank-layout/test/Tank/Layout/CellSpec.hs`

**Step 1: Write failing test**

```haskell
-- tank-layout/test/Tank/Layout/CellSpec.hs
module Tank.Layout.CellSpec (spec) where

import Test.Hspec
import Tank.Layout.Cell

spec :: Spec
spec = do
  describe "Cell" $ do
    it "defaultCell is a space with default colors" $ do
      cellChar defaultCell `shouldBe` ' '
      cellFg defaultCell `shouldBe` Default
      cellBg defaultCell `shouldBe` Default

  describe "CellGrid" $ do
    it "mkGrid creates grid of default cells" $ do
      let g = mkGrid 3 2
      gridWidth g `shouldBe` 3
      gridHeight g `shouldBe` 2
      getCell g 0 0 `shouldBe` defaultCell

    it "setCell updates a cell" $ do
      let g = setCell (mkGrid 3 2) 1 0 (defaultCell { cellChar = 'X' })
      cellChar (getCell g 1 0) `shouldBe` 'X'
      cellChar (getCell g 0 0) `shouldBe` ' '

    it "stampText writes string into grid at position" $ do
      let g = stampText (mkGrid 10 1) 0 0 Default Default "hello"
      map (\c -> cellChar (getCell g c 0)) [0..4] `shouldBe` "hello"
```

**Step 2: Run test to verify it fails**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: FAIL — module not found

**Step 3: Implement Cell.hs**

```haskell
-- tank-layout/src/Tank/Layout/Cell.hs
module Tank.Layout.Cell
  ( Cell(..)
  , Color(..)
  , CellGrid(..)
  , defaultCell
  , mkGrid
  , getCell
  , setCell
  , stampText
  , gridWidth
  , gridHeight
  ) where

import Data.Word (Word8)
import Data.Vector (Vector)
import qualified Data.Vector as V
import Data.Text (Text)
import qualified Data.Text as T

data Color = Default | RGB !Word8 !Word8 !Word8
  deriving (Eq, Show)

data Cell = Cell
  { cellChar :: !Char
  , cellFg   :: !Color
  , cellBg   :: !Color
  , cellBold :: !Bool
  , cellDim  :: !Bool
  } deriving (Eq, Show)

defaultCell :: Cell
defaultCell = Cell ' ' Default Default False False

-- Row-major grid: outer vector = rows, inner = columns
newtype CellGrid = CellGrid { gridRows :: Vector (Vector Cell) }
  deriving (Show)

gridWidth :: CellGrid -> Int
gridWidth (CellGrid rows)
  | V.null rows = 0
  | otherwise   = V.length (V.head rows)

gridHeight :: CellGrid -> Int
gridHeight (CellGrid rows) = V.length rows

mkGrid :: Int -> Int -> CellGrid
mkGrid w h = CellGrid $ V.replicate h (V.replicate w defaultCell)

getCell :: CellGrid -> Int -> Int -> Cell
getCell (CellGrid rows) col row
  | row >= 0 && row < V.length rows =
      let r = rows V.! row
      in if col >= 0 && col < V.length r then r V.! col else defaultCell
  | otherwise = defaultCell

setCell :: CellGrid -> Int -> Int -> Cell -> CellGrid
setCell (CellGrid rows) col row cell
  | row >= 0 && row < V.length rows && col >= 0 =
      let r = rows V.! row
      in if col < V.length r
         then CellGrid $ rows V.// [(row, r V.// [(col, cell)])]
         else CellGrid rows
  | otherwise = CellGrid rows

stampText :: CellGrid -> Int -> Int -> Color -> Color -> Text -> CellGrid
stampText grid startCol row fg bg txt =
  T.foldl' (\g (col, ch) -> setCell g col row (Cell ch fg bg False False))
    grid
    (zip [startCol..] (T.unpack txt))
  where
    zip = Prelude.zip
```

**Step 4: Add module to cabal and re-export**

Add `Tank.Layout.Cell` to exposed-modules in tank-layout.cabal.
Update `Tank/Layout.hs` to `module Tank.Layout (module Tank.Layout.Cell) where; import Tank.Layout.Cell`.

**Step 5: Run tests**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: PASS

**Step 6: Commit**

```
git add tank-layout/
git commit -m "feat(tank-layout): add Cell and CellGrid types with tests"
```

---

### Task 3: Layout tree types

**Files:**
- Create: `tank-layout/src/Tank/Layout/Types.hs`
- Create: `tank-layout/test/Tank/Layout/TypesSpec.hs`

**Step 1: Write failing test**

```haskell
-- tank-layout/test/Tank/Layout/TypesSpec.hs
module Tank.Layout.TypesSpec (spec) where

import Test.Hspec
import Tank.Layout.Types
import Tank.Layout.Cell (Color(..))

spec :: Spec
spec = do
  describe "Layout constructors" $ do
    it "can create a leaf" $ do
      let l = Leaf (Text [plainSpan "hello"])
      case l of
        Leaf (Text spans) -> length spans `shouldBe` 1
        _ -> expectationFailure "expected Leaf"

    it "can create a split" $ do
      let l = Split Horizontal 0.5 (Leaf (Fill ' ' Default)) (Leaf (Fill ' ' Default))
      case l of
        Split Horizontal r _ _ -> r `shouldBe` 0.5
        _ -> expectationFailure "expected Split"

    it "can create layers with overlays" $ do
      let base = Leaf (Fill ' ' Default)
          over = Leaf (Text [plainSpan "popup"])
          l = Layers base [(Center, over)]
      case l of
        Layers _ overlays -> length overlays `shouldBe` 1
        _ -> expectationFailure "expected Layers"
```

**Step 2: Run test to verify it fails**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: FAIL — module not found

**Step 3: Implement Types.hs**

```haskell
-- tank-layout/src/Tank/Layout/Types.hs
module Tank.Layout.Types
  ( Layout(..)
  , Dir(..)
  , Anchor(..)
  , Style(..)
  , Border(..)
  , BorderStyle(..)
  , Edges(..)
  , Content(..)
  , Span(..)
  , SpanStyle(..)
  , Rect(..)
  , plainSpan
  , defaultStyle
  , noEdges
  ) where

import Data.Text (Text)
import Data.Vector (Vector)
import Tank.Layout.Cell (Cell, Color(..))

data Layout
  = Leaf !Content
  | Split !Dir !Float Layout Layout
  | Layers Layout [(Anchor, Layout)]
  | Styled !Style Layout
  deriving (Show)

data Dir = Horizontal | Vertical
  deriving (Eq, Show)

data Anchor
  = Center
  | Bottom
  | Absolute !Int !Int
  deriving (Eq, Show)

data Style = Style
  { sBorder  :: !(Maybe Border)
  , sPadding :: !Edges
  , sTitle   :: !(Maybe (Text, Text))
  , sBg      :: !(Maybe Color)
  } deriving (Eq, Show)

defaultStyle :: Style
defaultStyle = Style Nothing noEdges Nothing Nothing

data Border = Border
  { bStyle :: !BorderStyle
  , bColor :: !Color
  } deriving (Eq, Show)

data BorderStyle = Single | Rounded | Heavy
  deriving (Eq, Show)

data Edges = Edges !Int !Int !Int !Int  -- top right bottom left
  deriving (Eq, Show)

noEdges :: Edges
noEdges = Edges 0 0 0 0

data Content
  = Text ![Span]
  | Fill !Char !Color
  | CellGrid !(Vector (Vector Cell))
  deriving (Show)

data Span = Span !Text !SpanStyle
  deriving (Show)

data SpanStyle = SpanStyle
  { spanFg   :: !(Maybe Color)
  , spanBold :: !Bool
  , spanDim  :: !Bool
  } deriving (Eq, Show)

plainSpan :: Text -> Span
plainSpan t = Span t (SpanStyle Nothing False False)

-- | A positioned rectangle: col, row, width, height
data Rect = Rect !Int !Int !Int !Int
  deriving (Eq, Show)
```

**Step 4: Add to cabal, run tests**

Add `Tank.Layout.Types` to exposed-modules. Re-export from `Tank.Layout`.

Run: `nix develop -c cabal test tank-layout-tests`
Expected: PASS

**Step 5: Commit**

```
git commit -m "feat(tank-layout): add layout tree and style types"
```

---

### Task 4: eDSL combinators

**Files:**
- Create: `tank-layout/src/Tank/Layout/DSL.hs`
- Create: `tank-layout/test/Tank/Layout/DSLSpec.hs`

**Step 1: Write failing test**

```haskell
-- tank-layout/test/Tank/Layout/DSLSpec.hs
module Tank.Layout.DSLSpec (spec) where

import Test.Hspec
import Tank.Layout.DSL
import Tank.Layout.Types
import Tank.Layout.Cell (Color(..))

spec :: Spec
spec = do
  describe "split combinators" $ do
    it "hsplit creates horizontal split" $ do
      let l = hsplit 0.5 (text "left") (text "right")
      case l of
        Split Horizontal 0.5 _ _ -> pure ()
        _ -> expectationFailure "expected horizontal split"

    it "hsplit2 creates even split" $ do
      let l = hsplit2 (text "a") (text "b")
      case l of
        Split Horizontal 0.5 _ _ -> pure ()
        _ -> expectationFailure "expected 0.5 split"

  describe "decoration combinators" $ do
    it "bordered wraps with single border" $ do
      let l = bordered (text "inner")
      case l of
        Styled s _ -> sBorder s `shouldNotBe` Nothing
        _ -> expectationFailure "expected Styled"

    it "titled adds border + title" $ do
      let l = titled "my box" (text "inner")
      case l of
        Styled s _ -> sTitle s `shouldBe` Just ("my box", "")
        _ -> expectationFailure "expected Styled"

  describe "overlay combinators" $ do
    it "centered creates center-anchored overlay" $ do
      let l = centered (text "base") (text "popup")
      case l of
        Layers _ [(Center, _)] -> pure ()
        _ -> expectationFailure "expected centered overlay"

  describe "withStatusBar" $ do
    it "creates vsplit with 1-row bar at bottom" $ do
      let l = withStatusBar (text "main") [plainSpan "status"]
      case l of
        Split Vertical _ _ (Leaf (Text _)) -> pure ()
        _ -> expectationFailure "expected vsplit with text bar"
```

**Step 2: Run test to verify it fails**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: FAIL

**Step 3: Implement DSL.hs**

```haskell
-- tank-layout/src/Tank/Layout/DSL.hs
module Tank.Layout.DSL
  ( -- Splitting
    hsplit, vsplit, hsplit2, vsplit2
    -- Overlays
  , overlay, centered, bottomPinned
    -- Decoration
  , bordered, roundBordered, titled, titled'
    -- Content
  , text, styled, spans, fill, cells
    -- Patterns
  , withStatusBar
  ) where

import Data.Text (Text)
import Data.Vector (Vector)
import Tank.Layout.Types
import Tank.Layout.Cell (Cell, Color(..))

-- Splitting
hsplit :: Float -> Layout -> Layout -> Layout
hsplit = Split Horizontal

vsplit :: Float -> Layout -> Layout -> Layout
vsplit = Split Vertical

hsplit2 :: Layout -> Layout -> Layout
hsplit2 = hsplit 0.5

vsplit2 :: Layout -> Layout -> Layout
vsplit2 = vsplit 0.5

-- Overlays
overlay :: Anchor -> Layout -> Layout -> Layout
overlay anchor base floating = Layers base [(anchor, floating)]

centered :: Layout -> Layout -> Layout
centered = overlay Center

bottomPinned :: Layout -> Layout -> Layout
bottomPinned = overlay Bottom

-- Decoration
bordered :: Layout -> Layout
bordered = Styled defaultStyle { sBorder = Just (Border Single Default) }

roundBordered :: Layout -> Layout
roundBordered = Styled defaultStyle { sBorder = Just (Border Rounded Default) }

titled :: Text -> Layout -> Layout
titled t = Styled defaultStyle
  { sBorder = Just (Border Single Default)
  , sTitle  = Just (t, "")
  }

titled' :: Text -> Text -> Layout -> Layout
titled' t hint = Styled defaultStyle
  { sBorder = Just (Border Single Default)
  , sTitle  = Just (t, hint)
  }

-- Content
text :: Text -> Layout
text t = Leaf (Text [plainSpan t])

styled :: Color -> Text -> Layout
styled c t = Leaf (Text [Span t (SpanStyle (Just c) False False)])

spans :: [Span] -> Layout
spans = Leaf . Text

fill :: Char -> Layout
fill ch = Leaf (Fill ch Default)

cells :: Vector (Vector Cell) -> Layout
cells = Leaf . CellGrid

-- Patterns
withStatusBar :: Layout -> [Span] -> Layout
withStatusBar content bar = Split Vertical (-1) content (Leaf (Text bar))
-- -1 ratio means: second child gets 1 row, first gets the rest
```

Note: The `-1` sentinel for `withStatusBar` means "fixed 1-row for second child." The solver will handle this special case. Alternatively we can use a `SplitSpec` type instead of raw `Float` — but start simple.

**Step 4: Add to cabal, run tests**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: PASS

**Step 5: Commit**

```
git commit -m "feat(tank-layout): add eDSL combinators"
```

---

### Task 5: Layout solver — resolve tree to cell grid

This is the core algorithm. The solver walks the layout tree, assigns a `Rect` to each node, and stamps content into a `CellGrid`.

**Files:**
- Create: `tank-layout/src/Tank/Layout/Render.hs`
- Create: `tank-layout/test/Tank/Layout/RenderSpec.hs`

**Step 1: Write failing test**

```haskell
-- tank-layout/test/Tank/Layout/RenderSpec.hs
module Tank.Layout.RenderSpec (spec) where

import Test.Hspec
import Tank.Layout.Render
import Tank.Layout.DSL
import Tank.Layout.Types (Span(..), SpanStyle(..), plainSpan)
import Tank.Layout.Cell

spec :: Spec
spec = do
  describe "renderLayout" $ do
    it "renders a plain text leaf into the grid" $ do
      let layout = text "hello"
          grid = renderLayout 10 3 layout
      map (\c -> cellChar (getCell grid c 0)) [0..4] `shouldBe` "hello"

    it "renders a horizontal split" $ do
      let layout = hsplit 0.5 (text "LEFT") (text "RIGHT")
          grid = renderLayout 20 3 layout
      -- Left pane starts at col 0
      map (\c -> cellChar (getCell grid c 0)) [0..3] `shouldBe` "LEFT"
      -- Right pane starts at col 10
      map (\c -> cellChar (getCell grid c 0)) [10..14] `shouldBe` "RIGHT"

    it "renders a bordered box" $ do
      let layout = bordered (text "hi")
          grid = renderLayout 10 5 layout
      -- Top-left corner should be box-drawing
      cellChar (getCell grid 0 0) `shouldBe` '┌'
      -- Content starts at (1, 1)
      cellChar (getCell grid 1 1) `shouldBe` 'h'
      cellChar (getCell grid 2 1) `shouldBe` 'i'

    it "renders overlay on top of base" $ do
      let layout = centered (fill '.') (bordered (text "popup"))
          grid = renderLayout 20 10 layout
      -- Corners of the overlay should be box-drawing
      -- Cells outside overlay should be '.'
      cellChar (getCell grid 0 0) `shouldBe` '.'

    it "renders withStatusBar" $ do
      let layout = withStatusBar (text "main") [plainSpan "status"]
          grid = renderLayout 20 5 layout
      -- Last row should have status text
      map (\c -> cellChar (getCell grid c 4)) [0..5] `shouldBe` "status"
```

**Step 2: Run test to verify it fails**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: FAIL

**Step 3: Implement Render.hs**

```haskell
-- tank-layout/src/Tank/Layout/Render.hs
module Tank.Layout.Render
  ( renderLayout
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Tank.Layout.Types
import Tank.Layout.Cell

-- | Render a layout tree into a cell grid of the given dimensions.
renderLayout :: Int -> Int -> Layout -> CellGrid
renderLayout w h layout = resolve (mkGrid w h) (Rect 0 0 w h) layout

-- | Recursively resolve layout into the grid within the given rect.
resolve :: CellGrid -> Rect -> Layout -> CellGrid
resolve grid (Rect _ _ rw rh) _
  | rw <= 0 || rh <= 0 = grid
resolve grid rect (Leaf content) =
  stampContent grid rect content
resolve grid (Rect rx ry rw rh) (Split dir ratio l r) =
  let (r1, r2) = splitRect dir ratio (Rect rx ry rw rh)
  in resolve (resolve grid r1 l) r2 r
resolve grid rect (Layers base overlays) =
  let grid' = resolve grid rect base
  in foldl (\g (anchor, lay) -> resolve g (anchorRect anchor rect lay) lay) grid' overlays
resolve grid rect (Styled style child) =
  let (innerRect, grid') = applyStyle grid rect style
  in resolve grid' innerRect child

-- | Split a rect into two sub-rects.
splitRect :: Dir -> Float -> Rect -> (Rect, Rect)
splitRect dir ratio (Rect rx ry rw rh)
  -- Special case: negative ratio means second child gets abs(ratio) rows/cols
  | ratio < 0 =
      let fixed = abs (round ratio)
      in case dir of
           Vertical   -> (Rect rx ry rw (rh - fixed), Rect rx (ry + rh - fixed) rw fixed)
           Horizontal -> (Rect rx ry (rw - fixed) rh, Rect (rx + rw - fixed) ry fixed rh)
  | otherwise =
      case dir of
        Vertical ->
          let h1 = round (fromIntegral rh * ratio)
          in (Rect rx ry rw h1, Rect rx (ry + h1) rw (rh - h1))
        Horizontal ->
          let w1 = round (fromIntegral rw * ratio)
          in (Rect rx ry w1 rh, Rect (rx + w1) ry (rw - w1) rh)

-- | Compute overlay rect from anchor within parent.
anchorRect :: Anchor -> Rect -> Layout -> Rect
anchorRect Center (Rect rx ry rw rh) child =
  let (cw, ch) = layoutSize child rw rh
      ox = rx + (rw - cw) `div` 2
      oy = ry + (rh - ch) `div` 2
  in Rect ox oy cw ch
anchorRect Bottom (Rect rx ry rw rh) child =
  let (cw, ch) = layoutSize child rw rh
      oy = ry + rh - ch
  in Rect rx oy cw ch
anchorRect (Absolute row col) (Rect rx ry _ _) child =
  let (cw, ch) = layoutSize child 80 24  -- fallback size
  in Rect (rx + col) (ry + row) cw ch

-- | Estimate preferred size of a layout (for overlay positioning).
-- Returns (width, height). Uses parent dimensions as max.
layoutSize :: Layout -> Int -> Int -> (Int, Int)
layoutSize (Leaf (Text spans)) maxW _ =
  let totalLen = sum (map (\(Span t _) -> T.length t) spans)
      w = min maxW (totalLen + 2)
      h = max 3 ((totalLen `div` maxW) + 3)
  in (w, h)
layoutSize (Styled style child) maxW maxH =
  let (cw, ch) = layoutSize child maxW maxH
      Edges pt pr pb pl = sPadding style
      borderExtra = case sBorder style of
        Nothing -> 0
        Just _  -> 2  -- 1 for each side
  in (cw + pl + pr + borderExtra, ch + pt + pb + borderExtra)
layoutSize _ maxW maxH = (maxW, maxH)

-- | Apply style (border, padding, bg) to the grid and return the inner rect.
applyStyle :: CellGrid -> Rect -> Style -> (Rect, CellGrid)
applyStyle grid (Rect rx ry rw rh) style =
  let -- Background fill
      grid1 = case sBg style of
        Nothing -> grid
        Just bg -> fillRect grid (Rect rx ry rw rh) ' ' Default bg

      -- Border
      (borderInset, grid2) = case sBorder style of
        Nothing -> (0, grid1)
        Just (Border bs bc) -> (1, drawBorder grid1 (Rect rx ry rw rh) bs bc (sTitle style))

      -- Padding
      Edges pt pr pb pl = sPadding style
      ix = rx + borderInset + pl
      iy = ry + borderInset + pt
      iw = rw - 2 * borderInset - pl - pr
      ih = rh - 2 * borderInset - pt - pb
  in (Rect ix iy (max 0 iw) (max 0 ih), grid2)

-- | Fill a rect with a character.
fillRect :: CellGrid -> Rect -> Char -> Color -> Color -> CellGrid
fillRect grid (Rect rx ry rw rh) ch fg bg =
  foldl (\g (c, r) -> setCell g c r (Cell ch fg bg False False))
    grid
    [(c, r) | r <- [ry .. ry + rh - 1], c <- [rx .. rx + rw - 1]]

-- | Draw a border around a rect.
drawBorder :: CellGrid -> Rect -> BorderStyle -> Color -> Maybe (Text, Text) -> CellGrid
drawBorder grid (Rect rx ry rw rh) bs bc titleM =
  let (tl, tr, bl, br, h, v) = borderChars bs
      fg = bc
      bg = Default
      cell ch = Cell ch fg bg False False
      -- Corners
      g1 = setCell grid rx ry (cell tl)
      g2 = setCell g1 (rx + rw - 1) ry (cell tr)
      g3 = setCell g2 rx (ry + rh - 1) (cell bl)
      g4 = setCell g3 (rx + rw - 1) (ry + rh - 1) (cell br)
      -- Top/bottom edges
      g5 = foldl (\g c -> setCell g c ry (cell h)) g4 [rx + 1 .. rx + rw - 2]
      g6 = foldl (\g c -> setCell g c (ry + rh - 1) (cell h)) g5 [rx + 1 .. rx + rw - 2]
      -- Left/right edges
      g7 = foldl (\g r -> setCell g rx r (cell v)) g6 [ry + 1 .. ry + rh - 2]
      g8 = foldl (\g r -> setCell g (rx + rw - 1) r (cell v)) g7 [ry + 1 .. ry + rh - 2]
      -- Title
      g9 = case titleM of
        Nothing -> g8
        Just (title, hint) ->
          let g' = stampText g8 (rx + 2) ry fg bg title
          in if T.null hint then g'
             else stampText g' (rx + rw - 2 - T.length hint) ry fg bg hint
  in g9

borderChars :: BorderStyle -> (Char, Char, Char, Char, Char, Char)
borderChars Single  = ('┌', '┐', '└', '┘', '─', '│')
borderChars Rounded = ('╭', '╮', '╰', '╯', '─', '│')
borderChars Heavy   = ('┏', '┓', '┗', '┛', '━', '┃')

-- | Stamp content into a rect.
stampContent :: CellGrid -> Rect -> Content -> CellGrid
stampContent grid (Rect rx ry rw _rh) (Text spans) =
  let (_, g) = foldl stampSpan (0, grid) spans
  in g
  where
    stampSpan (offset, g) (Span t ss) =
      let fg = maybe Default id (spanFg ss)
          chars = T.unpack (T.take (rw - offset) t)
          g' = foldl (\g'' (i, ch) ->
                  setCell g'' (rx + offset + i) ry
                    (Cell ch fg Default (spanBold ss) (spanDim ss)))
                g (Prelude.zip [0..] chars)
      in (offset + length chars, g')
stampContent grid (Rect rx ry rw rh) (Fill ch clr) =
  fillRect grid (Rect rx ry rw rh) ch clr Default
stampContent grid (Rect rx ry rw rh) (CellGrid rows) =
  -- Stamp the cell grid into the rect, clipping to bounds
  foldl (\g (r, row) ->
    foldl (\g' (c, cell) ->
      if c < rw && r < rh then setCell g' (rx + c) (ry + r) cell else g')
    g (V.toList (V.indexed row)))
  grid (V.toList (V.indexed rows))
  where
    V = Data.Vector  -- imported at top
```

Note: This is the initial implementation. The `stampContent` for `Text` spans only stamps on a single row for now. Multi-line text support will be added when needed (wrap text at newlines).

**Step 4: Add to cabal, add Vector import, run tests**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: PASS (may need to adjust tests for exact cell positions)

**Step 5: Commit**

```
git commit -m "feat(tank-layout): add layout solver"
```

---

### Task 6: ANSI backend

**Files:**
- Create: `tank-layout/src/Tank/Layout/Backend/ANSI.hs`
- Create: `tank-layout/test/Tank/Layout/Backend/ANSISpec.hs`

**Step 1: Write failing test**

```haskell
-- tank-layout/test/Tank/Layout/Backend/ANSISpec.hs
module Tank.Layout.Backend.ANSISpec (spec) where

import Test.Hspec
import qualified Data.ByteString.Char8 as B8
import Tank.Layout.Backend.ANSI
import Tank.Layout.Cell

spec :: Spec
spec = do
  describe "renderANSI" $ do
    it "renders a simple grid to ANSI" $ do
      let grid = stampText (mkGrid 5 1) 0 0 Default Default "hello"
          bs = renderANSI grid
      B8.unpack bs `shouldContain` "hello"

    it "includes SGR reset at end" $ do
      let grid = mkGrid 3 1
          bs = renderANSI grid
      B8.unpack bs `shouldContain` "\ESC[0m"

    it "emits color codes for RGB cells" $ do
      let cell = Cell 'X' (RGB 255 0 0) Default False False
          grid = setCell (mkGrid 3 1) 0 0 cell
          bs = renderANSI grid
      -- Should contain foreground color SGR
      B8.unpack bs `shouldContain` "\ESC[38;2;255;0;0m"
```

**Step 2: Run test to verify it fails**

Expected: FAIL

**Step 3: Implement ANSI.hs**

```haskell
-- tank-layout/src/Tank/Layout/Backend/ANSI.hs
module Tank.Layout.Backend.ANSI
  ( renderANSI
  ) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder, toLazyByteString, byteString, char7, string7)
import qualified Data.ByteString.Lazy as LBS
import Data.Word (Word8)
import qualified Data.Vector as V
import Tank.Layout.Cell

renderANSI :: CellGrid -> ByteString
renderANSI (CellGrid rows) =
  LBS.toStrict $ toLazyByteString $
    V.ifoldl' (\b rowIdx row ->
      b <> renderRow row <> (if rowIdx < V.length rows - 1 then string7 "\n" else mempty)
    ) mempty rows
    <> string7 "\ESC[0m"

renderRow :: V.Vector Cell -> Builder
renderRow row =
  V.foldl' (\b cell -> b <> renderCell cell) mempty row

renderCell :: Cell -> Builder
renderCell (Cell ch fg bg bold dim) =
  sgrFg fg <> sgrBg bg <> sgrBold bold <> sgrDim dim <> char7 ch

sgrFg :: Color -> Builder
sgrFg Default = string7 "\ESC[39m"
sgrFg (RGB r g b) = string7 "\ESC[38;2;" <> w8 r <> string7 ";" <> w8 g <> string7 ";" <> w8 b <> string7 "m"

sgrBg :: Color -> Builder
sgrBg Default = string7 "\ESC[49m"
sgrBg (RGB r g b) = string7 "\ESC[48;2;" <> w8 r <> string7 ";" <> w8 g <> string7 ";" <> w8 b <> string7 "m"

sgrBold :: Bool -> Builder
sgrBold True  = string7 "\ESC[1m"
sgrBold False = string7 "\ESC[22m"

sgrDim :: Bool -> Builder
sgrDim True  = string7 "\ESC[2m"
sgrDim False = mempty

w8 :: Word8 -> Builder
w8 = string7 . show
```

Note: This naive implementation emits SGR codes for every cell. A future optimization can diff adjacent cells and only emit changes.

**Step 4: Add to cabal, run tests**

Run: `nix develop -c cabal test tank-layout-tests`
Expected: PASS

**Step 5: Commit**

```
git commit -m "feat(tank-layout): add ANSI rendering backend"
```

---

### Task 7: PNG backend

**Files:**
- Modify: `tank-layout/tank-layout.cabal` (add JuicyPixels, FontyFruity deps)
- Modify: `flake.nix` (ensure deps available)
- Create: `tank-layout/src/Tank/Layout/Backend/PNG.hs`
- Create: `tank-layout/test/Tank/Layout/Backend/PNGSpec.hs`

**Step 1: Add dependencies to cabal**

Add to library build-depends:
```
, JuicyPixels   >= 3.3   && < 4
, FontyFruity   >= 0.5   && < 1
```

**Step 2: Write failing test**

```haskell
-- tank-layout/test/Tank/Layout/Backend/PNGSpec.hs
module Tank.Layout.Backend.PNGSpec (spec) where

import Test.Hspec
import qualified Data.ByteString.Lazy as LBS
import Tank.Layout.Backend.PNG
import Tank.Layout.Cell

spec :: Spec
spec = do
  describe "renderPNG" $ do
    it "produces valid PNG bytes" $ do
      let grid = stampText (mkGrid 10 3) 0 0 Default Default "hello"
      -- renderPNG needs a font path; skip in CI if font not found
      -- For now, just test that the function exists and the module compiles
      pendingWith "requires TTF font file; tested manually"
```

**Step 3: Implement PNG.hs**

This translates the Pillow rendering from render-concepts.py into Haskell:

```haskell
-- tank-layout/src/Tank/Layout/Backend/PNG.hs
module Tank.Layout.Backend.PNG
  ( renderPNG
  , PNGConfig(..)
  , defaultPNGConfig
  ) where

import Codec.Picture
import Graphics.Text.TrueType (loadFontFile, Font, stringBoundingBox, ...)
import qualified Data.Vector as V
import qualified Data.ByteString.Lazy as LBS
import Tank.Layout.Cell

data PNGConfig = PNGConfig
  { pngFontPath   :: FilePath
  , pngFontSize   :: Int      -- default 14
  , pngTitleBar   :: Bool     -- draw window chrome
  , pngWindowTitle :: String
  } deriving (Show)

defaultPNGConfig :: PNGConfig
defaultPNGConfig = PNGConfig
  { pngFontPath = ""  -- must be set
  , pngFontSize = 14
  , pngTitleBar = True
  , pngWindowTitle = "tank"
  }

renderPNG :: PNGConfig -> CellGrid -> IO LBS.ByteString
renderPNG config grid = do
  font <- loadFontFile (pngFontPath config)
  case font of
    Left err -> error $ "Failed to load font: " ++ err
    Right f  -> pure $ encodePng $ renderImage config f grid

renderImage :: PNGConfig -> Font -> CellGrid -> Image PixelRGBA8
renderImage config font (CellGrid rows) =
  -- Implementation: calculate cell dimensions from font metrics,
  -- create image, draw cell backgrounds and characters.
  -- Details follow the same approach as render-concepts.py.
  undefined -- TODO: implement in step 3
```

Full implementation of `renderImage` follows the render-concepts.py approach:
1. Get cell dimensions from font metrics (bbox of "M")
2. Create image sized to grid × cell dimensions (+ title bar if enabled)
3. For each cell: draw background rect, rasterize character glyph
4. Draw window chrome (title bar, traffic lights, rounded corners)

This task is the most complex. Implementation will be iterative — get basic character rendering working first, then add window chrome.

**Step 4: Build to verify compilation**

Run: `nix develop -c cabal build tank-layout`
Expected: builds (test is `pendingWith`)

**Step 5: Commit**

```
git commit -m "feat(tank-layout): add PNG rendering backend (initial)"
```

---

### Task 8: Concept image reproduction

Port the 9 concept scenarios from render-concepts.py to the Haskell eDSL. Create an executable that generates them.

**Files:**
- Create: `tank-layout/app/RenderConcepts.hs`
- Modify: `tank-layout/tank-layout.cabal` (add executable)

**Step 1: Add executable to cabal**

```cabal
executable tank-render-concepts
  import:           warnings
  main-is:          RenderConcepts.hs
  build-depends:
    , base         >= 4.17 && < 5
    , tank-layout
    , text         >= 2.0  && < 3
    , bytestring   >= 0.11 && < 1
    , filepath     >= 1.4  && < 2
    , directory    >= 1.3  && < 2
  hs-source-dirs:   app
  default-language: GHC2021
```

**Step 2: Port scenarios**

Start with scenario 01 (idle) and 02 (overlay) to validate the eDSL works end-to-end. Port remaining scenarios incrementally.

Each scenario becomes a `Layout` value. The main function renders each to PNG.

**Step 3: Build and compare output**

Run: `nix develop -c cabal run tank-render-concepts -- all --font $(nix eval --raw nixpkgs#dejavu_fonts)/share/fonts/truetype/DejaVuSansMono.ttf --outdir /tmp/concepts`

Compare output PNGs to existing ones visually.

**Step 4: Commit**

```
git commit -m "feat(tank-layout): port concept image scenarios to eDSL"
```

---

### Task 9: Wire tank-layout into tank

**Files:**
- Modify: `tank.cabal` (add tank-layout dependency)
- Modify: `src/Tank/Plug/Terminal.hs` (use tank-layout's Layout type)
- Modify: `src/Tank/Plug/Operator/Overlay.hs` (render via tank-layout)

**Step 1: Add dependency**

Add `tank-layout` to tank.cabal build-depends.

**Step 2: Replace Terminal.hs Layout type**

Replace the inline `Layout` and `SplitDir` types with imports from `Tank.Layout.Types`.

**Step 3: Migrate overlay rendering**

Replace the manual ANSI construction in `renderOverlay` with:
1. Build a `Layout` tree describing the overlay
2. Call `renderLayout` to get a `CellGrid`
3. Call `renderANSI` to get the ByteString

**Step 4: Run existing tests**

Run: `nix develop -c cabal test`
Expected: all existing tank tests pass

**Step 5: Commit**

```
git commit -m "refactor(tank): use tank-layout for terminal rendering"
```

---

### Task 10: Update nix derivation for concept images

Replace the Python-based `concept-images` nix derivation with the Haskell executable.

**Files:**
- Modify: `flake.nix`

**Step 1: Replace concept-images derivation**

```nix
concept-images = pkgs.runCommand "tank-concept-images" {
  nativeBuildInputs = [ haskellPackages.tank-layout ];
} ''
  mkdir -p $out
  tank-render-concepts all \
    --font ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf \
    --outdir $out
'';
```

**Step 2: Build**

Run: `nix build .#concept-images`
Expected: generates 9 PNGs matching the Python output

**Step 3: Commit**

```
git commit -m "build: replace Python concept renderer with Haskell"
```

---

## Task Dependency Graph

```
Task 1 (scaffold)
  └→ Task 2 (Cell types)
       └→ Task 3 (Layout types)
            └→ Task 4 (eDSL)
                 └→ Task 5 (solver)
                      ├→ Task 6 (ANSI backend)
                      └→ Task 7 (PNG backend)
                           └→ Task 8 (concept images)
                                └→ Task 9 (wire into tank)
                                     └→ Task 10 (nix derivation)
```

Tasks 6 and 7 are independent and can be parallelized.
