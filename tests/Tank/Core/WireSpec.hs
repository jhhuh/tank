{-# LANGUAGE OverloadedStrings #-}
module Tank.Core.WireSpec (spec) where

import qualified Data.Set as Set
import Data.UUID (nil)
import Test.Hspec

import Tank.Core.CRDT (ReplicaId(..))
import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Core.Types (CellId(..), PlugId(..), PlugCapability(..), PlugInfo(..), GridDelta(..), CellUpdate(..), ViewportUpdate(..), EpochUpdate(..), GridSnapshot(..))
import Tank.Core.Wire (toWire, fromWire)
import Tank.Terminal.Grid (GridCell(..), Color(..), defaultAttrs, defaultCell)

-- | Helper: wrap a message in an envelope for round-trip testing.
mkEnvelope :: Message -> MessageEnvelope
mkEnvelope msg = MessageEnvelope
  { meVersion  = 1
  , meSource   = PlugId nil
  , meTarget   = TargetBroadcast
  , meSequence = 42
  , mePayload  = msg
  }

roundTrip :: Message -> Either String MessageEnvelope
roundTrip = fromWire . toWire . mkEnvelope

spec :: Spec
spec = describe "Wire round-trip" $ do
  it "MsgListCells" $ do
    roundTrip MsgListCells `shouldBe` Right (mkEnvelope MsgListCells)

  it "MsgPlugRegister with PlugInfo" $ do
    let pi' = PlugInfo
          { piId           = PlugId nil
          , piName         = "test-plug"
          , piCapabilities = Set.fromList [CapTerminal, CapOperator]
          }
    roundTrip (MsgPlugRegister pi') `shouldBe` Right (mkEnvelope (MsgPlugRegister pi'))

  it "MsgCellCreate" $ do
    let msg = MsgCellCreate (CellId nil) "/tmp/test"
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgCellAttach" $ do
    let msg = MsgCellAttach (CellId nil) (PlugId nil)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgInput" $ do
    let msg = MsgInput (CellId nil) "hello"
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgOutput" $ do
    let msg = MsgOutput (CellId nil) "world"
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgCellDetach" $ do
    let msg = MsgCellDetach (CellId nil) (PlugId nil)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgPlugRegistered" $ do
    let msg = MsgPlugRegistered (PlugId nil)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgPlugDeregister" $ do
    let msg = MsgPlugDeregister (PlugId nil)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgCellDestroy" $ do
    let msg = MsgCellDestroy (CellId nil)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgFetchLines" $ do
    let msg = MsgFetchLines (CellId nil) 10 20
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgFetchLinesResponse" $ do
    let msg = MsgFetchLinesResponse (CellId nil) [(1, "line one"), (2, "line two")]
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgListCellsResponse" $ do
    let msg = MsgListCellsResponse [(CellId nil, "/home/user")]
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "targets: cell and plug" $ do
    let envCell = (mkEnvelope MsgListCells) { meTarget = TargetCell (CellId nil) }
        envPlug = (mkEnvelope MsgListCells) { meTarget = TargetPlug (PlugId nil) }
    fromWire (toWire envCell) `shouldBe` Right envCell
    fromWire (toWire envPlug) `shouldBe` Right envPlug

  it "version narrowing: survives round-trip within Word16 range" $ do
    let env = (mkEnvelope MsgListCells) { meVersion = 255 }
    fromWire (toWire env) `shouldBe` Right env

  it "MsgStateUpdate with DeltaCells" $ do
    let cu = CellUpdate
              { cuAbsLine   = 5
              , cuCol       = 10
              , cuCell      = GridCell 'A' DefaultColor (Color256 1) defaultAttrs
              , cuEpoch     = 0
              , cuTimestamp = 100
              , cuReplicaId = ReplicaId nil
              }
        msg = MsgStateUpdate (CellId nil) (DeltaCells [cu])
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgStateUpdate with DeltaViewport" $ do
    let vu = ViewportUpdate
              { vuAbsLine  = 42
              , vuTimestamp = 200
              , vuReplicaId = ReplicaId nil
              }
        msg = MsgStateUpdate (CellId nil) (DeltaViewport vu)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgStateUpdate with DeltaEpoch" $ do
    let eu = EpochUpdate
              { euEpoch     = 3
              , euTimestamp  = 300
              , euReplicaId  = ReplicaId nil
              }
        msg = MsgStateUpdate (CellId nil) (DeltaEpoch eu)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)

  it "MsgStateUpdate with DeltaSnapshot" $ do
    let cu = CellUpdate
              { cuAbsLine   = 0
              , cuCol       = 0
              , cuCell      = defaultCell
              , cuEpoch     = 1
              , cuTimestamp = 50
              , cuReplicaId = ReplicaId nil
              }
        snap = GridSnapshot
                { gsWidth       = 80
                , gsHeight      = 24
                , gsBufferAbove = 200
                , gsBufferBelow = 100
                , gsViewport    = 0
                , gsEpoch       = 1
                , gsCells       = [cu]
                }
        msg = MsgStateUpdate (CellId nil) (DeltaSnapshot snap)
    roundTrip msg `shouldBe` Right (mkEnvelope msg)
