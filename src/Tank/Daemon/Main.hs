module Tank.Daemon.Main
  ( startDaemon
  , stopDaemon
  ) where

import Control.Exception (bracket)
import Network.Socket (Socket, accept, close)
import System.Directory (removeFile)
import System.IO (hPutStrLn, stderr)
import Tank.Daemon.Socket (listenSocket, socketPath)
import Tank.Daemon.State (DaemonState, newDaemonState)

-- | Start the tank daemon
startDaemon :: String -> IO ()
startDaemon name = do
  path <- socketPath name
  hPutStrLn stderr $ "tank: starting daemon on " ++ path
  state <- newDaemonState
  bracket (listenSocket path) cleanup (acceptLoop state)
  where
    cleanup sock = do
      close sock
      path <- socketPath name
      removeFile path

-- | Accept client connections
acceptLoop :: DaemonState -> Socket -> IO ()
acceptLoop state sock = do
  (clientSock, _addr) <- accept sock
  hPutStrLn stderr "tank: client connected"
  -- TODO: spawn handler thread for this client
  close clientSock
  acceptLoop state sock

-- | Stop the daemon
stopDaemon :: String -> IO ()
stopDaemon name = do
  path <- socketPath name
  -- TODO: send shutdown message to daemon
  hPutStrLn stderr $ "tank: stopping daemon at " ++ path
