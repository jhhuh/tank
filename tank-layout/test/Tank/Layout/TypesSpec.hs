{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.TypesSpec (spec) where

import Test.Hspec
import Tank.Layout.Types
import Tank.Layout.Cell (Color(..))

spec :: Spec
spec = do
  describe "Layout constructors" $ do
    it "can create a leaf" $ do
      let l = Leaf (Text [plainSpan "hello"])
      case l of
        Leaf (Text spans) -> length spans `shouldBe` 1
        _ -> expectationFailure "expected Leaf"

    it "can create a split" $ do
      let l = Split Horizontal 0.5 (Leaf (Fill ' ' Default)) (Leaf (Fill ' ' Default))
      case l of
        Split Horizontal r _ _ -> r `shouldBe` 0.5
        _ -> expectationFailure "expected Split"

    it "can create layers with overlays" $ do
      let base = Leaf (Fill ' ' Default)
          over = Leaf (Text [plainSpan "popup"])
          l = Layers base [(Center, over)]
      case l of
        Layers _ overlays -> length overlays `shouldBe` 1
        _ -> expectationFailure "expected Layers"
