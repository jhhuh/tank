module Tank.Layout.Cell
  ( Cell(..)
  , Color(..)
  , CellGrid(..)
  , defaultCell
  , mkGrid
  , getCell
  , setCell
  , stampText
  , gridWidth
  , gridHeight
  ) where

import Data.Word (Word8)
import Data.Vector (Vector)
import qualified Data.Vector as V
import Data.Text (Text)
import qualified Data.Text as T

data Color = Default | RGB !Word8 !Word8 !Word8
  deriving (Eq, Show)

data Cell = Cell
  { cellChar      :: !Char
  , cellFg        :: !Color
  , cellBg        :: !Color
  , cellBold      :: !Bool
  , cellDim       :: !Bool
  , cellUnderline :: !Bool
  , cellItalic    :: !Bool
  , cellInverse   :: !Bool
  , cellBlink     :: !Bool
  } deriving (Eq, Show)

defaultCell :: Cell
defaultCell = Cell ' ' Default Default False False False False False False

-- Row-major grid: outer vector = rows, inner = columns
newtype CellGrid = CellGrid { gridRows :: Vector (Vector Cell) }
  deriving (Show)

gridWidth :: CellGrid -> Int
gridWidth (CellGrid rows)
  | V.null rows = 0
  | otherwise   = V.length (V.head rows)

gridHeight :: CellGrid -> Int
gridHeight (CellGrid rows) = V.length rows

mkGrid :: Int -> Int -> CellGrid
mkGrid w h = CellGrid $ V.replicate h (V.replicate w defaultCell)

getCell :: CellGrid -> Int -> Int -> Cell
getCell (CellGrid rows) col row
  | row >= 0 && row < V.length rows =
      let r = rows V.! row
      in if col >= 0 && col < V.length r then r V.! col else defaultCell
  | otherwise = defaultCell

setCell :: CellGrid -> Int -> Int -> Cell -> CellGrid
setCell (CellGrid rows) col row cell
  | row >= 0 && row < V.length rows && col >= 0 =
      let r = rows V.! row
      in if col < V.length r
         then CellGrid $ rows V.// [(row, r V.// [(col, cell)])]
         else CellGrid rows
  | otherwise = CellGrid rows

stampText :: CellGrid -> Int -> Int -> Color -> Color -> Text -> CellGrid
stampText grid startCol row fg bg txt =
  fst $ T.foldl' step (grid, startCol) txt
  where
    step (g, col) ch = (setCell g col row (Cell ch fg bg False False False False False False), col + 1)
