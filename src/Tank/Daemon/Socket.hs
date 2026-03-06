module Tank.Daemon.Socket
  ( listenSocket
  , connectSocket
  , socketPath
  , socketHandle
  , readEnvelope
  , writeEnvelope
  ) where

import qualified Capnp.Bits
import qualified Capnp.Classes as C
import qualified Capnp.IO as CIO
import Control.Exception (IOException, try)
import Network.Socket (Socket, SockAddr(..), Family(..), SocketType(..), socket, bind, listen, connect, socketToHandle)
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO (Handle, IOMode(..), hSetBinaryMode, hSetBuffering, BufferMode(..), hFlush)
import System.Posix.User (getEffectiveUserID)

import Tank.Core.Protocol (MessageEnvelope)
import Tank.Core.Wire (toWire, fromWire)
import qualified Tank.Gen.Protocol as CP

-- | Max Cap'n Proto message size in 64-bit words (~1 MiB).
maxMessageWords :: Capnp.Bits.WordCount
maxMessageWords = 131072

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
-- Returns Left on IO errors (EOF, socket closed) or wire conversion failures.
readEnvelope :: Handle -> IO (Either String MessageEnvelope)
readEnvelope h = do
  result <- try (CIO.hGetParsed h maxMessageWords :: IO (C.Parsed CP.MessageEnvelope))
  case result of
    Left (e :: IOException) -> pure $ Left (show e)
    Right parsed -> pure $ fromWire parsed

-- | Encode a domain MessageEnvelope and write as framed Cap'n Proto.
-- Flushes after writing to ensure the message is sent immediately.
writeEnvelope :: Handle -> MessageEnvelope -> IO ()
writeEnvelope h env = do
  CIO.hPutParsed h (toWire env)
  hFlush h
