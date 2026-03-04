{-# LANGUAGE OverloadedStrings #-}

module Tank.Terminal.EmulatorSpec (spec) where

import Test.Hspec
import qualified Data.ByteString.Char8 as B8
import qualified Data.Vector as V
import Tank.Terminal.Emulator

spec :: Spec
spec = do
  describe "VTerm basics" $ do
    it "creates an empty terminal" $ do
      let vt = mkVTerm 80 24
      vtGetSize vt `shouldBe` (80, 24)
      vtGetCursor vt `shouldBe` (0, 0)
      cChar (vtGetCell 0 0 vt) `shouldBe` ' '

    it "writes characters at cursor" $ do
      let vt = vtFeed "ABC" (mkVTerm 80 24)
      cChar (vtGetCell 0 0 vt) `shouldBe` 'A'
      cChar (vtGetCell 0 1 vt) `shouldBe` 'B'
      cChar (vtGetCell 0 2 vt) `shouldBe` 'C'
      vtGetCursor vt `shouldBe` (0, 3)

    it "handles carriage return and linefeed" $ do
      let vt = vtFeed "AB\r\nCD" (mkVTerm 80 24)
      cChar (vtGetCell 0 0 vt) `shouldBe` 'A'
      cChar (vtGetCell 0 1 vt) `shouldBe` 'B'
      cChar (vtGetCell 1 0 vt) `shouldBe` 'C'
      cChar (vtGetCell 1 1 vt) `shouldBe` 'D'
      vtGetCursor vt `shouldBe` (1, 2)

    it "handles backspace" $ do
      let vt = vtFeed "AB\x08X" (mkVTerm 80 24)
      cChar (vtGetCell 0 0 vt) `shouldBe` 'A'
      cChar (vtGetCell 0 1 vt) `shouldBe` 'X'

  describe "Cursor movement" $ do
    it "handles CUP (cursor position)" $ do
      let vt = vtFeed "\x1b[5;10H" (mkVTerm 80 24)
      vtGetCursor vt `shouldBe` (4, 9)  -- 1-indexed to 0-indexed

    it "handles CUU/CUD/CUF/CUB" $ do
      let vt = vtFeed "\x1b[10;10H\x1b[3A" (mkVTerm 80 24)
      vtGetCursor vt `shouldBe` (6, 9)  -- moved up 3

    it "clamps cursor to screen bounds" $ do
      let vt = vtFeed "\x1b[999;999H" (mkVTerm 80 24)
      vtGetCursor vt `shouldBe` (23, 79)

  describe "Erase" $ do
    it "clears entire screen with ED 2" $ do
      let vt0 = vtFeed "Hello World" (mkVTerm 80 24)
      let vt = vtFeed "\x1b[2J" vt0
      cChar (vtGetCell 0 0 vt) `shouldBe` ' '
      cChar (vtGetCell 0 4 vt) `shouldBe` ' '

    it "clears to end of line with EL 0" $ do
      let vt0 = vtFeed "Hello World" (mkVTerm 80 24)
      let vt = vtFeed "\x1b[6G\x1b[K" vt0  -- move to col 6, erase to EOL
      cChar (vtGetCell 0 0 vt) `shouldBe` 'H'
      cChar (vtGetCell 0 4 vt) `shouldBe` 'o'
      cChar (vtGetCell 0 5 vt) `shouldBe` ' '  -- erased

  describe "SGR (colors/attributes)" $ do
    it "sets bold attribute" $ do
      let vt = vtFeed "\x1b[1mX" (mkVTerm 80 24)
      let cell = vtGetCell 0 0 vt
      cChar cell `shouldBe` 'X'
      hasFlag attrBold (cAttrs cell) `shouldBe` True

    it "sets foreground color" $ do
      let vt = vtFeed "\x1b[31mR" (mkVTerm 80 24)
      let cell = vtGetCell 0 0 vt
      aFg (cAttrs cell) `shouldBe` Color256 1  -- red

    it "resets attributes" $ do
      let vt = vtFeed "\x1b[1;31mX\x1b[0mY" (mkVTerm 80 24)
      let cellX = vtGetCell 0 0 vt
      let cellY = vtGetCell 0 1 vt
      aFg (cAttrs cellX) `shouldBe` Color256 1
      aFg (cAttrs cellY) `shouldBe` DefaultColor

  describe "Scrolling" $ do
    it "scrolls when writing past bottom" $ do
      let vt0 = mkVTerm 80 3
      -- Fill 3 rows and write one more line
      let vt = vtFeed "AAA\r\nBBB\r\nCCC\r\nDDD" vt0
      -- After scroll, row 0 should be BBB, row 1 CCC, row 2 DDD
      cChar (vtGetCell 0 0 vt) `shouldBe` 'B'
      cChar (vtGetCell 1 0 vt) `shouldBe` 'C'
      cChar (vtGetCell 2 0 vt) `shouldBe` 'D'

    it "handles scroll region (DECSTBM)" $ do
      let vt0 = vtFeed "AAA\r\nBBB\r\nCCC\r\nDDD\r\nEEE" (mkVTerm 80 5)
      -- Set scroll region to rows 2-4 (1-indexed), then scroll
      let vt = vtFeed "\x1b[2;4r\x1b[2;1H\x1b[S" vt0
      -- Row 0 (outside region) unchanged: AAA
      cChar (vtGetCell 0 0 vt) `shouldBe` 'A'

    it "saves scrolled-off lines to scrollback" $ do
      let vt0 = mkVTerm 80 3
      let vt = vtFeed "AAA\r\nBBB\r\nCCC\r\nDDD\r\nEEE" vt0
      -- Two lines scrolled off: AAA then BBB
      vtScrollbackSize vt `shouldBe` 2
      let sb = vtScrollbackLines vt
      -- Most recent first: BBB then AAA
      cChar ((sb !! 0) V.! 0) `shouldBe` 'B'
      cChar ((sb !! 1) V.! 0) `shouldBe` 'A'

    it "does not save to scrollback in alt screen" $ do
      let vt0 = mkVTerm 80 3
      let vt1 = vtFeed "AAA\r\nBBB\r\nCCC" vt0
      let vt2 = vtFeed "\x1b[?1049h" vt1  -- switch to alt
      let vt3 = vtFeed "XXX\r\nYYY\r\nZZZ\r\nWWW" vt2  -- scroll in alt
      vtScrollbackSize vt3 `shouldBe` 0  -- alt screen doesn't save

    it "does not save to scrollback in scroll region" $ do
      let vt0 = vtFeed "AAA\r\nBBB\r\nCCC\r\nDDD\r\nEEE" (mkVTerm 80 5)
      let vt = vtFeed "\x1b[2;4r\x1b[2;1H\x1b[S" vt0  -- scroll within region
      vtScrollbackSize vt `shouldBe` 0  -- region scroll doesn't save

  describe "Alternate screen" $ do
    it "switches to and from alt screen" $ do
      let vt0 = vtFeed "Hello" (mkVTerm 80 24)
      let vt1 = vtFeed "\x1b[?1049h" vt0  -- switch to alt
      cChar (vtGetCell 0 0 vt1) `shouldBe` ' '  -- alt screen is blank
      let vt2 = vtFeed "\x1b[?1049l" vt1  -- switch back
      cChar (vtGetCell 0 0 vt2) `shouldBe` 'H'  -- original content

  describe "Line wrapping" $ do
    it "wraps at end of line" $ do
      let vt = vtFeed (B8.replicate 82 'X') (mkVTerm 80 24)
      cChar (vtGetCell 0 79 vt) `shouldBe` 'X'
      cChar (vtGetCell 1 0 vt) `shouldBe` 'X'
      cChar (vtGetCell 1 1 vt) `shouldBe` 'X'

  describe "Resize" $ do
    it "preserves content on resize" $ do
      let vt0 = vtFeed "Hello" (mkVTerm 80 24)
      let vt = vtResize 40 12 vt0
      vtGetSize vt `shouldBe` (40, 12)
      cChar (vtGetCell 0 0 vt) `shouldBe` 'H'
      cChar (vtGetCell 0 4 vt) `shouldBe` 'o'
