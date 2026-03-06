{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.RenderSpec (spec) where

import Test.Hspec
import Tank.Layout.Render
import Tank.Layout.DSL
import Tank.Layout.Types
  ( Layout(..), plainSpan
  , Style(..), Anchor(..), Edges(..)
  , defaultStyle
  )
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
      cellChar (getCell grid 0 0) `shouldBe` '\x250C'  -- '┌'
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

  describe "splitRect negative ratio" $ do
    it "vertical split with ratio=-1 gives second child 1 row" $ do
      -- withStatusBar uses Split Vertical (-1)
      -- On a 20x5 grid: main gets rows 0-3 (height 4), status gets row 4 (height 1)
      let layout = withStatusBar (fill '#') [plainSpan "bar"]
          grid = renderLayout 20 5 layout
      -- Row 3 should still be main content (fill '#')
      cellChar (getCell grid 0 3) `shouldBe` '#'
      -- Row 4 is the status bar
      map (\c -> cellChar (getCell grid c 4)) [0..2] `shouldBe` "bar"

    it "horizontal split with ratio=-1 gives second child 1 column" $ do
      -- Split Horizontal (-1) on 10-wide: first gets 9 cols, second gets 1 col
      let layout = hsplit (-1) (fill 'A') (fill 'B')
          grid = renderLayout 10 3 layout
      -- Column 8 should be 'A' (last col of first child)
      cellChar (getCell grid 8 0) `shouldBe` 'A'
      -- Column 9 should be 'B' (the 1-col second child)
      cellChar (getCell grid 9 0) `shouldBe` 'B'

  describe "vertical split" $ do
    it "vsplit 0.5 divides rows evenly" $ do
      -- 20x10 grid, vsplit 0.5: h1 = round(10*0.5) = 5
      -- Top: rows 0-4, Bottom: rows 5-9
      let layout = vsplit 0.5 (fill 'T') (fill 'B')
          grid = renderLayout 20 10 layout
      cellChar (getCell grid 0 4) `shouldBe` 'T'  -- last row of top
      cellChar (getCell grid 0 5) `shouldBe` 'B'  -- first row of bottom

  describe "zero-size rect" $ do
    it "ratio=1.0 gives all space to first child, second gets nothing" $ do
      -- hsplit 1.0: w1 = round(20*1.0) = 20, second child gets 0 width
      let layout = hsplit 1.0 (fill 'X') (fill 'Y')
          grid = renderLayout 20 3 layout
      -- All columns should be 'X'
      cellChar (getCell grid 0 0) `shouldBe` 'X'
      cellChar (getCell grid 19 0) `shouldBe` 'X'
      -- No 'Y' anywhere — second child rect has width 0, resolve returns grid unchanged
      map (\c -> cellChar (getCell grid c 0)) [0..19] `shouldBe` replicate 20 'X'

  describe "multiline text" $ do
    it "spans with newline render on multiple rows" $ do
      let layout = spans [plainSpan "ab\ncd"]
          grid = renderLayout 10 5 layout
      -- First line: "ab" at row 0
      map (\c -> cellChar (getCell grid c 0)) [0..1] `shouldBe` "ab"
      -- Second line: "cd" at row 1
      map (\c -> cellChar (getCell grid c 1)) [0..1] `shouldBe` "cd"

    it "newline resets column to 0" $ do
      let layout = spans [plainSpan "x\ny"]
          grid = renderLayout 10 5 layout
      cellChar (getCell grid 0 0) `shouldBe` 'x'
      cellChar (getCell grid 0 1) `shouldBe` 'y'

  describe "text clipping" $ do
    it "text exceeding rect width gets clipped" $ do
      -- Render "abcdef" in a 4-wide grid
      let layout = text "abcdef"
          grid = renderLayout 4 1 layout
      -- First 4 chars should appear
      map (\c -> cellChar (getCell grid c 0)) [0..3] `shouldBe` "abcd"
      -- Columns beyond width are not modified (remain default space)
      -- (grid is only 4 wide, getCell returns defaultCell for out-of-bounds)

    it "clipped text does not wrap to next row" $ do
      let layout = text "abcdef"
          grid = renderLayout 4 3 layout
      -- Row 0 has first 4 chars
      map (\c -> cellChar (getCell grid c 0)) [0..3] `shouldBe` "abcd"
      -- Row 1 should be empty (clipped chars don't wrap)
      cellChar (getCell grid 0 1) `shouldBe` ' '

  describe "small border" $ do
    it "bordered on a 2x2 rect draws only corners" $ do
      -- 2x2 border: only corners, no horizontal/vertical edges
      -- ranges [rx+1..rx+rw-2] = [1..0] = empty
      let layout = bordered (text "z")
          grid = renderLayout 2 2 layout
      -- Four corners of the single border
      cellChar (getCell grid 0 0) `shouldBe` '\x250C'  -- ┌
      cellChar (getCell grid 1 0) `shouldBe` '\x2510'  -- ┐
      cellChar (getCell grid 0 1) `shouldBe` '\x2514'  -- └
      cellChar (getCell grid 1 1) `shouldBe` '\x2518'  -- ┘

  describe "styled background" $ do
    it "sBg fills all cells with that background color" $ do
      let green = RGB 0 255 0
          layout = Styled defaultStyle { sBg = Just green } (text "hi")
          grid = renderLayout 5 3 layout
      -- Content cells preserve the background
      cellBg (getCell grid 0 0) `shouldBe` green  -- 'h' cell
      cellBg (getCell grid 1 0) `shouldBe` green  -- 'i' cell
      -- Non-content cells also have the background (filled before content)
      cellBg (getCell grid 4 2) `shouldBe` green

  describe "padding" $ do
    it "sPadding insets content" $ do
      -- Padding 1 on all sides, no border
      -- On 10x5: innerRect = (1,1,8,3)
      let layout = Styled defaultStyle { sPadding = Edges 1 1 1 1 } (text "AB")
          grid = renderLayout 10 5 layout
      -- (0,0) should be space (padding area)
      cellChar (getCell grid 0 0) `shouldBe` ' '
      -- Content starts at (1,1) due to padding
      cellChar (getCell grid 1 1) `shouldBe` 'A'
      cellChar (getCell grid 2 1) `shouldBe` 'B'

  describe "bottom-pinned overlay" $ do
    it "overlay appears at bottom of rect" $ do
      -- bottomPinned places overlay at bottom, centered horizontally
      -- Base: fill '.', Overlay: text "bot" (3 chars wide, 1 row tall)
      -- On 20x10: oy = 10 - 1 = 9, ox = (20 - 3) / 2 = 8
      -- Overlay at (8, 9)
      let layout = bottomPinned (fill '.') (text "bot")
          grid = renderLayout 20 10 layout
      -- Base fill at top
      cellChar (getCell grid 0 0) `shouldBe` '.'
      -- Overlay text at bottom row, horizontally centered
      map (\c -> cellChar (getCell grid c 9)) [8..10] `shouldBe` "bot"

  describe "absolute-positioned overlay" $ do
    it "overlay at specific coordinates" $ do
      -- Absolute 2 1 places overlay at offset (2,1) from parent rect origin
      -- text "XY" is 2 wide, 1 tall
      -- On 10x5: overlay at (2, 1)
      let layout = overlay (Absolute 2 1) (fill '.') (text "XY")
          grid = renderLayout 10 5 layout
      -- Base fill everywhere
      cellChar (getCell grid 0 0) `shouldBe` '.'
      -- Overlay overwrites at (2,1)
      cellChar (getCell grid 2 1) `shouldBe` 'X'
      cellChar (getCell grid 3 1) `shouldBe` 'Y'
      -- Adjacent cells still have base fill
      cellChar (getCell grid 1 1) `shouldBe` '.'
      cellChar (getCell grid 4 1) `shouldBe` '.'
