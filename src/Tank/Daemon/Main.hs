{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Tank.Daemon.Main
  ( startDaemon
  , startDaemonAt
  , stopDaemon
  ) where

import Control.Concurrent (forkFinally, threadDelay)
import Control.Concurrent.STM (atomically)
import Control.Exception (bracket, IOException, try)
import Control.Monad (forM_, when)
import Data.UUID (nil)
import qualified Data.Set as Set
import Network.Socket (Socket, accept, close)
import System.Directory (doesFileExist, removeFile)
import System.FilePath (replaceExtension)
import System.IO (Handle, hClose, hPutStrLn, stderr)
import System.Posix.Process (getProcessID)
import System.Posix.Signals (signalProcess, sigTERM)
import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Core.Types (PlugId(..))
import Tank.Daemon.Router (RouteAction(..), routeMessage)
import Tank.Daemon.Socket (listenSocket, socketPath, socketHandle, readEnvelope, writeEnvelope)
import Tank.Daemon.State (DaemonState, PlugConn(..), newDaemonState, lookupPlug, getCellPlugs)

-- | Start the tank daemon
startDaemon :: String -> IO ()
startDaemon name = do
  path <- socketPath name
  startDaemonAt path

-- | Start daemon on a specific socket path (useful for testing)
startDaemonAt :: FilePath -> IO ()
startDaemonAt path = do
  hPutStrLn stderr $ "tank: starting daemon on " ++ path
  let pidPath = replaceExtension path ".pid"
  pid <- getProcessID
  writeFile pidPath (show pid)
  state <- newDaemonState
  bracket (listenSocket path) (cleanup path pidPath) (acceptLoop state)
  where
    cleanup p pp sock = do
      close sock
      removeFile p
      pidExists <- doesFileExist pp
      when pidExists $ removeFile pp

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
      dispatchActions state h envelope actions
      handleClient state h

-- | Dispatch routing actions to the appropriate handles.
dispatchActions :: DaemonState -> Handle -> MessageEnvelope -> [RouteAction] -> IO ()
dispatchActions ds senderH req actions = forM_ actions $ \case
  Reply msg ->
    writeEnvelope senderH (makeResponse req msg)
  SendTo pid msg -> do
    mconn <- atomically $ lookupPlug ds pid
    case mconn of
      Just conn -> safeSend (pcHandle conn) (makeResponse req msg)
      Nothing -> pure ()
  Broadcast cid msg -> do
    plugIds <- atomically $ getCellPlugs ds cid
    forM_ (Set.toList plugIds) $ \pid -> do
      mconn <- atomically $ lookupPlug ds pid
      case mconn of
        Just conn -> safeSend (pcHandle conn) (makeResponse req msg)
        Nothing -> pure ()

-- | Write envelope, silently ignoring write errors (plug may have disconnected).
safeSend :: Handle -> MessageEnvelope -> IO ()
safeSend h env = do
  result <- try (writeEnvelope h env)
  case result of
    Left (_ :: IOException) -> pure ()
    Right () -> pure ()

-- | Build a response envelope from request envelope + response payload
makeResponse :: MessageEnvelope -> Message -> MessageEnvelope
makeResponse req payload = MessageEnvelope
  { meVersion  = meVersion req
  , meSource   = PlugId nil  -- daemon's own ID
  , meTarget   = TargetPlug (meSource req)
  , meSequence = meSequence req + 1
  , mePayload  = payload
  }

-- | Stop the daemon by sending SIGTERM to the daemon process.
-- Reads the PID from the .pid file written by startDaemon.
stopDaemon :: String -> IO ()
stopDaemon name = do
  path <- socketPath name
  let pidPath = replaceExtension path ".pid"
  pidExists <- doesFileExist pidPath
  if not pidExists
    then hPutStrLn stderr "tank: no daemon running (no pid file)"
    else do
      pidStr <- readFile pidPath
      let pid = read pidStr
      hPutStrLn stderr $ "tank: stopping daemon (pid " ++ show pid ++ ")"
      result <- try (signalProcess sigTERM pid) :: IO (Either IOException ())
      case result of
        Left _ -> hPutStrLn stderr "tank: daemon process not found (already stopped?)"
        Right () -> do
          threadDelay 100000  -- 100ms for cleanup
          hPutStrLn stderr "tank: daemon stopped"
