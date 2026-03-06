{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Conversion between domain types and Cap'n Proto parsed types.
module Tank.Core.Wire
  ( toWire
  , fromWire
  ) where

import qualified Capnp.Classes as C
import qualified Capnp.GenHelpers as GH
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.UUID (UUID, toByteString, fromByteString)
import Data.Word (Word16, Word64)

import Tank.Core.Protocol
  ( Message(..)
  , MessageEnvelope(..)
  , Target(..)
  )
import Tank.Core.Types (CellId(..), PlugId(..), PlugCapability(..), PlugInfo(..))
import qualified Tank.Gen.Protocol as W

-- --------------------------------------------------------------------
-- UUID helpers
-- --------------------------------------------------------------------

uuidToBS :: UUID -> ByteString
uuidToBS = LBS.toStrict . toByteString

bsToUUID :: ByteString -> Either String UUID
bsToUUID bs = case fromByteString (LBS.fromStrict bs) of
  Just u  -> Right u
  Nothing -> Left "invalid UUID bytes"

-- --------------------------------------------------------------------
-- toWire
-- --------------------------------------------------------------------

-- | Convert domain envelope to Cap'n Proto parsed envelope.
toWire :: MessageEnvelope -> C.Parsed W.MessageEnvelope
toWire env = mkEnv
  (fromIntegral (meVersion env) :: Word16)
  (uuidToBS (let PlugId u = meSource env in u))
  (targetToWire (meTarget env))
  (meSequence env)
  (messageToWire (mePayload env))

-- Positional constructors to avoid DuplicateRecordFields ambiguity.
-- The Cap'n Proto data family instances have positional fields in declaration order.

mkEnv :: Word16 -> ByteString -> C.Parsed W.Target -> Word64
      -> C.Parsed W.Message -> C.Parsed W.MessageEnvelope
mkEnv ver src tgt sq pay = W.MessageEnvelope ver src tgt sq pay

mkTarget :: C.Parsed (GH.Which W.Target) -> C.Parsed W.Target
mkTarget = W.Target

mkMsg :: C.Parsed (GH.Which W.Message) -> C.Parsed W.Message
mkMsg = W.Message

targetToWire :: Target -> C.Parsed W.Target
targetToWire (TargetCell (CellId u)) = mkTarget (W.Target'cell (uuidToBS u))
targetToWire (TargetPlug (PlugId u)) = mkTarget (W.Target'plug (uuidToBS u))
targetToWire TargetBroadcast         = mkTarget W.Target'broadcast

plugInfoToWire :: PlugInfo -> C.Parsed W.PlugInfo
plugInfoToWire pi' =
  W.PlugInfo
    (uuidToBS (let PlugId u = piId pi' in u))
    (piName pi')
    (capsToWire (piCapabilities pi'))

capsToWire :: Set PlugCapability -> C.Parsed W.PlugCapabilities
capsToWire caps = W.PlugCapabilities
  (Set.member CapTerminal caps)
  (Set.member CapOperator caps)
  (Set.member CapDevshell caps)
  (Set.member CapProcessMgr caps)

messageToWire :: Message -> C.Parsed W.Message
messageToWire = mkMsg . go
  where
    go (MsgPlugRegister pi')          = W.Message'plugRegister (plugInfoToWire pi')
    go (MsgPlugRegistered (PlugId u)) = W.Message'plugRegistered (uuidToBS u)
    go (MsgPlugDeregister (PlugId u)) = W.Message'plugDeregister (uuidToBS u)
    go (MsgCellCreate (CellId u) dir) =
      W.Message'cellCreate (W.CellCreate (uuidToBS u) (T.pack dir) "")
    go (MsgCellDestroy (CellId u))    = W.Message'cellDestroy (uuidToBS u)
    go (MsgCellAttach (CellId cu) (PlugId pu)) =
      W.Message'cellAttach (W.CellAttach (uuidToBS cu) (uuidToBS pu))
    go (MsgCellDetach (CellId cu) (PlugId pu)) =
      W.Message'cellDetach (W.CellDetach (uuidToBS cu) (uuidToBS pu))
    go (MsgStateUpdate _ _) = W.Message'error "stateUpdate not yet supported"
    go (MsgFetchLines (CellId u) from to) =
      W.Message'fetchLines (W.FetchLines (uuidToBS u) from to)
    go (MsgFetchLinesResponse (CellId u) lns) =
      W.Message'fetchLinesResp $ W.FetchLinesResponse (uuidToBS u)
        [ W.ScrollbackLine n c | (n, c) <- lns ]
    go MsgListCells = W.Message'listCells
    go (MsgListCellsResponse cells) =
      W.Message'listCellsResp
        [ W.CellInfo (uuidToBS u) (T.pack dir) | (CellId u, dir) <- cells ]
    go (MsgInput (CellId u) d)  =
      W.Message'input (W.TerminalIO (uuidToBS u) d)
    go (MsgOutput (CellId u) d) =
      W.Message'output (W.TerminalIO (uuidToBS u) d)

-- --------------------------------------------------------------------
-- fromWire
-- --------------------------------------------------------------------

-- | Convert Cap'n Proto parsed envelope to domain envelope.
fromWire :: C.Parsed W.MessageEnvelope -> Either String MessageEnvelope
fromWire (W.MessageEnvelope ver src tgt sq pay) = do
  srcUuid <- bsToUUID src
  tgt'    <- targetFromWire tgt
  pay'    <- messageFromWire pay
  Right MessageEnvelope
    { meVersion  = fromIntegral ver :: Word64
    , meSource   = PlugId srcUuid
    , meTarget   = tgt'
    , meSequence = sq
    , mePayload  = pay'
    }

targetFromWire :: C.Parsed W.Target -> Either String Target
targetFromWire (W.Target u) = case u of
  W.Target'cell bs   -> TargetCell . CellId <$> bsToUUID bs
  W.Target'plug bs   -> TargetPlug . PlugId <$> bsToUUID bs
  W.Target'broadcast -> Right TargetBroadcast
  W.Target'unknown' n -> Left $ "unknown Target variant: " ++ show n

plugInfoFromWire :: C.Parsed W.PlugInfo -> Either String PlugInfo
plugInfoFromWire (W.PlugInfo idBs nm caps) = do
  uid <- bsToUUID idBs
  Right PlugInfo
    { piId           = PlugId uid
    , piName         = nm
    , piCapabilities = capsFromWire caps
    }

capsFromWire :: C.Parsed W.PlugCapabilities -> Set PlugCapability
capsFromWire (W.PlugCapabilities t o d p) = Set.fromList $ concat
  [ [CapTerminal   | t]
  , [CapOperator   | o]
  , [CapDevshell   | d]
  , [CapProcessMgr | p]
  ]

parseCellId :: ByteString -> Either String CellId
parseCellId bs = CellId <$> bsToUUID bs

parsePlugId :: ByteString -> Either String PlugId
parsePlugId bs = PlugId <$> bsToUUID bs

messageFromWire :: C.Parsed W.Message -> Either String Message
messageFromWire (W.Message w) = case w of
  W.Message'plugRegister pi'   -> MsgPlugRegister <$> plugInfoFromWire pi'
  W.Message'plugRegistered bs  -> MsgPlugRegistered <$> parsePlugId bs
  W.Message'plugDeregister bs  -> MsgPlugDeregister <$> parsePlugId bs
  W.Message'cellCreate (W.CellCreate cid dir _shell) -> do
    cid' <- parseCellId cid
    Right $ MsgCellCreate cid' (T.unpack dir)
  W.Message'cellDestroy bs -> MsgCellDestroy <$> parseCellId bs
  W.Message'cellAttach (W.CellAttach cid pid) -> do
    cid' <- parseCellId cid
    pid' <- parsePlugId pid
    Right $ MsgCellAttach cid' pid'
  W.Message'cellDetach (W.CellDetach cid pid) -> do
    cid' <- parseCellId cid
    pid' <- parsePlugId pid
    Right $ MsgCellDetach cid' pid'
  W.Message'stateUpdate _ -> Left "stateUpdate not yet supported"
  W.Message'fetchLines (W.FetchLines cid from to) -> do
    cid' <- parseCellId cid
    Right $ MsgFetchLines cid' from to
  W.Message'fetchLinesResp (W.FetchLinesResponse cid lns) -> do
    cid' <- parseCellId cid
    lns' <- traverse parseScrollbackLine lns
    Right $ MsgFetchLinesResponse cid' lns'
  W.Message'listCells -> Right MsgListCells
  W.Message'listCellsResp cis -> do
    cells <- traverse parseCellInfo cis
    Right $ MsgListCellsResponse cells
  W.Message'input (W.TerminalIO cid d) -> do
    cid' <- parseCellId cid
    Right $ MsgInput cid' d
  W.Message'output (W.TerminalIO cid d) -> do
    cid' <- parseCellId cid
    Right $ MsgOutput cid' d
  W.Message'error _ -> Left "received error message"
  W.Message'unknown' n -> Left $ "unknown Message variant: " ++ show n

parseScrollbackLine :: C.Parsed W.ScrollbackLine -> Either String (Word64, Text)
parseScrollbackLine (W.ScrollbackLine n c) = Right (n, c)

parseCellInfo :: C.Parsed W.CellInfo -> Either String (CellId, FilePath)
parseCellInfo (W.CellInfo idBs dir) = do
  cid <- parseCellId idBs
  Right (cid, T.unpack dir)
