{-# LANGUAGE LambdaCase #-}
module Tank.Daemon.Router
  ( RouteAction(..)
  , routeMessage
  ) where

import Control.Concurrent.STM
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.UUID (nil)
import System.IO (Handle)

import Tank.Core.CRDT (ReplicaId(..))
import Tank.Core.Types
import Tank.Core.Protocol
import Tank.Daemon.State
import Tank.Terminal.Grid (mkGrid)

-- | Routing decisions returned by the router.
data RouteAction
  = Reply Message              -- ^ Respond to the sender
  | SendTo PlugId Message      -- ^ Send to a specific plug
  | Broadcast CellId Message   -- ^ Send to all plugs attached to a cell
  deriving (Eq, Show)

-- | Route an incoming message. Returns a list of actions for the caller to dispatch.
routeMessage :: DaemonState -> Handle -> MessageEnvelope -> IO [RouteAction]
routeMessage ds handle envelope = case mePayload envelope of

  -- Plug lifecycle
  MsgPlugRegister info -> do
    let conn = PlugConn info handle
    atomically $ addPlug ds conn
    pure [Reply (MsgPlugRegistered (piId info))]

  MsgPlugDeregister pid -> do
    atomically $ do
      removePlug ds pid
      cells <- readTVar (dsCells ds)
      let cells' = Map.map (\c -> c { cellPlugs = Set.delete pid (cellPlugs c) }) cells
      writeTVar (dsCells ds) cells'
    pure []

  -- Cell lifecycle
  MsgCellCreate cid dir -> do
    let cell = Cell
          { cellId = cid
          , cellDirectory = dir
          , cellEnv = Map.empty
          , cellPlugs = Set.empty
          , cellPtyOwner = Just (meSource envelope)
          , cellGrid = mkGrid (ReplicaId nil) 80 24 100 10
          }
    atomically $ addCell ds cell
    pure []

  MsgCellDestroy cid -> do
    atomically $ removeCell ds cid
    pure []

  MsgCellAttach cid pid -> do
    mOwner <- atomically $ do
      mcell <- getCell ds cid
      case mcell of
        Nothing -> pure Nothing
        Just cell -> do
          addCell ds cell { cellPlugs = Set.insert pid (cellPlugs cell) }
          pure (cellPtyOwner cell)
    -- Notify PTY owner so it can send a snapshot to the new plug
    case mOwner of
      Just owner | owner /= meSource envelope ->
        pure [SendTo owner (MsgCellAttach cid pid)]
      _ -> pure []

  MsgCellDetach cid pid -> do
    atomically $ do
      mcell <- getCell ds cid
      case mcell of
        Nothing -> pure ()
        Just cell -> addCell ds cell { cellPlugs = Set.delete pid (cellPlugs cell) }
    pure []

  -- Queries
  MsgListCells -> do
    cells <- atomically $ listCells ds
    pure [Reply (MsgListCellsResponse cells)]

  -- I/O routing
  MsgInput cid bytes -> do
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> pure []
      Just cell -> case cellPtyOwner cell of
        Nothing -> pure []
        Just owner -> pure [SendTo owner (MsgInput cid bytes)]

  MsgOutput cid bytes -> do
    pure [Broadcast cid (MsgOutput cid bytes)]

  -- State sync
  MsgStateUpdate cid delta ->
    pure [Broadcast cid (MsgStateUpdate cid delta)]

  -- Response messages shouldn't arrive at router
  MsgPlugRegistered _ -> pure []
  MsgListCellsResponse _ -> pure []
  MsgFetchLines cid _from _to -> do
    mcell <- atomically $ getCell ds cid
    case mcell of
      Just cell | Just owner <- cellPtyOwner cell ->
        pure [SendTo owner (mePayload envelope)]
      _ -> pure []
  MsgFetchLinesResponse _ _ -> pure []
