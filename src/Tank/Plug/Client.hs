{-# LANGUAGE ScopedTypeVariables #-}
module Tank.Plug.Client
  ( PlugClient(..)
  , connectDaemon
  , sendMsg
  , recvMsg
  , disconnectPlug
  ) where

import Control.Exception (IOException, try)
import Data.Set (Set)
import Data.Text (Text)
import Data.UUID.V4 (nextRandom)
import Network.Socket (Socket)
import System.IO (Handle, hClose)

import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Core.Types (PlugId(..), PlugInfo(..), PlugCapability)
import Tank.Daemon.Socket (connectSocket, socketHandle, readEnvelope, writeEnvelope)

-- | A connected plug client.
data PlugClient = PlugClient
  { pcHandle :: !Handle
  , pcPlugId :: !PlugId
  } deriving (Show)

-- | Connect to the daemon, register as a plug.
-- Returns Nothing if the daemon is not running or registration fails.
connectDaemon :: FilePath -> Text -> Set PlugCapability -> IO (Maybe PlugClient)
connectDaemon sockPath name caps = do
  result <- try (connectSocket sockPath) :: IO (Either IOException Socket)
  case result of
    Left _ -> pure Nothing
    Right sock -> do
      h <- socketHandle sock
      uid <- nextRandom
      let pid = PlugId uid
          info = PlugInfo pid name caps
          env = MessageEnvelope 1 pid TargetBroadcast 1
                  (MsgPlugRegister info)
      writeEnvelope h env
      resp <- readEnvelope h
      case resp of
        Right rEnv | MsgPlugRegistered rpid <- mePayload rEnv, rpid == pid ->
          pure $ Just (PlugClient h pid)
        _ -> do
          hClose h
          pure Nothing

-- | Send a message envelope to the daemon.
sendMsg :: PlugClient -> MessageEnvelope -> IO ()
sendMsg client = writeEnvelope (pcHandle client)

-- | Read a message from the daemon. Returns Left on EOF/error.
recvMsg :: PlugClient -> IO (Either String MessageEnvelope)
recvMsg client = readEnvelope (pcHandle client)

-- | Deregister from the daemon and close the connection.
disconnectPlug :: PlugClient -> IO ()
disconnectPlug client = do
  let env = MessageEnvelope 1 (pcPlugId client) TargetBroadcast 0
              (MsgPlugDeregister (pcPlugId client))
  result <- try (writeEnvelope (pcHandle client) env) :: IO (Either IOException ())
  case result of
    Left _ -> pure ()
    Right () -> pure ()
  hClose (pcHandle client)
