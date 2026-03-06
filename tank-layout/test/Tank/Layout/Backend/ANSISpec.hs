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

    it "does not emit redundant SGR for identical adjacent cells" $ do
      -- 3 red cells in a row: only the first should get the color SGR
      let cell = Cell 'A' (RGB 255 0 0) Default False False
          grid = setCell (setCell (setCell (mkGrid 3 1) 0 0 cell) 1 0 cell) 2 0 cell
          s = B8.unpack (renderANSI grid)
          -- Count occurrences of the red foreground SGR
          redSgr = "\ESC[38;2;255;0;0m"
          count _ [] = 0
          count needle hay@(_:rest)
            | take (length needle) hay == needle = 1 + count needle (drop (length needle) hay)
            | otherwise = count needle rest
      count redSgr s `shouldBe` (1 :: Int)

    it "emits new SGR when color changes between cells" $ do
      -- First cell red, second cell green: both color SGRs must appear
      let red   = Cell 'R' (RGB 255 0 0) Default False False
          green = Cell 'G' (RGB 0 255 0) Default False False
          grid  = setCell (setCell (mkGrid 2 1) 0 0 red) 1 0 green
          s = B8.unpack (renderANSI grid)
      s `shouldContain` "\ESC[38;2;255;0;0m"
      s `shouldContain` "\ESC[38;2;0;255;0m"
