{-# LANGUAGE OverloadedStrings #-}
module Tank.Daemon.RouterSpec (spec) where

import Test.Hspec
import Data.UUID (nil)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Control.Concurrent.STM
import System.IO (stdin)

import Tank.Core.CRDT (ReplicaId(..))
import Tank.Core.Types
import Tank.Core.Protocol
import Tank.Daemon.State
import Tank.Daemon.Router

mkEnvelope :: Message -> MessageEnvelope
mkEnvelope = MessageEnvelope 1 (PlugId nil) TargetBroadcast 1

spec :: Spec
spec = describe "Router" $ do
  it "handles MsgListCells with empty state" $ do
    ds <- newDaemonState
    result <- routeMessage ds stdin (mkEnvelope MsgListCells)
    result `shouldBe` [Reply (MsgListCellsResponse [])]

  it "handles MsgPlugRegister and stores plug" $ do
    ds <- newDaemonState
    let info = PlugInfo (PlugId nil) "test-plug" Set.empty
    result <- routeMessage ds stdin (mkEnvelope (MsgPlugRegister info))
    result `shouldBe` [Reply (MsgPlugRegistered (PlugId nil))]
    plugs <- atomically $ readTVar (dsPlugs ds)
    Map.member (PlugId nil) plugs `shouldBe` True

  it "handles MsgCellCreate with PTY owner" $ do
    ds <- newDaemonState
    let cid = CellId nil
    result <- routeMessage ds stdin (mkEnvelope (MsgCellCreate cid "/tmp"))
    result `shouldBe` []
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> cellPtyOwner cell `shouldBe` Just (PlugId nil)

  it "handles MsgCellDestroy" $ do
    ds <- newDaemonState
    let cid = CellId nil
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellDestroy cid))
    cells <- atomically $ readTVar (dsCells ds)
    Map.member cid cells `shouldBe` False

  it "handles MsgCellAttach" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellAttach cid pid))
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> Set.member pid (cellPlugs cell) `shouldBe` True

  it "handles MsgCellDetach" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellAttach cid pid))
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellDetach cid pid))
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> Set.member pid (cellPlugs cell) `shouldBe` False

  it "lists cells after creating" $ do
    ds <- newDaemonState
    let cid = CellId nil
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellCreate cid "/tmp"))
    result <- routeMessage ds stdin (mkEnvelope MsgListCells)
    result `shouldBe` [Reply (MsgListCellsResponse [(cid, "/tmp")])]

  it "handles MsgPlugDeregister and cleans up cells" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellAttach cid pid))
    _ <- routeMessage ds stdin (mkEnvelope (MsgPlugDeregister pid))
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> Set.member pid (cellPlugs cell) `shouldBe` False

  it "routes MsgInput to PTY owner" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds stdin (mkEnvelope (MsgCellCreate cid "/tmp"))
    result <- routeMessage ds stdin (mkEnvelope (MsgInput cid "hello"))
    result `shouldBe` [SendTo pid (MsgInput cid "hello")]

  it "routes MsgOutput as broadcast" $ do
    ds <- newDaemonState
    let cid = CellId nil
    result <- routeMessage ds stdin (mkEnvelope (MsgOutput cid "data"))
    result `shouldBe` [Broadcast cid (MsgOutput cid "data")]

  it "returns empty for MsgInput to nonexistent cell" $ do
    ds <- newDaemonState
    let cid = CellId nil
    result <- routeMessage ds stdin (mkEnvelope (MsgInput cid "hello"))
    result `shouldBe` []

  it "routes MsgStateUpdate as broadcast" $ do
    ds <- newDaemonState
    let cid = CellId nil
        delta = DeltaViewport (ViewportUpdate 10 100 (ReplicaId nil))
    result <- routeMessage ds stdin (mkEnvelope (MsgStateUpdate cid delta))
    result `shouldBe` [Broadcast cid (MsgStateUpdate cid delta)]
