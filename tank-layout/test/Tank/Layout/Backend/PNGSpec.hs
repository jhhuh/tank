{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.Backend.PNGSpec (spec) where

import Test.Hspec
import Tank.Layout.Backend.PNG

spec :: Spec
spec = do
  describe "PNGConfig" $ do
    it "has sensible defaults" $ do
      pngFontSize defaultPNGConfig `shouldBe` 14
      pngTitleBar defaultPNGConfig `shouldBe` True
      pngWindowTitle defaultPNGConfig `shouldBe` "tank"
      pngFontFamily defaultPNGConfig `shouldBe` "DejaVu Sans Mono"
