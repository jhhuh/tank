{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.DSLSpec (spec) where

import Test.Hspec
import Tank.Layout.DSL
import Tank.Layout.Types

spec :: Spec
spec = do
  describe "split combinators" $ do
    it "hsplit creates horizontal split" $ do
      let l = hsplit 0.5 (text "left") (text "right")
      case l of
        Split Horizontal 0.5 _ _ -> pure ()
        _ -> expectationFailure "expected horizontal split"

    it "hsplit2 creates even split" $ do
      let l = hsplit2 (text "a") (text "b")
      case l of
        Split Horizontal 0.5 _ _ -> pure ()
        _ -> expectationFailure "expected 0.5 split"

  describe "decoration combinators" $ do
    it "bordered wraps with single border" $ do
      let l = bordered (text "inner")
      case l of
        Styled s _ -> sBorder s `shouldNotBe` Nothing
        _ -> expectationFailure "expected Styled"

    it "titled adds border + title" $ do
      let l = titled "my box" (text "inner")
      case l of
        Styled s _ -> sTitle s `shouldBe` Just ("my box", "")
        _ -> expectationFailure "expected Styled"

  describe "overlay combinators" $ do
    it "centered creates center-anchored overlay" $ do
      let l = centered (text "base") (text "popup")
      case l of
        Layers _ [(Center, _)] -> pure ()
        _ -> expectationFailure "expected centered overlay"

  describe "withStatusBar" $ do
    it "creates vsplit with 1-row bar at bottom" $ do
      let l = withStatusBar (text "main") [plainSpan "status"]
      case l of
        Split Vertical _ _ (Leaf (Text _)) -> pure ()
        _ -> expectationFailure "expected vsplit with text bar"
