module Tank.Daemon.Router
  ( routeMessage
  ) where

import Control.Concurrent.STM
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.UUID (nil)

import Tank.Core.CRDT (ReplicaId(..))
import Tank.Core.Types
import Tank.Core.Protocol
import Tank.Daemon.State
import Tank.Terminal.Grid (mkGrid)

-- | Route an incoming message to the appropriate handler.
-- Returns 'Just response' for messages that need a reply,
-- 'Nothing' for fire-and-forget messages.
routeMessage :: DaemonState -> MessageEnvelope -> IO (Maybe Message)
routeMessage ds envelope = case mePayload envelope of

  -- Plug lifecycle
  MsgPlugRegister info -> do
    -- NOTE: We can't store the PlugConn here because routeMessage doesn't
    -- have access to the client Handle. The handle linkage will be added
    -- in Main.hs where the Handle is available.
    pure $ Just $ MsgPlugRegistered (piId info)

  MsgPlugDeregister pid -> do
    atomically $ do
      removePlug ds pid
      -- Detach from all cells
      cells <- readTVar (dsCells ds)
      let cells' = Map.map (\c -> c { cellPlugs = Set.delete pid (cellPlugs c) }) cells
      writeTVar (dsCells ds) cells'
    pure Nothing

  -- Cell lifecycle
  MsgCellCreate cid dir -> do
    let cell = Cell
          { cellId = cid
          , cellDirectory = dir
          , cellEnv = Map.empty
          , cellPlugs = Set.empty
          , cellGrid = mkGrid (ReplicaId nil) 80 24 100 10
          }
    atomically $ addCell ds cell
    pure Nothing

  MsgCellDestroy cid -> do
    atomically $ removeCell ds cid
    pure Nothing

  MsgCellAttach cid pid -> do
    atomically $ do
      mcell <- getCell ds cid
      case mcell of
        Nothing -> pure ()
        Just cell -> do
          let cell' = cell { cellPlugs = Set.insert pid (cellPlugs cell) }
          addCell ds cell'
    pure Nothing

  MsgCellDetach cid pid -> do
    atomically $ do
      mcell <- getCell ds cid
      case mcell of
        Nothing -> pure ()
        Just cell -> do
          let cell' = cell { cellPlugs = Set.delete pid (cellPlugs cell) }
          addCell ds cell'
    pure Nothing

  -- Queries
  MsgListCells -> do
    cells <- atomically $ listCells ds
    pure $ Just $ MsgListCellsResponse cells

  -- I/O routing (forward to attached plugs — needs broadcast mechanism, stub for now)
  MsgInput _cid _bytes -> pure Nothing
  MsgOutput _cid _bytes -> pure Nothing

  -- State sync (deferred to Phase 4)
  MsgStateUpdate _cid _delta -> pure Nothing

  -- Response messages shouldn't arrive at router, ignore them
  MsgPlugRegistered _ -> pure Nothing
  MsgListCellsResponse _ -> pure Nothing
  MsgFetchLines {} -> pure Nothing
  MsgFetchLinesResponse _ _ -> pure Nothing
