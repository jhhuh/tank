module Tank.Layout.Backend.ANSI
  ( renderANSI
  ) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder, toLazyByteString, char7, string7)
import qualified Data.ByteString.Lazy as LBS
import Data.Word (Word8)
import qualified Data.Vector as V
import Tank.Layout.Cell

renderANSI :: CellGrid -> ByteString
renderANSI (CellGrid rows) =
  LBS.toStrict $ toLazyByteString $
    V.ifoldl' (\b rowIdx row ->
      b <> renderRow row <> (if rowIdx < V.length rows - 1 then string7 "\n" else mempty)
    ) mempty rows
    <> string7 "\ESC[0m"

renderRow :: V.Vector Cell -> Builder
renderRow row =
  V.foldl' (\b cell -> b <> renderCell cell) mempty row

renderCell :: Cell -> Builder
renderCell (Cell ch fg bg bold dim) =
  sgrFg fg <> sgrBg bg <> sgrBold bold <> sgrDim dim <> char7 ch

sgrFg :: Color -> Builder
sgrFg Default = string7 "\ESC[39m"
sgrFg (RGB r g b) = string7 "\ESC[38;2;" <> w8 r <> string7 ";" <> w8 g <> string7 ";" <> w8 b <> string7 "m"

sgrBg :: Color -> Builder
sgrBg Default = string7 "\ESC[49m"
sgrBg (RGB r g b) = string7 "\ESC[48;2;" <> w8 r <> string7 ";" <> w8 g <> string7 ";" <> w8 b <> string7 "m"

sgrBold :: Bool -> Builder
sgrBold True  = string7 "\ESC[1m"
sgrBold False = string7 "\ESC[22m"

sgrDim :: Bool -> Builder
sgrDim True  = string7 "\ESC[2m"
sgrDim False = mempty

w8 :: Word8 -> Builder
w8 = string7 . show
