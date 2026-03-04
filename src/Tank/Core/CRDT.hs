module Tank.Core.CRDT
  ( LWW(..)
  , mkLWW
  , mergeLWW
  , EpochLWW(..)
  , mkEpochLWW
  , mergeEpochLWW
  , isStale
  , ReplicaId(..)
  ) where

import Data.Word (Word64)
import Data.UUID (UUID)

newtype ReplicaId = ReplicaId UUID
  deriving (Eq, Ord, Show)

-- | Last-Writer-Wins Register
data LWW a = LWW
  { lwwValue     :: !a
  , lwwTimestamp  :: !Word64
  , lwwReplicaId :: !ReplicaId
  } deriving (Show)

mkLWW :: ReplicaId -> Word64 -> a -> LWW a
mkLWW rid ts val = LWW val ts rid

mergeLWW :: LWW a -> LWW a -> LWW a
mergeLWW a b
  | lwwTimestamp a > lwwTimestamp b = a
  | lwwTimestamp a < lwwTimestamp b = b
  | lwwReplicaId a >= lwwReplicaId b = a  -- tie-break on replica ID
  | otherwise = b

-- | Epoch-tagged LWW Register (for terminal grid cells)
data EpochLWW a = EpochLWW
  { elwwValue     :: !a
  , elwwTimestamp  :: !Word64
  , elwwEpoch     :: !Word64
  , elwwReplicaId :: !ReplicaId
  } deriving (Show)

mkEpochLWW :: ReplicaId -> Word64 -> Word64 -> a -> EpochLWW a
mkEpochLWW rid ts epoch val = EpochLWW val ts epoch rid

mergeEpochLWW :: EpochLWW a -> EpochLWW a -> EpochLWW a
mergeEpochLWW a b
  | elwwEpoch a > elwwEpoch b = a
  | elwwEpoch a < elwwEpoch b = b
  | elwwTimestamp a > elwwTimestamp b = a
  | elwwTimestamp a < elwwTimestamp b = b
  | elwwReplicaId a >= elwwReplicaId b = a
  | otherwise = b

-- | Check if a cell is stale (epoch < grid epoch)
isStale :: Word64 -> EpochLWW a -> Bool
isStale gridEpoch cell = elwwEpoch cell < gridEpoch
