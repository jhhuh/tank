{-# LANGUAGE OverloadedStrings #-}
module Tank.Layout.DSL
  ( -- Splitting
    hsplit, vsplit, hsplit2, vsplit2
    -- Overlays
  , overlay, centered, bottomPinned
    -- Decoration
  , bordered, roundBordered, titled, titled'
    -- Content
  , text, styled, spans, fill, cells
    -- Patterns
  , withStatusBar
  ) where

import Data.Text (Text)
import Data.Vector (Vector)
import Tank.Layout.Types
import Tank.Layout.Cell (Cell, CellGrid(..), Color(..))

-- Splitting
hsplit :: Float -> Layout -> Layout -> Layout
hsplit = Split Horizontal

vsplit :: Float -> Layout -> Layout -> Layout
vsplit = Split Vertical

hsplit2 :: Layout -> Layout -> Layout
hsplit2 = hsplit 0.5

vsplit2 :: Layout -> Layout -> Layout
vsplit2 = vsplit 0.5

-- Overlays
overlay :: Anchor -> Layout -> Layout -> Layout
overlay anchor base floating = Layers base [(anchor, floating)]

centered :: Layout -> Layout -> Layout
centered = overlay Center

bottomPinned :: Layout -> Layout -> Layout
bottomPinned = overlay Bottom

-- Decoration
bordered :: Layout -> Layout
bordered = Styled defaultStyle { sBorder = Just (Border Single Default) }

roundBordered :: Layout -> Layout
roundBordered = Styled defaultStyle { sBorder = Just (Border Rounded Default) }

titled :: Text -> Layout -> Layout
titled t = Styled defaultStyle
  { sBorder = Just (Border Single Default)
  , sTitle  = Just (t, "")
  }

titled' :: Text -> Text -> Layout -> Layout
titled' t hint = Styled defaultStyle
  { sBorder = Just (Border Single Default)
  , sTitle  = Just (t, hint)
  }

-- Content
text :: Text -> Layout
text t = Leaf (Text [plainSpan t])

styled :: Color -> Text -> Layout
styled c t = Leaf (Text [Span t (SpanStyle (Just c) False False)])

spans :: [Span] -> Layout
spans = Leaf . Text

fill :: Char -> Layout
fill ch = Leaf (Fill ch Default)

cells :: Vector (Vector Cell) -> Layout
cells = Leaf . CellContent . CellGrid

-- Patterns
withStatusBar :: Layout -> [Span] -> Layout
withStatusBar content bar = Split Vertical (-1) content (Leaf (Text bar))
