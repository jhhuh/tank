{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.Backend.PNGSpec (spec) where

import Test.Hspec
import Tank.Layout.Backend.PNG
import Tank.Layout.Cell

spec :: Spec
spec = do
  describe "renderPNG" $ do
    it "produces valid PNG bytes" $ do
      let _grid = stampText (mkGrid 10 3) 0 0 Default Default "hello"
      -- renderPNG needs a font path; skip in CI if font not found
      -- For now, just test that the function exists and the module compiles
      pendingWith "requires TTF font file; tested manually"

  describe "PNGConfig" $ do
    it "has sensible defaults" $ do
      pngFontSize defaultPNGConfig `shouldBe` 14
      pngTitleBar defaultPNGConfig `shouldBe` True
      pngWindowTitle defaultPNGConfig `shouldBe` "tank"
