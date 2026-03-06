module Tank.Layout.Backend.ANSI
  ( renderANSI
  , renderRowANSI
  ) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder, toLazyByteString, charUtf8, string7)
import qualified Data.ByteString.Lazy as LBS
import Data.Word (Word8)
import qualified Data.Vector as V
import Tank.Layout.Cell

-- | Previous cell attributes for delta-encoding. 'Nothing' forces full SGR
-- emission on the first cell.
type Prev = Maybe Cell

renderANSI :: CellGrid -> ByteString
renderANSI (CellGrid rows) =
  LBS.toStrict $ toLazyByteString $
    snd (V.ifoldl' foldRow (Nothing, mempty) rows)
    <> string7 "\ESC[0m"
  where
    foldRow :: (Prev, Builder) -> Int -> V.Vector Cell -> (Prev, Builder)
    foldRow (prev, b) rowIdx row =
      let nl = if rowIdx < V.length rows - 1 then string7 "\n" else mempty
          (prev', rb) = renderRow prev row
      in (prev', b <> rb <> nl)

-- | Render a single row of cells to ANSI ByteString, with delta-encoding.
-- Includes trailing SGR reset. Useful for stamping rows at terminal positions.
renderRowANSI :: V.Vector Cell -> ByteString
renderRowANSI row =
  LBS.toStrict $ toLazyByteString $
    snd (renderRow Nothing row) <> string7 "\ESC[0m"

renderRow :: Prev -> V.Vector Cell -> (Prev, Builder)
renderRow prev row = V.foldl' step (prev, mempty) row
  where
    step (p, b) cell =
      let sgr = diffSGR p cell
      in (Just cell, b <> sgr <> charUtf8 (cellChar cell))

-- | Emit only the SGR codes that differ from the previous cell.
-- 'Nothing' means no previous cell — emit all attributes.
diffSGR :: Prev -> Cell -> Builder
diffSGR Nothing (Cell _ fg bg bold dim_) =
  sgrFg fg <> sgrBg bg <> sgrIntensity bold dim_
diffSGR (Just (Cell _ pfg pbg pbold pdim)) (Cell _ fg bg bold dim) =
  (if fg   /= pfg   then sgrFg fg     else mempty) <>
  (if bg   /= pbg   then sgrBg bg     else mempty) <>
  -- Bold and dim share SGR 22 for reset, so treat them as a unit
  (if bold /= pbold || dim /= pdim
     then sgrIntensity bold dim
     else mempty)

sgrFg :: Color -> Builder
sgrFg Default = string7 "\ESC[39m"
sgrFg (RGB r g b) = string7 "\ESC[38;2;" <> w8 r <> string7 ";" <> w8 g <> string7 ";" <> w8 b <> string7 "m"

sgrBg :: Color -> Builder
sgrBg Default = string7 "\ESC[49m"
sgrBg (RGB r g b) = string7 "\ESC[48;2;" <> w8 r <> string7 ";" <> w8 g <> string7 ";" <> w8 b <> string7 "m"

-- | Emit intensity attributes as a unit. SGR 22 resets both bold and dim,
-- so when either changes we must reset and re-assert both.
sgrIntensity :: Bool -> Bool -> Builder
sgrIntensity bold dim_ =
  string7 "\ESC[22m" <>
  (if bold then string7 "\ESC[1m" else mempty) <>
  (if dim_ then string7 "\ESC[2m" else mempty)

w8 :: Word8 -> Builder
w8 = string7 . show
