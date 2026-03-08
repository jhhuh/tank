module Tank.Terminal.Grid
  ( Grid(..)
  , GridCell(..)
  , CellAttrs(..)
  , Color(..)
  , mkGrid
  , writeCell
  , readCell
  , clearScreen
  , advanceViewport
  , visibleRange
  , defaultCell
  , defaultAttrs
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Word (Word64)
import Tank.Core.CRDT (LWW(..), EpochLWW(..), ReplicaId, mkLWW, mkEpochLWW, mergeLWW, mergeEpochLWW)

data Color
  = DefaultColor
  | Color256 !Int
  | ColorRGB !Int !Int !Int
  deriving (Eq, Show)

data CellAttrs = CellAttrs
  { attrBold      :: !Bool
  , attrItalic    :: !Bool
  , attrUnderline :: !Bool
  , attrReverse   :: !Bool
  , attrBlink     :: !Bool
  , attrDim       :: !Bool
  } deriving (Eq, Show)

defaultAttrs :: CellAttrs
defaultAttrs = CellAttrs False False False False False False

data GridCell = GridCell
  { gcCodepoint :: !Char
  , gcFg        :: !Color
  , gcBg        :: !Color
  , gcAttrs     :: !CellAttrs
  } deriving (Eq, Show)

defaultCell :: GridCell
defaultCell = GridCell ' ' DefaultColor DefaultColor defaultAttrs

-- | Terminal grid with spatial jitter buffer and epoch-based clear
data Grid = Grid
  { gridWidth       :: !Int
  , gridHeight      :: !Int
  , gridBufferAbove :: !Int          -- hidden above size (scrollback cache)
  , gridBufferBelow :: !Int          -- hidden below size (jitter buffer)
  , gridViewport    :: !(LWW Word64) -- absolute line of viewport top
  , gridEpoch       :: !(LWW Word64) -- clear screen epoch
  , gridCells       :: !(Map (Word64, Int) (EpochLWW GridCell))
  } deriving (Show)

mkGrid :: ReplicaId -> Int -> Int -> Int -> Int -> Grid
mkGrid rid w h above below = Grid
  { gridWidth       = w
  , gridHeight      = h
  , gridBufferAbove = above
  , gridBufferBelow = below
  , gridViewport    = mkLWW rid 0 0
  , gridEpoch       = mkLWW rid 0 0
  , gridCells       = Map.empty
  }

-- | Write a cell at an absolute position
writeCell :: ReplicaId -> Word64 -> Word64 -> Word64 -> Int -> GridCell -> Grid -> Grid
writeCell rid ts epoch absLine col cell grid =
  let ecell = mkEpochLWW rid ts epoch cell
      key = (absLine, col)
      cells' = Map.insertWith mergeEpochLWW key ecell (gridCells grid)
  in grid { gridCells = cells' }

-- | Read a cell at an absolute position, respecting epoch
readCell :: Grid -> Word64 -> Int -> Maybe GridCell
readCell grid absLine col =
  case Map.lookup (absLine, col) (gridCells grid) of
    Nothing -> Nothing
    Just ecell
      | elwwEpoch ecell < lwwValue (gridEpoch grid) -> Nothing  -- stale
      | otherwise -> Just (elwwValue ecell)

-- | Clear screen: increment epoch
clearScreen :: ReplicaId -> Word64 -> Grid -> Grid
clearScreen rid ts grid =
  let curEpoch = lwwValue (gridEpoch grid)
      newEpoch = mkLWW rid ts (curEpoch + 1)
  in grid { gridEpoch = mergeLWW newEpoch (gridEpoch grid) }

-- | Advance viewport position
advanceViewport :: ReplicaId -> Word64 -> Word64 -> Grid -> Grid
advanceViewport rid ts newPos grid =
  let newVp = mkLWW rid ts newPos
  in grid { gridViewport = mergeLWW newVp (gridViewport grid) }

-- | Get the visible line range (viewport top to viewport top + height)
visibleRange :: Grid -> (Word64, Word64)
visibleRange grid =
  let top = lwwValue (gridViewport grid)
  in (top, top + fromIntegral (gridHeight grid) - 1)
