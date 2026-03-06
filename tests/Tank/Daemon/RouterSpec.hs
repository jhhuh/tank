{-# LANGUAGE OverloadedStrings #-}
module Tank.Daemon.RouterSpec (spec) where

import Test.Hspec
import Data.UUID (nil)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Control.Concurrent.STM

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
    result <- routeMessage ds (mkEnvelope MsgListCells)
    result `shouldBe` Just (MsgListCellsResponse [])

  it "handles MsgPlugRegister" $ do
    ds <- newDaemonState
    let info = PlugInfo (PlugId nil) "test-plug" Set.empty
    result <- routeMessage ds (mkEnvelope (MsgPlugRegister info))
    result `shouldBe` Just (MsgPlugRegistered (PlugId nil))

  it "handles MsgCellCreate" $ do
    ds <- newDaemonState
    let cid = CellId nil
    result <- routeMessage ds (mkEnvelope (MsgCellCreate cid "/tmp"))
    result `shouldBe` Nothing  -- fire-and-forget
    -- Verify cell was created
    cells <- atomically $ readTVar (dsCells ds)
    Map.member cid cells `shouldBe` True

  it "handles MsgCellDestroy" $ do
    ds <- newDaemonState
    let cid = CellId nil
    _ <- routeMessage ds (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds (mkEnvelope (MsgCellDestroy cid))
    cells <- atomically $ readTVar (dsCells ds)
    Map.member cid cells `shouldBe` False

  it "handles MsgCellAttach" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds (mkEnvelope (MsgCellAttach cid pid))
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> Set.member pid (cellPlugs cell) `shouldBe` True

  it "handles MsgCellDetach" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds (mkEnvelope (MsgCellAttach cid pid))
    _ <- routeMessage ds (mkEnvelope (MsgCellDetach cid pid))
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> Set.member pid (cellPlugs cell) `shouldBe` False

  it "lists cells after creating" $ do
    ds <- newDaemonState
    let cid = CellId nil
    _ <- routeMessage ds (mkEnvelope (MsgCellCreate cid "/tmp"))
    result <- routeMessage ds (mkEnvelope MsgListCells)
    result `shouldBe` Just (MsgListCellsResponse [(cid, "/tmp")])

  it "handles MsgPlugDeregister and cleans up cells" $ do
    ds <- newDaemonState
    let cid = CellId nil
        pid = PlugId nil
    _ <- routeMessage ds (mkEnvelope (MsgCellCreate cid "/tmp"))
    _ <- routeMessage ds (mkEnvelope (MsgCellAttach cid pid))
    _ <- routeMessage ds (mkEnvelope (MsgPlugDeregister pid))
    mcell <- atomically $ getCell ds cid
    case mcell of
      Nothing -> expectationFailure "cell not found"
      Just cell -> Set.member pid (cellPlugs cell) `shouldBe` False
