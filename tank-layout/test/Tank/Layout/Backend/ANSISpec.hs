{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.Backend.ANSISpec (spec) where

import Test.Hspec
import qualified Data.ByteString.Char8 as B8
import Tank.Layout.Backend.ANSI
import Tank.Layout.Cell

-- | Strip ANSI escape sequences, keeping only printable content.
stripAnsi :: String -> String
stripAnsi [] = []
stripAnsi ('\ESC':'[':rest) = stripAnsi (drop 1 $ dropWhile (/= 'm') rest)
stripAnsi (c:cs) = c : stripAnsi cs

spec :: Spec
spec = do
  describe "renderANSI" $ do
    it "renders a simple grid to ANSI" $ do
      let grid = stampText (mkGrid 5 1) 0 0 Default Default "hello"
          bs = renderANSI grid
      stripAnsi (B8.unpack bs) `shouldBe` "hello"

    it "includes SGR reset at end" $ do
      let grid = mkGrid 3 1
          bs = renderANSI grid
      B8.unpack bs `shouldContain` "\ESC[0m"

    it "emits color codes for RGB cells" $ do
      let cell = Cell 'X' (RGB 255 0 0) Default False False
          grid = setCell (mkGrid 3 1) 0 0 cell
          bs = renderANSI grid
      -- Should contain foreground color SGR
      B8.unpack bs `shouldContain` "\ESC[38;2;255;0;0m"
