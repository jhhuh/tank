module Tank.Layout.Types
  ( Layout(..)
  , Dir(..)
  , Anchor(..)
  , Style(..)
  , Border(..)
  , BorderStyle(..)
  , Edges(..)
  , Content(..)
  , Span(..)
  , SpanStyle(..)
  , Rect(..)
  , plainSpan
  , defaultStyle
  , noEdges
  ) where

import Data.Text (Text)
import Tank.Layout.Cell (CellGrid, Color(..))

data Layout
  = Leaf !Content
  | Split !Dir !Float Layout Layout
  | Layers Layout [(Anchor, Layout)]
  | Styled !Style Layout
  deriving (Show)

data Dir = Horizontal | Vertical
  deriving (Eq, Show)

data Anchor
  = Center
  | Bottom
  | Absolute !Int !Int
  deriving (Eq, Show)

data Style = Style
  { sBorder  :: !(Maybe Border)
  , sPadding :: !Edges
  , sTitle   :: !(Maybe (Text, Text))
  , sBg      :: !(Maybe Color)
  } deriving (Eq, Show)

defaultStyle :: Style
defaultStyle = Style Nothing noEdges Nothing Nothing

data Border = Border
  { bStyle :: !BorderStyle
  , bColor :: !Color
  } deriving (Eq, Show)

data BorderStyle = Single | Rounded | Heavy
  deriving (Eq, Show)

data Edges = Edges !Int !Int !Int !Int  -- top right bottom left
  deriving (Eq, Show)

noEdges :: Edges
noEdges = Edges 0 0 0 0

data Content
  = Text ![Span]
  | Fill !Char !Color
  | CellContent !CellGrid
  deriving (Show)

data Span = Span !Text !SpanStyle
  deriving (Show)

data SpanStyle = SpanStyle
  { spanFg   :: !(Maybe Color)
  , spanBold :: !Bool
  , spanDim  :: !Bool
  } deriving (Eq, Show)

plainSpan :: Text -> Span
plainSpan t = Span t (SpanStyle Nothing False False)

-- | A positioned rectangle: col, row, width, height
data Rect = Rect !Int !Int !Int !Int
  deriving (Eq, Show)
