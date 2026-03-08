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
import Data.Char (chr, ord)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.UUID (UUID, toByteString, fromByteString)
import Data.Word (Word16, Word32, Word64)

import Tank.Core.CRDT (ReplicaId(..))
import Tank.Core.Protocol
  ( Message(..)
  , MessageEnvelope(..)
  , Target(..)
  )
import Tank.Core.Types
  ( CellId(..), PlugId(..), PlugCapability(..), PlugInfo(..)
  , GridDelta(..), CellUpdate(..), ViewportUpdate(..), EpochUpdate(..), GridSnapshot(..)
  )
import Tank.Terminal.Grid (GridCell(..), Color(..), CellAttrs(..))
import qualified Tank.Gen.Grid as G
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

colorToWire :: Color -> C.Parsed G.Color
colorToWire DefaultColor      = G.Color G.Color'default_
colorToWire (Color256 n)      = G.Color (G.Color'index (fromIntegral n))
colorToWire (ColorRGB r g b)  = G.Color (G.Color'rgb (G.RGB (fromIntegral r) (fromIntegral g) (fromIntegral b)))

cellAttrsToWire :: CellAttrs -> C.Parsed G.CellAttrs
cellAttrsToWire a = G.CellAttrs
  (attrBold a) (attrItalic a) (attrUnderline a)
  (attrReverse a) (attrBlink a) (attrDim a)

gridCellToWire :: GridCell -> Word64 -> Word64 -> ReplicaId -> C.Parsed G.GridCell
gridCellToWire gc epoch ts (ReplicaId rid) = G.GridCell
  (fromIntegral (ord (gcCodepoint gc)) :: Word32)
  (colorToWire (gcFg gc))
  (colorToWire (gcBg gc))
  (cellAttrsToWire (gcAttrs gc))
  epoch
  ts
  (uuidToBS rid)

cellUpdateToWire :: CellUpdate -> C.Parsed G.CellUpdate
cellUpdateToWire cu = G.CellUpdate
  (cuAbsLine cu)
  (fromIntegral (cuCol cu) :: Word16)
  (gridCellToWire (cuCell cu) (cuEpoch cu) (cuTimestamp cu) (cuReplicaId cu))

gridDeltaToWire :: GridDelta -> C.Parsed G.GridDelta
gridDeltaToWire (DeltaCells cus) =
  G.GridDelta (G.GridDelta'cells (map cellUpdateToWire cus))
gridDeltaToWire (DeltaViewport vu) =
  G.GridDelta (G.GridDelta'viewport (viewportUpdateToWire vu))
gridDeltaToWire (DeltaEpoch eu) =
  G.GridDelta (G.GridDelta'epochUpdate (epochUpdateToWire eu))
gridDeltaToWire (DeltaSnapshot snap) =
  G.GridDelta (G.GridDelta'snapshot (gridSnapshotToWire snap))

viewportUpdateToWire :: ViewportUpdate -> C.Parsed G.ViewportUpdate
viewportUpdateToWire vu = G.ViewportUpdate
  (vuAbsLine vu) (vuTimestamp vu) (uuidToBS (let ReplicaId u = vuReplicaId vu in u))

epochUpdateToWire :: EpochUpdate -> C.Parsed G.EpochUpdate
epochUpdateToWire eu = G.EpochUpdate
  (euEpoch eu) (euTimestamp eu) (uuidToBS (let ReplicaId u = euReplicaId eu in u))

gridSnapshotToWire :: GridSnapshot -> C.Parsed G.GridSnapshot
gridSnapshotToWire gs = G.GridSnapshot
  (fromIntegral (gsWidth gs) :: Word16)
  (fromIntegral (gsHeight gs) :: Word16)
  (fromIntegral (gsBufferAbove gs) :: Word16)
  (fromIntegral (gsBufferBelow gs) :: Word16)
  (gsViewport gs)
  (gsEpoch gs)
  (map cellUpdateToWire (gsCells gs))

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
    go (MsgStateUpdate cid delta) =
      W.Message'stateUpdate (W.StateUpdate (uuidToBS (let CellId u = cid in u)) (gridDeltaToWire delta))
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

colorFromWire :: C.Parsed G.Color -> Either String Color
colorFromWire (G.Color w) = case w of
  G.Color'default_  -> Right DefaultColor
  G.Color'index n   -> Right (Color256 (fromIntegral n))
  G.Color'rgb (G.RGB r g b) -> Right (ColorRGB (fromIntegral r) (fromIntegral g) (fromIntegral b))
  G.Color'unknown' n -> Left $ "unknown Color variant: " ++ show n

cellAttrsFromWire :: C.Parsed G.CellAttrs -> CellAttrs
cellAttrsFromWire (G.CellAttrs bo it ul rv bl di) =
  CellAttrs bo it ul rv bl di

gridCellFromWire :: C.Parsed G.GridCell -> Either String (GridCell, Word64, Word64, ReplicaId)
gridCellFromWire (G.GridCell cp fg bg attrs epoch ts ridBs) = do
  fg' <- colorFromWire fg
  bg' <- colorFromWire bg
  rid <- ReplicaId <$> bsToUUID ridBs
  let cell = GridCell (chr (fromIntegral cp)) fg' bg' (cellAttrsFromWire attrs)
  Right (cell, epoch, ts, rid)

cellUpdateFromWire :: C.Parsed G.CellUpdate -> Either String CellUpdate
cellUpdateFromWire (G.CellUpdate absLn col gcW) = do
  (cell, epoch, ts, rid) <- gridCellFromWire gcW
  Right CellUpdate
    { cuAbsLine   = absLn
    , cuCol       = fromIntegral col
    , cuCell      = cell
    , cuEpoch     = epoch
    , cuTimestamp = ts
    , cuReplicaId = rid
    }

viewportUpdateFromWire :: C.Parsed G.ViewportUpdate -> Either String ViewportUpdate
viewportUpdateFromWire (G.ViewportUpdate absLn ts ridBs) = do
  rid <- ReplicaId <$> bsToUUID ridBs
  Right ViewportUpdate { vuAbsLine = absLn, vuTimestamp = ts, vuReplicaId = rid }

epochUpdateFromWire :: C.Parsed G.EpochUpdate -> Either String EpochUpdate
epochUpdateFromWire (G.EpochUpdate ep ts ridBs) = do
  rid <- ReplicaId <$> bsToUUID ridBs
  Right EpochUpdate { euEpoch = ep, euTimestamp = ts, euReplicaId = rid }

gridSnapshotFromWire :: C.Parsed G.GridSnapshot -> Either String GridSnapshot
gridSnapshotFromWire (G.GridSnapshot w h ba bb vp ep cells) = do
  cells' <- traverse cellUpdateFromWire cells
  Right GridSnapshot
    { gsWidth       = fromIntegral w
    , gsHeight      = fromIntegral h
    , gsBufferAbove = fromIntegral ba
    , gsBufferBelow = fromIntegral bb
    , gsViewport    = vp
    , gsEpoch       = ep
    , gsCells       = cells'
    }

gridDeltaFromWire :: C.Parsed G.GridDelta -> Either String GridDelta
gridDeltaFromWire (G.GridDelta w) = case w of
  G.GridDelta'cells cus     -> DeltaCells <$> traverse cellUpdateFromWire cus
  G.GridDelta'viewport vu   -> DeltaViewport <$> viewportUpdateFromWire vu
  G.GridDelta'epochUpdate eu -> DeltaEpoch <$> epochUpdateFromWire eu
  G.GridDelta'snapshot snap -> DeltaSnapshot <$> gridSnapshotFromWire snap
  G.GridDelta'unknown' n    -> Left $ "unknown GridDelta variant: " ++ show n

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
  W.Message'stateUpdate (W.StateUpdate cidBs deltaW) -> do
    cid <- parseCellId cidBs
    delta <- gridDeltaFromWire deltaW
    Right $ MsgStateUpdate cid delta
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
