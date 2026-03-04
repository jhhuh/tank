module Tank.Daemon.Socket
  ( listenSocket
  , connectSocket
  , socketPath
  ) where

import Network.Socket
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.Posix.User (getEffectiveUserID)

-- | Get the socket path for the tank daemon
socketPath :: String -> IO FilePath
socketPath name = do
  mRuntime <- lookupEnv "XDG_RUNTIME_DIR"
  case mRuntime of
    Just dir -> do
      let tankDir = dir </> "tank"
      createDirectoryIfMissing True tankDir
      pure $ tankDir </> (name ++ ".sock")
    Nothing -> do
      tmp <- getTemporaryDirectory
      uid <- getEffectiveUserID
      let tankDir = tmp </> ("tank-" ++ show uid)
      createDirectoryIfMissing True tankDir
      pure $ tankDir </> (name ++ ".sock")

-- | Create and bind a listening Unix socket
listenSocket :: FilePath -> IO Socket
listenSocket path = do
  sock <- socket AF_UNIX Stream 0
  bind sock (SockAddrUnix path)
  listen sock 5
  pure sock

-- | Connect to an existing daemon Unix socket
connectSocket :: FilePath -> IO Socket
connectSocket path = do
  sock <- socket AF_UNIX Stream 0
  connect sock (SockAddrUnix path)
  pure sock
