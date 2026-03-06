{-# LANGUAGE OverloadedStrings #-}
module Tank.Daemon.IntegrationSpec (spec) where

import Test.Hspec
import Control.Concurrent (forkIO, threadDelay, killThread)
import Data.UUID (nil)
import Data.UUID.V4 (nextRandom)
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

  it "broadcasts MsgOutput to attached plugs" $ do
    withSystemTempDirectory "tank-int" $ \dir -> do
      let sockPath = dir ++ "/test.sock"

      daemonThread <- forkIO $ startDaemonAt sockPath
      threadDelay 200000

      -- Connect two clients
      sock1 <- connectSocket sockPath
      h1 <- socketHandle sock1
      sock2 <- connectSocket sockPath
      h2 <- socketHandle sock2

      -- Generate unique plug IDs
      uid1 <- nextRandom
      uid2 <- nextRandom
      let pid1 = PlugId uid1
          pid2 = PlugId uid2
          cid = CellId nil

      -- Register plug 1
      writeEnvelope h1 $ MessageEnvelope 1 pid1 TargetBroadcast 1
        (MsgPlugRegister (PlugInfo pid1 "plug1" Set.empty))
      resp1 <- readEnvelope h1
      case resp1 of
        Right env -> mePayload env `shouldBe` MsgPlugRegistered pid1
        Left err  -> expectationFailure $ "plug1 register failed: " ++ err

      -- Register plug 2
      writeEnvelope h2 $ MessageEnvelope 1 pid2 TargetBroadcast 1
        (MsgPlugRegister (PlugInfo pid2 "plug2" Set.empty))
      resp2 <- readEnvelope h2
      case resp2 of
        Right env -> mePayload env `shouldBe` MsgPlugRegistered pid2
        Left err  -> expectationFailure $ "plug2 register failed: " ++ err

      -- Plug 1 creates cell
      writeEnvelope h1 $ MessageEnvelope 1 pid1 TargetBroadcast 2
        (MsgCellCreate cid "/tmp")
      threadDelay 50000

      -- Both attach to cell
      writeEnvelope h1 $ MessageEnvelope 1 pid1 TargetBroadcast 3
        (MsgCellAttach cid pid1)
      threadDelay 50000
      writeEnvelope h2 $ MessageEnvelope 1 pid2 TargetBroadcast 3
        (MsgCellAttach cid pid2)
      threadDelay 50000

      -- Plug 1 sends MsgOutput
      writeEnvelope h1 $ MessageEnvelope 1 pid1 TargetBroadcast 4
        (MsgOutput cid "hello from plug1")

      -- Both should receive broadcast
      resp3 <- readEnvelope h1
      case resp3 of
        Right env -> mePayload env `shouldBe` MsgOutput cid "hello from plug1"
        Left err  -> expectationFailure $ "plug1 broadcast failed: " ++ err

      resp4 <- readEnvelope h2
      case resp4 of
        Right env -> mePayload env `shouldBe` MsgOutput cid "hello from plug1"
        Left err  -> expectationFailure $ "plug2 broadcast failed: " ++ err

      hClose h1
      hClose h2
      killThread daemonThread
