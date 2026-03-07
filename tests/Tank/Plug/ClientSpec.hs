{-# LANGUAGE OverloadedStrings #-}
module Tank.Plug.ClientSpec (spec) where

import Test.Hspec
import Control.Concurrent (forkIO, threadDelay, killThread)
import Data.Maybe (isNothing)
import qualified Data.Set as Set
import System.IO.Temp (withSystemTempDirectory)

import Tank.Core.Types (PlugCapability(..))
import Tank.Daemon.Main (startDaemonAt)
import Tank.Plug.Client (connectDaemon, disconnectPlug, pcPlugId)

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
