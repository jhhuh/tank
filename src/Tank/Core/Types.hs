module Tank.Core.Types
  ( CellId(..)
  , PlugId(..)
  , Cell(..)
  , PlugCapability(..)
  , PlugInfo(..)
  , GridDelta(..)
  , CellUpdate(..)
  , ViewportUpdate(..)
  , EpochUpdate(..)
  , GridSnapshot(..)
  ) where

import Data.Map.Strict (Map)
import Data.Set (Set)
import Data.Text (Text)
import Data.UUID (UUID)
import Data.Word (Word64)
import Tank.Core.CRDT (ReplicaId)
import Tank.Terminal.Grid (Grid, GridCell)

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
  , cellPtyOwner  :: !(Maybe PlugId)
  , cellGrid      :: !Grid
  } deriving (Show)

data GridDelta
  = DeltaCells ![CellUpdate]
  | DeltaViewport !ViewportUpdate
  | DeltaEpoch !EpochUpdate
  | DeltaSnapshot !GridSnapshot
  deriving (Eq, Show)

data CellUpdate = CellUpdate
  { cuAbsLine   :: !Word64
  , cuCol       :: !Int
  , cuCell      :: !GridCell
  , cuEpoch     :: !Word64
  , cuTimestamp  :: !Word64
  , cuReplicaId :: !ReplicaId
  } deriving (Eq, Show)

data ViewportUpdate = ViewportUpdate
  { vuAbsLine   :: !Word64
  , vuTimestamp  :: !Word64
  , vuReplicaId  :: !ReplicaId
  } deriving (Eq, Show)

data EpochUpdate = EpochUpdate
  { euEpoch     :: !Word64
  , euTimestamp  :: !Word64
  , euReplicaId  :: !ReplicaId
  } deriving (Eq, Show)

data GridSnapshot = GridSnapshot
  { gsWidth       :: !Int
  , gsHeight      :: !Int
  , gsBufferAbove :: !Int
  , gsBufferBelow :: !Int
  , gsViewport    :: !Word64
  , gsEpoch       :: !Word64
  , gsCells       :: ![CellUpdate]
  } deriving (Eq, Show)
