{-# LANGUAGE OverloadedStrings #-}

module Tank.Layout.RenderSpec (spec) where

import Test.Hspec
import qualified Data.ByteString as BS
import Tank.Layout.Cell
import Tank.Layout.Types
import Tank.Layout.Render (renderLayout)
import Tank.Layout.Backend.ANSI (renderANSI, renderRowANSI)
import Tank.Terminal.Emulator (mkVTerm, vtFeed, vtGetCell)
import qualified Tank.Terminal.Emulator as Em
import qualified Data.Vector as V

-- | Feed a single rendered row through VTerm and inspect cells.
-- Uses a VTerm with extra rows to avoid scroll-on-wrap.
feedRow :: V.Vector Cell -> Em.VTerm
feedRow row =
  let ansi = renderRowANSI row
      w = V.length row
  in vtFeed ansi (mkVTerm w 2)

spec :: Spec
spec = do
  describe "Layout rendering (CellGrid)" $ do
    it "vertical split places content in correct halves" $ do
      let left  = Leaf (Fill 'L' Default)
          right = Leaf (Fill 'R' Default)
          layout = Split Horizontal 0.5 left right
          grid = renderLayout 20 3 layout
      cellChar (getCell grid 0 1) `shouldBe` 'L'
      cellChar (getCell grid 9 1) `shouldBe` 'L'
      cellChar (getCell grid 10 1) `shouldBe` 'R'
      cellChar (getCell grid 19 1) `shouldBe` 'R'

    it "horizontal split places content in top and bottom" $ do
      let top    = Leaf (Fill 'T' Default)
          bottom = Leaf (Fill 'B' Default)
          layout = Split Vertical 0.5 top bottom
          grid = renderLayout 10 10 layout
      cellChar (getCell grid 5 0) `shouldBe` 'T'
      cellChar (getCell grid 5 4) `shouldBe` 'T'
      cellChar (getCell grid 5 5) `shouldBe` 'B'
      cellChar (getCell grid 5 9) `shouldBe` 'B'

    it "styled border draws box-drawing characters" $ do
      let content = Leaf (Fill '.' Default)
          style = Style (Just (Border Single Default)) noEdges Nothing Nothing
          layout = Styled style content
          grid = renderLayout 10 5 layout
      cellChar (getCell grid 0 0) `shouldBe` '\x250C'
      cellChar (getCell grid 9 0) `shouldBe` '\x2510'
      cellChar (getCell grid 0 4) `shouldBe` '\x2514'
      cellChar (getCell grid 9 4) `shouldBe` '\x2518'
      cellChar (getCell grid 5 0) `shouldBe` '\x2500'
      cellChar (getCell grid 0 2) `shouldBe` '\x2502'
      cellChar (getCell grid 1 1) `shouldBe` '.'

    it "nested split produces correct sub-regions" $ do
      let topLeft  = Leaf (Fill 'A' Default)
          topRight = Leaf (Fill 'B' Default)
          topRow   = Split Horizontal 0.5 topLeft topRight
          bottom   = Leaf (Fill 'C' Default)
          layout   = Split Vertical 0.5 topRow bottom
          grid = renderLayout 20 10 layout
      cellChar (getCell grid 0 0) `shouldBe` 'A'
      cellChar (getCell grid 9 4) `shouldBe` 'A'
      cellChar (getCell grid 10 0) `shouldBe` 'B'
      cellChar (getCell grid 19 4) `shouldBe` 'B'
      cellChar (getCell grid 0 5) `shouldBe` 'C'
      cellChar (getCell grid 19 9) `shouldBe` 'C'

    it "CellContent stamps existing grid into layout" $ do
      let src = mkGrid 3 2
          src' = setCell src 0 0 (Cell 'X' (RGB 255 0 0) Default True False False False False False)
          layout = Leaf (CellContent src')
          grid = renderLayout 10 5 layout
      cellChar (getCell grid 0 0) `shouldBe` 'X'
      cellFg (getCell grid 0 0) `shouldBe` RGB 255 0 0
      cellBold (getCell grid 0 0) `shouldBe` True

    it "text spans preserve bold and dim" $ do
      let sp = Span "Hi" (SpanStyle (Just (RGB 0 255 0)) True True)
          layout = Leaf (Text [sp])
          grid = renderLayout 10 3 layout
      cellChar (getCell grid 0 0) `shouldBe` 'H'
      cellFg (getCell grid 0 0) `shouldBe` RGB 0 255 0
      cellBold (getCell grid 0 0) `shouldBe` True
      cellDim (getCell grid 0 0) `shouldBe` True

  describe "ANSI round-trip (single row)" $ do
    -- Uses renderRowANSI + VTerm to verify attributes survive serialization.
    -- VTerm tracks: bold, dim, underline, inverse. NOT italic or blink.

    it "preserves bold" $ do
      let row = V.singleton (Cell 'B' Default Default True False False False False False)
          vt = feedRow row
      Em.cChar (vtGetCell 0 0 vt) `shouldBe` 'B'
      Em.hasFlag Em.attrBold (Em.cAttrs (vtGetCell 0 0 vt)) `shouldBe` True

    it "preserves dim" $ do
      let row = V.singleton (Cell 'D' Default Default False True False False False False)
          vt = feedRow row
      Em.cChar (vtGetCell 0 0 vt) `shouldBe` 'D'
      Em.hasFlag Em.attrDim (Em.cAttrs (vtGetCell 0 0 vt)) `shouldBe` True

    it "preserves underline" $ do
      let row = V.singleton (Cell 'U' Default Default False False True False False False)
          vt = feedRow row
      Em.cChar (vtGetCell 0 0 vt) `shouldBe` 'U'
      Em.hasFlag Em.attrUnderline (Em.cAttrs (vtGetCell 0 0 vt)) `shouldBe` True

    it "preserves inverse" $ do
      let row = V.singleton (Cell 'I' Default Default False False False False True False)
          vt = feedRow row
      Em.cChar (vtGetCell 0 0 vt) `shouldBe` 'I'
      Em.hasFlag Em.attrInverse (Em.cAttrs (vtGetCell 0 0 vt)) `shouldBe` True

    it "preserves bold+dim combination" $ do
      let row = V.singleton (Cell 'X' Default Default True True False False False False)
          vt = feedRow row
      Em.cChar (vtGetCell 0 0 vt) `shouldBe` 'X'
      Em.hasFlag Em.attrBold (Em.cAttrs (vtGetCell 0 0 vt)) `shouldBe` True
      Em.hasFlag Em.attrDim (Em.cAttrs (vtGetCell 0 0 vt)) `shouldBe` True

    it "preserves all four trackable attributes" $ do
      let row = V.singleton (Cell 'A' Default Default True True True False True False)
          vt = feedRow row
      Em.cChar (vtGetCell 0 0 vt) `shouldBe` 'A'
      Em.hasFlag Em.attrBold (Em.cAttrs (vtGetCell 0 0 vt)) `shouldBe` True
      Em.hasFlag Em.attrDim (Em.cAttrs (vtGetCell 0 0 vt)) `shouldBe` True
      Em.hasFlag Em.attrUnderline (Em.cAttrs (vtGetCell 0 0 vt)) `shouldBe` True
      Em.hasFlag Em.attrInverse (Em.cAttrs (vtGetCell 0 0 vt)) `shouldBe` True

  describe "ANSI output verification" $ do
    it "emits RGB foreground SGR sequence" $ do
      let src = mkGrid 3 1
          src' = setCell src 0 0 (Cell 'C' (RGB 255 0 0) Default False False False False False False)
          ansi = renderANSI (CellGrid (gridRows src'))
      BS.isInfixOf "\ESC[38;2;255;0;0m" ansi `shouldBe` True

    it "emits RGB background SGR sequence" $ do
      let src = mkGrid 3 1
          src' = setCell src 0 0 (Cell 'C' Default (RGB 0 0 255) False False False False False False)
          ansi = renderANSI (CellGrid (gridRows src'))
      BS.isInfixOf "\ESC[48;2;0;0;255m" ansi `shouldBe` True

    it "delta-encodes: bold SGR emitted only once for consecutive bold cells" $ do
      let cell = Cell 'X' Default Default True False False False False False
          row = V.fromList [cell, cell, cell]
          ansi = renderRowANSI row
          boldSeq = "\ESC[1m" :: BS.ByteString
          countOccurrences needle haystack =
            let len = BS.length needle
                go acc bs
                  | BS.length bs < len = acc
                  | BS.isPrefixOf needle bs = go (acc + 1) (BS.drop 1 bs)
                  | otherwise = go acc (BS.drop 1 bs)
            in go (0 :: Int) haystack
      countOccurrences boldSeq ansi `shouldBe` 1

    it "emits trailing reset" $ do
      let row = V.singleton (Cell 'Z' Default Default False False False False False False)
          ansi = renderRowANSI row
      -- Should end with \ESC[0m
      BS.isSuffixOf "\ESC[0m" ansi `shouldBe` True
