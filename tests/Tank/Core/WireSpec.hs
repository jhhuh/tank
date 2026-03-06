{-# LANGUAGE OverloadedStrings #-}
module Tank.Core.WireSpec (spec) where

import qualified Data.Set as Set
import Data.UUID (nil)
import Test.Hspec

import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Core.Types (CellId(..), PlugId(..), PlugCapability(..), PlugInfo(..))
import Tank.Core.Wire (toWire, fromWire)

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
