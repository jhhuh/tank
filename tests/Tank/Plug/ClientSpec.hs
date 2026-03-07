{-# LANGUAGE OverloadedStrings #-}
module Tank.Plug.ClientSpec (spec) where

import Test.Hspec
import Control.Concurrent (forkIO, threadDelay, killThread)
import Data.Maybe (isNothing)
import qualified Data.Set as Set
import Data.UUID.V4 (nextRandom)
import System.IO.Temp (withSystemTempDirectory)

import Tank.Core.Types (CellId(..), PlugCapability(..))
import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Daemon.Main (startDaemonAt)
import Tank.Plug.Client (connectDaemon, sendMsg, recvMsg, disconnectPlug, pcPlugId)

spec :: Spec
spec = describe "Plug.Client" $ do
  it "connects to daemon and registers plug" $ do
    withSystemTempDirectory "tank-client" $ \dir -> do
      let sockPath = dir ++ "/test.sock"
      daemonThread <- forkIO $ startDaemonAt sockPath
      threadDelay 200000

      result <- connectDaemon sockPath "terminal" (Set.singleton CapTerminal)
      case result of
        Nothing -> expectationFailure "connectDaemon returned Nothing"
        Just client -> do
          let _pid = pcPlugId client
          disconnectPlug client

      killThread daemonThread

  it "returns Nothing when daemon is not running" $ do
    withSystemTempDirectory "tank-client" $ \dir -> do
      let sockPath = dir ++ "/nonexistent.sock"
      result <- connectDaemon sockPath "terminal" (Set.singleton CapTerminal)
      result `shouldSatisfy` isNothing

  it "client creates cell and broadcasts output to second client" $ do
    withSystemTempDirectory "tank-client" $ \dir -> do
      let sockPath = dir ++ "/test.sock"
      daemonThread <- forkIO $ startDaemonAt sockPath
      threadDelay 200000

      -- Connect terminal plug (client 1)
      Just client1 <- connectDaemon sockPath "terminal" (Set.singleton CapTerminal)

      -- Connect observer plug (client 2)
      Just client2 <- connectDaemon sockPath "observer" Set.empty

      let pid1 = pcPlugId client1
          pid2 = pcPlugId client2

      -- Client 1 creates a cell
      cuid <- nextRandom
      let cid = CellId cuid
      sendMsg client1 $ MessageEnvelope 1 pid1 TargetBroadcast 0
        (MsgCellCreate cid "/tmp")
      threadDelay 50000

      -- Both attach
      sendMsg client1 $ MessageEnvelope 1 pid1 TargetBroadcast 0
        (MsgCellAttach cid pid1)
      sendMsg client2 $ MessageEnvelope 1 pid2 TargetBroadcast 0
        (MsgCellAttach cid pid2)
      threadDelay 50000

      -- Client 1 sends output
      sendMsg client1 $ MessageEnvelope 1 pid1 TargetBroadcast 0
        (MsgOutput cid "hello world")

      -- Both should receive broadcast
      resp1 <- recvMsg client1
      case resp1 of
        Right env -> mePayload env `shouldBe` MsgOutput cid "hello world"
        Left err  -> expectationFailure $ "client1 broadcast failed: " ++ err

      resp2 <- recvMsg client2
      case resp2 of
        Right env -> mePayload env `shouldBe` MsgOutput cid "hello world"
        Left err  -> expectationFailure $ "client2 broadcast failed: " ++ err

      disconnectPlug client1
      disconnectPlug client2
      killThread daemonThread
