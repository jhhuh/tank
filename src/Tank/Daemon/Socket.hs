module Tank.Daemon.Socket
  ( listenSocket
  , connectSocket
  , socketPath
  , socketHandle
  , readEnvelope
  , writeEnvelope
  ) where

import qualified Capnp.Classes as C
import qualified Capnp.IO as CIO
import Network.Socket (Socket, SockAddr(..), Family(..), SocketType(..), socket, bind, listen, connect, socketToHandle)
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO (Handle, IOMode(..), hSetBinaryMode, hSetBuffering, BufferMode(..))
import System.Posix.User (getEffectiveUserID)

import Tank.Core.Protocol (MessageEnvelope)
import Tank.Core.Wire (toWire, fromWire)
import qualified Tank.Gen.Protocol as CP

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

-- | Convert a Socket to a binary-mode, block-buffered Handle
socketHandle :: Socket -> IO Handle
socketHandle sock = do
  h <- socketToHandle sock ReadWriteMode
  hSetBinaryMode h True
  hSetBuffering h (BlockBuffering Nothing)
  pure h

-- | Read a framed Cap'n Proto message from a Handle, decode to domain type.
-- Throws on EOF or parse error (error handling deferred to client handler).
readEnvelope :: Handle -> IO (Either String MessageEnvelope)
readEnvelope h = do
  parsed <- CIO.hGetParsed h maxBound :: IO (C.Parsed CP.MessageEnvelope)
  pure $ fromWire parsed

-- | Encode a domain MessageEnvelope and write as framed Cap'n Proto.
writeEnvelope :: Handle -> MessageEnvelope -> IO ()
writeEnvelope h env = CIO.hPutParsed h (toWire env)
