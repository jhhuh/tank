{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.Backend.PNGSpec (spec) where

import Test.Hspec
import qualified Data.ByteString.Lazy as LBS
import Tank.Layout.Backend.PNG
import Tank.Layout.Cell

-- | A small 10x3 grid with some text stamped on it.
testGrid :: CellGrid
testGrid = stampText (mkGrid 10 3) 0 0 Default Default "hello"

spec :: Spec
spec = do
  describe "PNGConfig" $ do
    it "has sensible defaults" $ do
      pngFontSize defaultPNGConfig `shouldBe` 14
      pngTitleBar defaultPNGConfig `shouldBe` True
      pngWindowTitle defaultPNGConfig `shouldBe` "tank"
      pngFontFamily defaultPNGConfig `shouldBe` "DejaVu Sans Mono"

  describe "renderPNG" $ do
    it "produces non-empty output" $ do
      bs <- renderPNG defaultPNGConfig testGrid
      LBS.length bs `shouldSatisfy` (> 0)

    it "starts with valid PNG signature" $ do
      bs <- renderPNG defaultPNGConfig testGrid
      let hdr = LBS.take 4 bs
      hdr `shouldBe` LBS.pack [0x89, 0x50, 0x4E, 0x47]

    it "renders without title bar" $ do
      let cfg = defaultPNGConfig { pngTitleBar = False }
      bs <- renderPNG cfg testGrid
      LBS.length bs `shouldSatisfy` (> 0)
      let hdr = LBS.take 4 bs
      hdr `shouldBe` LBS.pack [0x89, 0x50, 0x4E, 0x47]

  describe "renderMultiPNG" $ do
    it "renders multiple frames as non-empty output" $ do
      let frames = [("frame1", testGrid), ("frame2", testGrid)]
      bs <- renderMultiPNG defaultPNGConfig frames
      LBS.length bs `shouldSatisfy` (> 0)

    it "multi-frame is larger than single frame" $ do
      single <- renderPNG defaultPNGConfig testGrid
      multi  <- renderMultiPNG defaultPNGConfig
                  [("frame1", testGrid), ("frame2", testGrid)]
      LBS.length multi `shouldSatisfy` (> LBS.length single)
