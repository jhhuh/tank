{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.RenderSpec (spec) where

import Test.Hspec
import Tank.Layout.Render
import Tank.Layout.DSL
import Tank.Layout.Types (plainSpan)
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
