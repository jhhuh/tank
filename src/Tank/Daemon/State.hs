module Tank.Daemon.State
  ( DaemonState(..)
  , PlugConn(..)
  , newDaemonState
  , addCell
  , removeCell
  , getCell
  , listCells
  , addPlug
  , removePlug
  ) where

import Control.Concurrent.STM
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Network.Socket (Socket)
import Tank.Core.Types (CellId(..), PlugId(..), Cell(..), PlugInfo(..))

data PlugConn = PlugConn
  { pcInfo   :: !PlugInfo
  , pcSocket :: !Socket
  }

instance Show PlugConn where
  show pc = "PlugConn{" ++ show (pcInfo pc) ++ "}"

data DaemonState = DaemonState
  { dsCells :: !(TVar (Map CellId Cell))
  , dsPlugs :: !(TVar (Map PlugId PlugConn))
  }

newDaemonState :: IO DaemonState
newDaemonState = do
  cells <- newTVarIO Map.empty
  plugs <- newTVarIO Map.empty
  pure $ DaemonState cells plugs

addCell :: DaemonState -> Cell -> STM ()
addCell ds cell =
  modifyTVar' (dsCells ds) (Map.insert (cellId cell) cell)

removeCell :: DaemonState -> CellId -> STM ()
removeCell ds cid =
  modifyTVar' (dsCells ds) (Map.delete cid)

getCell :: DaemonState -> CellId -> STM (Maybe Cell)
getCell ds cid =
  Map.lookup cid <$> readTVar (dsCells ds)

listCells :: DaemonState -> STM [(CellId, FilePath)]
listCells ds = do
  cells <- readTVar (dsCells ds)
  pure [(cellId c, cellDirectory c) | c <- Map.elems cells]

addPlug :: DaemonState -> PlugConn -> STM ()
addPlug ds pc =
  modifyTVar' (dsPlugs ds) (Map.insert (piId $ pcInfo pc) pc)

removePlug :: DaemonState -> PlugId -> STM ()
removePlug ds pid =
  modifyTVar' (dsPlugs ds) (Map.delete pid)
