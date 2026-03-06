{-# LANGUAGE OverloadedStrings #-}
module Tank.Daemon.IntegrationSpec (spec) where

import Test.Hspec
import Control.Concurrent (forkIO, threadDelay, killThread)
import Data.UUID (nil)
import qualified Data.Set as Set
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)

import Tank.Core.Types (CellId(..), PlugId(..), PlugInfo(..))
import Tank.Core.Protocol
import Tank.Daemon.Main (startDaemonAt)
import Tank.Daemon.Socket (connectSocket, socketHandle, readEnvelope, writeEnvelope)

spec :: Spec
spec = describe "Daemon integration" $ do
  it "client can register, create cell, and list cells" $ do
    withSystemTempDirectory "tank-int" $ \dir -> do
      let sockPath = dir ++ "/test.sock"

      -- Start daemon in background
      daemonThread <- forkIO $ startDaemonAt sockPath

      -- Wait for socket to appear
      threadDelay 200000  -- 200ms

      -- Connect client
      clientSock <- connectSocket sockPath
      h <- socketHandle clientSock

      -- Register as plug
      let pid = PlugId nil
          regMsg = MessageEnvelope 1 pid TargetBroadcast 1
                     (MsgPlugRegister (PlugInfo pid "test" Set.empty))
      writeEnvelope h regMsg
      resp1 <- readEnvelope h
      case resp1 of
        Right env -> mePayload env `shouldBe` MsgPlugRegistered pid
        Left err  -> expectationFailure $ "register failed: " ++ err

      -- Create cell (fire-and-forget, no response expected)
      let cid = CellId nil
          createMsg = MessageEnvelope 1 pid TargetBroadcast 2
                        (MsgCellCreate cid "/tmp")
      writeEnvelope h createMsg

      -- Small delay to ensure cell is created before listing
      threadDelay 50000  -- 50ms

      -- List cells
      let listMsg = MessageEnvelope 1 pid TargetBroadcast 3 MsgListCells
      writeEnvelope h listMsg
      resp2 <- readEnvelope h
      case resp2 of
        Right env -> mePayload env `shouldBe` MsgListCellsResponse [(cid, "/tmp")]
        Left err  -> expectationFailure $ "listCells failed: " ++ err

      -- Cleanup
      hClose h
      killThread daemonThread
