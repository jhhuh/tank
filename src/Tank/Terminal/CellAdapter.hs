module Tank.Terminal.CellAdapter
  ( gridToCellGrid
  , vtermToCellGrid
  , convertGridCell
  , convertColor
  ) where

import qualified Tank.Terminal.Grid as VT
import qualified Tank.Terminal.Emulator as Em
import qualified Tank.Layout.Cell as LC
import qualified Data.Vector as V
import Data.Word (Word8)

-- | Convert a VTerm Grid's visible viewport to a tank-layout CellGrid.
gridToCellGrid :: VT.Grid -> LC.CellGrid
gridToCellGrid vtGrid =
  let w = VT.gridWidth vtGrid
      h = VT.gridHeight vtGrid
      (topLine, _) = VT.visibleRange vtGrid
      rows = V.generate h $ \r ->
        V.generate w $ \c ->
          case VT.readCell vtGrid (topLine + fromIntegral r) c of
            Just gc -> convertGridCell gc
            Nothing -> LC.defaultCell
  in LC.CellGrid rows

-- | Convert a single VTerm GridCell to a tank-layout Cell.
convertGridCell :: VT.GridCell -> LC.Cell
convertGridCell gc = LC.Cell
  { LC.cellChar = VT.gcCodepoint gc
  , LC.cellFg   = convertColor (VT.gcFg gc)
  , LC.cellBg   = convertColor (VT.gcBg gc)
  , LC.cellBold = VT.attrBold (VT.gcAttrs gc)
  , LC.cellDim  = VT.attrDim (VT.gcAttrs gc)
  }

-- | Convert VTerm Color to tank-layout Color.
convertColor :: VT.Color -> LC.Color
convertColor VT.DefaultColor      = LC.Default
convertColor (VT.ColorRGB r g b)  = LC.RGB (fromIntegral r) (fromIntegral g) (fromIntegral b)
convertColor (VT.Color256 n)      = ansi256ToRGB n

-- | ANSI 256-color palette to RGB conversion.
ansi256ToRGB :: Int -> LC.Color
ansi256ToRGB n
  | n < 0     = LC.Default
  | n < 16    = let (r, g, b) = ansi16 V.! n in LC.RGB r g b
  | n < 232   = let n' = n - 16
                    r = fromIntegral $ (n' `div` 36) * 51
                    g = fromIntegral $ ((n' `mod` 36) `div` 6) * 51
                    b = fromIntegral $ (n' `mod` 6) * 51
                in LC.RGB r g b
  | n < 256   = let v = fromIntegral $ 8 + (n - 232) * 10
                in LC.RGB v v v
  | otherwise = LC.Default

-- | Standard ANSI 16-color palette.
ansi16 :: V.Vector (Word8, Word8, Word8)
ansi16 = V.fromList
  [ (0,0,0),       (170,0,0),     (0,170,0),     (170,85,0)
  , (0,0,170),     (170,0,170),   (0,170,170),   (170,170,170)
  , (85,85,85),    (255,85,85),   (85,255,85),   (255,255,85)
  , (85,85,255),   (255,85,255),  (85,255,255),  (255,255,255)
  ]

-- | Convert a VTerm's visible screen to a tank-layout CellGrid.
-- Uses the public VTerm API (vtGetCell, vtGetSize).
vtermToCellGrid :: Em.VTerm -> LC.CellGrid
vtermToCellGrid vt =
  let (cols, rows) = Em.vtGetSize vt
      grid = V.generate rows $ \r ->
        V.generate cols $ \c ->
          convertEmulatorCell (Em.vtGetCell r c vt)
  in LC.CellGrid grid

-- | Convert a VTerm Emulator Cell to a tank-layout Cell.
convertEmulatorCell :: Em.Cell -> LC.Cell
convertEmulatorCell (Em.Cell ch attrs) = LC.Cell
  { LC.cellChar = ch
  , LC.cellFg   = convertEmulatorColor (Em.aFg attrs)
  , LC.cellBg   = convertEmulatorColor (Em.aBg attrs)
  , LC.cellBold = Em.hasFlag Em.attrBold attrs
  , LC.cellDim  = Em.hasFlag Em.attrDim attrs
  }

-- | Convert VTerm Emulator Color to tank-layout Color.
convertEmulatorColor :: Em.Color -> LC.Color
convertEmulatorColor Em.DefaultColor    = LC.Default
convertEmulatorColor (Em.Color256 n)    = ansi256ToRGB (fromIntegral n)
