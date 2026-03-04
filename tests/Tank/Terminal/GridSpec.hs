module Tank.Terminal.GridSpec (spec) where

import Test.Hspec
import Data.UUID (nil)
import Tank.Core.CRDT (ReplicaId(..))
import Tank.Terminal.Grid

rid :: ReplicaId
rid = ReplicaId nil

spec :: Spec
spec = do
  describe "Grid" $ do
    it "creates an empty grid" $ do
      let g = mkGrid rid 80 24 200 100
      gridWidth g `shouldBe` 80
      gridHeight g `shouldBe` 24
      visibleRange g `shouldBe` (0, 23)

    it "writes and reads a cell" $ do
      let g = mkGrid rid 80 24 200 100
          g' = writeCell rid 1 0 5 10 (GridCell 'A' DefaultColor DefaultColor defaultAttrs) g
      readCell g' 5 10 `shouldBe` Just (GridCell 'A' DefaultColor DefaultColor defaultAttrs)

    it "returns Nothing for unwritten cells" $ do
      let g = mkGrid rid 80 24 200 100
      readCell g 0 0 `shouldBe` Nothing

    it "advances viewport" $ do
      let g = mkGrid rid 80 24 200 100
          g' = advanceViewport rid 1 10 g
      visibleRange g' `shouldBe` (10, 33)

    it "clears screen with epoch" $ do
      let g = mkGrid rid 80 24 200 100
          g' = writeCell rid 1 0 5 10 (GridCell 'A' DefaultColor DefaultColor defaultAttrs) g
          g'' = clearScreen rid 2 g'
      -- Cell from epoch 0 should be stale after clear (epoch 1)
      readCell g'' 5 10 `shouldBe` Nothing

    it "preserves cells from current epoch after clear" $ do
      let g = mkGrid rid 80 24 200 100
          g' = clearScreen rid 1 g  -- epoch becomes 1
          g'' = writeCell rid 2 1 5 10 (GridCell 'B' DefaultColor DefaultColor defaultAttrs) g'
      readCell g'' 5 10 `shouldBe` Just (GridCell 'B' DefaultColor DefaultColor defaultAttrs)

    it "handles out-of-order: content before clear" $ do
      -- Content with epoch=1 arrives before the clear that sets epoch=1
      let g = mkGrid rid 80 24 200 100
          -- Write cell with epoch 1 (future content)
          g' = writeCell rid 2 1 5 10 (GridCell 'X' DefaultColor DefaultColor defaultAttrs) g
          -- Clear arrives later, setting epoch to 1
          g'' = clearScreen rid 1 g'
      -- Cell with epoch 1 should survive clear to epoch 1
      readCell g'' 5 10 `shouldBe` Just (GridCell 'X' DefaultColor DefaultColor defaultAttrs)
