module Tank.Terminal.CellAdapterSpec (spec) where

import Test.Hspec
import Data.UUID (nil)
import Tank.Core.CRDT (ReplicaId(..))
import Tank.Terminal.Grid (GridCell(..), Color(..), CellAttrs(..), defaultAttrs, defaultCell)
import qualified Tank.Terminal.Grid as VT
import qualified Tank.Layout.Cell as LC
import Tank.Terminal.CellAdapter

rid :: ReplicaId
rid = ReplicaId nil

spec :: Spec
spec = do
  describe "convertColor" $ do
    it "converts DefaultColor to Default" $
      convertColor DefaultColor `shouldBe` LC.Default

    it "converts ColorRGB to RGB" $
      convertColor (ColorRGB 255 0 0) `shouldBe` LC.RGB 255 0 0

    it "converts Color256 0 (black) to RGB 0 0 0" $
      convertColor (Color256 0) `shouldBe` LC.RGB 0 0 0

    it "converts Color256 9 (bright red) to RGB 255 85 85" $
      convertColor (Color256 9) `shouldBe` LC.RGB 255 85 85

    it "converts Color256 196 (6x6x6 cube red) to RGB" $ do
      -- 196 - 16 = 180; r = 180/36 = 5 -> 255, g = (180%36)/6 = 0, b = 0
      convertColor (Color256 196) `shouldBe` LC.RGB 255 0 0

    it "converts Color256 240 (grayscale) to gray" $ do
      -- 240 - 232 = 8; value = 8 + 8*10 = 88
      convertColor (Color256 240) `shouldBe` LC.RGB 88 88 88

    it "converts out-of-range Color256 to Default" $ do
      convertColor (Color256 (-1)) `shouldBe` LC.Default
      convertColor (Color256 256) `shouldBe` LC.Default

  describe "convertGridCell" $ do
    it "preserves character, colors, and bold" $ do
      let gc = GridCell
            { gcCodepoint = 'X'
            , gcFg = ColorRGB 10 20 30
            , gcBg = DefaultColor
            , gcAttrs = CellAttrs True False False False False False
            }
          result = convertGridCell gc
      LC.cellChar result `shouldBe` 'X'
      LC.cellFg result `shouldBe` LC.RGB 10 20 30
      LC.cellBg result `shouldBe` LC.Default
      LC.cellBold result `shouldBe` True
      LC.cellDim result `shouldBe` False

    it "converts default GridCell to layout defaultCell" $ do
      convertGridCell defaultCell `shouldBe` LC.defaultCell

  describe "gridToCellGrid" $ do
    it "converts a grid with written cells" $ do
      let vtGrid = VT.mkGrid rid 4 3 0 0
          cell1 = GridCell 'A' (ColorRGB 255 0 0) DefaultColor defaultAttrs
          cell2 = GridCell 'B' DefaultColor (Color256 4) (CellAttrs True False False False False False)
          -- Write cell1 at line 0 col 0, cell2 at line 1 col 2
          vtGrid' = VT.writeCell rid 1 0 0 0 cell1
                  $ VT.writeCell rid 2 0 1 2 cell2
                  $ vtGrid
          result = gridToCellGrid vtGrid'
      -- Grid dimensions
      LC.gridHeight result `shouldBe` 3
      LC.gridWidth result `shouldBe` 4
      -- cell1 at (row=0, col=0)
      LC.getCell result 0 0 `shouldBe` convertGridCell cell1
      -- Unwritten cell at (row=0, col=1) -> defaultCell
      LC.getCell result 1 0 `shouldBe` LC.defaultCell
      -- cell2 at (row=1, col=2)
      LC.getCell result 2 1 `shouldBe` convertGridCell cell2

    it "respects viewport offset" $ do
      let vtGrid = VT.mkGrid rid 3 2 0 0
          -- Advance viewport to line 5
          vtGrid' = VT.advanceViewport rid 1 5 vtGrid
          cell = GridCell 'Z' DefaultColor DefaultColor defaultAttrs
          -- Write at absolute line 6, col 1 (should be row 1 in viewport)
          vtGrid'' = VT.writeCell rid 2 0 6 1 cell vtGrid'
          result = gridToCellGrid vtGrid''
      LC.getCell result 1 1 `shouldBe` convertGridCell cell
      -- Row 0 col 0 is unwritten
      LC.getCell result 0 0 `shouldBe` LC.defaultCell
