{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.Render
  ( renderLayout
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Tank.Layout.Cell
import Tank.Layout.Types

-- | Render a layout tree into a cell grid of the given dimensions.
renderLayout :: Int -> Int -> Layout -> CellGrid
renderLayout w h layout = resolve (mkGrid w h) (Rect 0 0 w h) layout

-- | Recursively resolve a layout node into the grid within the given rect.
resolve :: CellGrid -> Rect -> Layout -> CellGrid
resolve grid (Rect _ _ w h) _
  | w <= 0 || h <= 0 = grid
resolve grid rect (Leaf content) =
  stampContent grid rect content
resolve grid rect (Split dir ratio l r) =
  let (r1, r2) = splitRect dir ratio rect
  in resolve (resolve grid r1 l) r2 r
resolve grid rect (Layers base overlays) =
  foldl (\g (anchor, lay) -> resolve g (anchorRect anchor rect lay) lay)
        (resolve grid rect base)
        overlays
resolve grid rect (Styled style child) =
  let (innerRect, grid') = applyStyle grid rect style
  in resolve grid' innerRect child

-- | Split a rect into two sub-rects along the given direction.
-- A negative ratio is a sentinel: -1 means the second child gets 1 row/col.
splitRect :: Dir -> Float -> Rect -> (Rect, Rect)
splitRect Horizontal ratio (Rect x y w h)
  | ratio < 0 =
      let w1 = w - 1
      in (Rect x y w1 h, Rect (x + w1) y 1 h)
  | otherwise =
      let w1 = round (fromIntegral w * ratio)
      in (Rect x y w1 h, Rect (x + w1) y (w - w1) h)
splitRect Vertical ratio (Rect x y w h)
  | ratio < 0 =
      let h1 = h - 1
      in (Rect x y w h1, Rect x (y + h1) w 1)
  | otherwise =
      let h1 = round (fromIntegral h * ratio)
      in (Rect x y w h1, Rect x (y + h1) w (h - h1))

-- | Compute the rect for an overlay given its anchor and parent rect.
anchorRect :: Anchor -> Rect -> Layout -> Rect
anchorRect (Absolute ox oy) (Rect px py _pw _ph) _lay =
  let (cw, ch) = layoutSize _lay _pw _ph
  in Rect (px + ox) (py + oy) cw ch
anchorRect Center (Rect px py pw ph) lay =
  let (cw, ch) = layoutSize lay pw ph
      ox = (pw - cw) `div` 2
      oy = (ph - ch) `div` 2
  in Rect (px + ox) (py + oy) cw ch
anchorRect Bottom (Rect px py pw ph) lay =
  let (cw, ch) = layoutSize lay pw ph
      ox = (pw - cw) `div` 2
      oy = ph - ch
  in Rect (px + ox) (py + oy) cw ch

-- | Estimate the size of a layout for overlay positioning.
-- For overlays we need a size hint. This uses a simple heuristic:
-- styled nodes add border/padding, leaves measure their content.
layoutSize :: Layout -> Int -> Int -> (Int, Int)
layoutSize (Leaf (Text spans_)) _maxW _maxH =
  let lines_ = spansToLines spans_
      h = max 1 (length lines_)
      w = maximum (0 : map T.length lines_)
  in (w, h)
layoutSize (Leaf (Fill _ _)) maxW maxH = (maxW, maxH)
layoutSize (Leaf (CellContent g)) _maxW _maxH = (gridWidth g, gridHeight g)
layoutSize (Styled style child) maxW maxH =
  let (cw, ch) = layoutSize child maxW maxH
      (top, right, bottom, left) = styleInsets style
  in (cw + left + right, ch + top + bottom)
layoutSize (Split _ _ l _r) maxW maxH = layoutSize l maxW maxH
layoutSize (Layers base _) maxW maxH = layoutSize base maxW maxH

-- | Calculate the insets (border + padding) from a style.
styleInsets :: Style -> (Int, Int, Int, Int)  -- (top, right, bottom, left)
styleInsets (Style border (Edges pt pr pb pl) _ _) =
  let bt = if hasBorder then 1 else 0
  in (bt + pt, bt + pr, bt + pb, bt + pl)
  where
    hasBorder = case border of
      Just _  -> True
      Nothing -> False

-- | Apply style to the grid: draw border, fill background, compute inner rect.
applyStyle :: CellGrid -> Rect -> Style -> (Rect, CellGrid)
applyStyle grid rect@(Rect x y w h) (Style border (Edges pt pr pb pl) title_ bg) =
  let -- Fill background first
      grid1 = case bg of
        Just c  -> fillRect grid rect ' ' Default c
        Nothing -> grid
      -- Draw border
      (bInset, grid2) = case border of
        Just (Border bs bc) ->
          (1, drawBorder grid1 rect bs bc title_)
        Nothing -> (0, grid1)
      -- Compute inner rect
      innerX = x + bInset + pl
      innerY = y + bInset + pt
      innerW = w - 2 * bInset - pl - pr
      innerH = h - 2 * bInset - pt - pb
  in (Rect innerX innerY (max 0 innerW) (max 0 innerH), grid2)

-- | Fill a rect with a character and colors.
fillRect :: CellGrid -> Rect -> Char -> Color -> Color -> CellGrid
fillRect grid (Rect rx ry rw rh) ch fg bg =
  foldl (\g (col, row) -> setCell g col row (Cell ch fg bg False False))
        grid
        [(c, r) | r <- [ry .. ry + rh - 1], c <- [rx .. rx + rw - 1]]

-- | Draw a border around the given rect.
drawBorder :: CellGrid -> Rect -> BorderStyle -> Color -> Maybe (Text, Text) -> CellGrid
drawBorder grid (Rect rx ry rw rh) bs bc title_
  | rw < 2 || rh < 2 = grid
  | otherwise =
      let (tl, tr, bl, br, horiz, vert) = borderChars bs
          mkC ch = Cell ch bc Default False False
          -- Corners
          g1 = setCell grid  rx          ry          (mkC tl)
          g2 = setCell g1    (rx+rw-1)   ry          (mkC tr)
          g3 = setCell g2    rx          (ry+rh-1)   (mkC bl)
          g4 = setCell g3    (rx+rw-1)   (ry+rh-1)   (mkC br)
          -- Top & bottom edges
          g5 = foldl (\g c -> setCell g c ry (mkC horiz))
                     g4 [rx+1 .. rx+rw-2]
          g6 = foldl (\g c -> setCell g c (ry+rh-1) (mkC horiz))
                     g5 [rx+1 .. rx+rw-2]
          -- Left & right edges
          g7 = foldl (\g r -> setCell g rx r (mkC vert))
                     g6 [ry+1 .. ry+rh-2]
          g8 = foldl (\g r -> setCell g (rx+rw-1) r (mkC vert))
                     g7 [ry+1 .. ry+rh-2]
          -- Title on top border (left title)
          g9 = case title_ of
            Just (t, _) | not (T.null t) ->
              stampText g8 (rx + 2) ry bc Default t
            _ -> g8
          -- Right hint title on top border
          g10 = case title_ of
            Just (_, hint) | not (T.null hint) ->
              let hintLen = T.length hint
                  hintX = rx + rw - 2 - hintLen
              in stampText g9 hintX ry bc Default hint
            _ -> g9
      in g10

-- | Get the box-drawing characters for a border style.
-- Returns: (top-left, top-right, bottom-left, bottom-right, horizontal, vertical)
borderChars :: BorderStyle -> (Char, Char, Char, Char, Char, Char)
borderChars Single  = ('\x250C', '\x2510', '\x2514', '\x2518', '\x2500', '\x2502')  -- ┌┐└┘─│
borderChars Rounded = ('\x256D', '\x256E', '\x2570', '\x256F', '\x2500', '\x2502')  -- ╭╮╰╯─│
borderChars Heavy   = ('\x250F', '\x2513', '\x2517', '\x251B', '\x2501', '\x2503')  -- ┏┓┗┛━┃

-- | Stamp content into a rect.
stampContent :: CellGrid -> Rect -> Content -> CellGrid
stampContent grid (Rect rx ry rw rh) (Text spans_) =
  stampSpans grid rx ry rw rh spans_
stampContent grid (Rect rx ry rw rh) (Fill ch fg) =
  fillRect grid (Rect rx ry rw rh) ch fg Default
stampContent grid (Rect rx ry rw rh) (CellContent src) =
  let sw = gridWidth src
      sh = gridHeight src
      copyW = min rw sw
      copyH = min rh sh
  in foldl (\g (c, r) -> setCell g (rx + c) (ry + r) (getCell src c r))
           grid
           [(c, r) | r <- [0 .. copyH - 1], c <- [0 .. copyW - 1]]

-- | Stamp styled spans into the grid, preserving per-span colors.
-- Handles newlines within span text for multi-line content.
stampSpans :: CellGrid -> Int -> Int -> Int -> Int -> [Span] -> CellGrid
stampSpans grid startX startY maxW maxH spans_ =
  let -- Flatten spans into styled characters, tracking line breaks
      go g _col _row [] = g
      go g _col _row _ | _row >= maxH = g
      go g col row (Span txt style : rest) =
        let fg = case spanFg style of
              Just c  -> c
              Nothing -> Default
            bold = spanBold style
            dim_ = spanDim style
            (g', col', row') = T.foldl' (stepChar fg bold dim_) (g, col, row) txt
        in go g' col' row' rest
      stepChar fg bold dim_ (g, col, row) ch
        | row >= maxH = (g, col, row)
        | ch == '\n'  = (g, 0, row + 1)
        | col >= maxW = (g, col + 1, row)  -- clip but keep scanning
        | otherwise   =
            ( setCell g (startX + col) (startY + row)
                (Cell ch fg Default bold dim_)
            , col + 1, row)
  in go grid 0 0 spans_

-- | Convert a list of spans into lines, splitting on newlines.
-- Used for size estimation in layoutSize.
spansToLines :: [Span] -> [Text]
spansToLines spans_ =
  let fullText = T.concat [t | Span t _ <- spans_]
  in T.splitOn "\n" fullText
