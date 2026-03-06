{-# LANGUAGE LambdaCase #-}
module Tank.Daemon.Main
  ( startDaemon
  , startDaemonAt
  , stopDaemon
  ) where

import Control.Concurrent (forkFinally)
import Control.Exception (bracket)
import Data.UUID (nil)
import Network.Socket (Socket, accept, close)
import System.Directory (removeFile)
import System.IO (Handle, hClose, hPutStrLn, stderr)
import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Core.Types (PlugId(..))
import Tank.Daemon.Router (RouteAction(..), routeMessage)
import Tank.Daemon.Socket (listenSocket, socketPath, socketHandle, readEnvelope, writeEnvelope)
import Tank.Daemon.State (DaemonState, newDaemonState)

-- | Start the tank daemon
startDaemon :: String -> IO ()
startDaemon name = do
  path <- socketPath name
  startDaemonAt path

-- | Start daemon on a specific socket path (useful for testing)
startDaemonAt :: FilePath -> IO ()
startDaemonAt path = do
  hPutStrLn stderr $ "tank: starting daemon on " ++ path
  state <- newDaemonState
  bracket (listenSocket path) (cleanup path) (acceptLoop state)
  where
    cleanup p sock = do
      close sock
      removeFile p

-- | Accept client connections, spawning a handler thread per client
acceptLoop :: DaemonState -> Socket -> IO ()
acceptLoop state sock = do
  (clientSock, _addr) <- accept sock
  hPutStrLn stderr "tank: client connected"
  h <- socketHandle clientSock
  _ <- forkFinally (handleClient state h) (\_ -> do
    hPutStrLn stderr "tank: client disconnected"
    hClose h)
  acceptLoop state sock

-- | Handle a single client connection: read messages, route, respond
handleClient :: DaemonState -> Handle -> IO ()
handleClient state h = do
  result <- readEnvelope h
  case result of
    Left _err -> pure ()  -- EOF or parse error, exit loop (forkFinally will cleanup)
    Right envelope -> do
      actions <- routeMessage state h envelope
      mapM_ (\case
        Reply respMsg -> writeEnvelope h (makeResponse envelope respMsg)
        _ -> pure ()  -- SendTo/Broadcast handled in Task 3
        ) actions
      handleClient state h  -- loop

-- | Build a response envelope from request envelope + response payload
makeResponse :: MessageEnvelope -> Message -> MessageEnvelope
makeResponse req payload = MessageEnvelope
  { meVersion  = meVersion req
  , meSource   = PlugId nil  -- daemon's own ID
  , meTarget   = TargetPlug (meSource req)
  , meSequence = meSequence req + 1
  , mePayload  = payload
  }

-- | Stop the daemon
stopDaemon :: String -> IO ()
stopDaemon name = do
  path <- socketPath name
  -- TODO: send shutdown message to daemon
  hPutStrLn stderr $ "tank: stopping daemon at " ++ path
