{-# LANGUAGE OverloadedStrings #-}
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
