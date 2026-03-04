module Tank.Daemon.Router
  ( routeMessage
  ) where

import Tank.Core.Protocol (Message(..), MessageEnvelope(..))
import Tank.Daemon.State (DaemonState)

-- | Route an incoming message to the appropriate handler
routeMessage :: DaemonState -> MessageEnvelope -> IO (Maybe Message)
routeMessage _ds envelope = case mePayload envelope of
  MsgListCells -> pure $ Just $ MsgListCellsResponse []  -- TODO: implement
  _ -> pure Nothing  -- TODO: implement routing
