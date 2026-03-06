module Tank.Daemon.SocketSpec (spec) where

import Test.Hspec
import Data.UUID (nil)
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar
import Network.Socket (accept, close)
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)

import Tank.Core.Types (PlugId(..))
import Tank.Core.Protocol
import Tank.Daemon.Socket

spec :: Spec
spec = describe "Socket message framing" $ do
  it "round-trips a MessageEnvelope over Unix socket" $ do
    withSystemTempDirectory "tank-test" $ \dir -> do
      let path = dir ++ "/test.sock"
          env = MessageEnvelope 1 (PlugId nil) TargetBroadcast 42 MsgListCells
      result <- newEmptyMVar
      serverSock <- listenSocket path
      _ <- forkIO $ do
        (clientSock, _) <- accept serverSock
        clientH <- socketHandle clientSock
        msg <- readEnvelope clientH
        putMVar result msg
        hClose clientH
        close serverSock
      clientSock <- connectSocket path
      clientH <- socketHandle clientSock
      writeEnvelope clientH env
      hClose clientH
      received <- takeMVar result
      received `shouldBe` Right env
