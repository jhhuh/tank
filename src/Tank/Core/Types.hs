module Tank.Core.Types
  ( CellId(..)
  , PlugId(..)
  , Cell(..)
  , PlugCapability(..)
  , PlugInfo(..)
  ) where

import Data.Map.Strict (Map)
import Data.Set (Set)
import Data.Text (Text)
import Data.UUID (UUID)
import Tank.Terminal.Grid (Grid)

newtype CellId = CellId UUID
  deriving (Eq, Ord, Show)

newtype PlugId = PlugId UUID
  deriving (Eq, Ord, Show)

data PlugCapability
  = CapTerminal     -- ^ Can provide terminal emulation
  | CapOperator     -- ^ Can provide coding agent
  | CapDevshell     -- ^ Can manage devshell activation
  | CapProcessMgr   -- ^ Can manage per-project processes
  deriving (Eq, Ord, Show)

data PlugInfo = PlugInfo
  { piId           :: !PlugId
  , piName         :: !Text
  , piCapabilities :: !(Set PlugCapability)
  } deriving (Eq, Show)

data Cell = Cell
  { cellId        :: !CellId
  , cellDirectory :: !FilePath
  , cellEnv       :: !(Map Text Text)
  , cellPlugs     :: !(Set PlugId)
  , cellGrid      :: !Grid
  } deriving (Show)
