module Tank.Core.Protocol
  ( Message(..)
  , MessageEnvelope(..)
  , Target(..)
  ) where

import Data.ByteString (ByteString)
import Data.Word (Word64)
import Data.Text (Text)
import Tank.Core.Types (CellId, PlugId, PlugInfo)

data Target
  = TargetCell !CellId
  | TargetPlug !PlugId
  | TargetBroadcast
  deriving (Eq, Show)

data MessageEnvelope = MessageEnvelope
  { meVersion   :: !Word64
  , meSource    :: !PlugId
  , meTarget    :: !Target
  , meSequence  :: !Word64  -- Lamport clock
  , mePayload   :: !Message
  } deriving (Eq, Show)

data Message
  = MsgPlugRegister !PlugInfo
  | MsgPlugRegistered !PlugId
  | MsgPlugDeregister !PlugId
  | MsgCellCreate !CellId !FilePath
  | MsgCellDestroy !CellId
  | MsgCellAttach !CellId !PlugId
  | MsgCellDetach !CellId !PlugId
  | MsgStateUpdate !CellId !ByteString  -- CRDT delta (serialized)
  | MsgFetchLines !CellId !Word64 !Word64  -- from_line, to_line
  | MsgFetchLinesResponse !CellId ![(Word64, Text)]  -- line_num, content
  | MsgListCells
  | MsgListCellsResponse ![(CellId, FilePath)]
  | MsgInput !CellId !ByteString  -- keyboard input to forward to PTY
  | MsgOutput !CellId !ByteString  -- PTY output
  deriving (Eq, Show)
