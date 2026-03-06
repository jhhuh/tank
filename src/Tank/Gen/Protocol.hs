{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE EmptyDataDeriving #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}
{-# OPTIONS_GHC -Wno-dodgy-exports #-}
{-# OPTIONS_GHC -Wno-unused-matches #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-unticked-promoted-constructors #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}
module Tank.Gen.Protocol where
import qualified Capnp.Repr as R
import qualified Capnp.Repr.Parsed as RP
import qualified Capnp.Basics as Basics
import qualified GHC.OverloadedLabels as OL
import qualified Capnp.GenHelpers as GH
import qualified Capnp.Classes as C
import qualified GHC.Generics as Generics
import qualified Tank.Gen.ById.Xa3e8f1b2c4d56789
import qualified Prelude as Std_
import qualified Data.Word as Std_
import qualified Data.Int as Std_
import Prelude ((<$>), (<*>), (>>=))
data MessageEnvelope 
type instance (R.ReprFor MessageEnvelope) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId MessageEnvelope) where
    typeId  = 16961241225333960290
instance (C.TypedStruct MessageEnvelope) where
    numStructWords  = 2
    numStructPtrs  = 3
instance (C.Allocate MessageEnvelope) where
    type AllocHint MessageEnvelope = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc MessageEnvelope (C.Parsed MessageEnvelope))
instance (C.AllocateList MessageEnvelope) where
    type ListAllocHint MessageEnvelope = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc MessageEnvelope (C.Parsed MessageEnvelope))
data instance C.Parsed MessageEnvelope
    = MessageEnvelope 
        {version :: (RP.Parsed Std_.Word16)
        ,sourceId :: (RP.Parsed Basics.Data)
        ,target :: (RP.Parsed Target)
        ,sequence :: (RP.Parsed Std_.Word64)
        ,payload :: (RP.Parsed Message)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed MessageEnvelope))
deriving instance (Std_.Eq (C.Parsed MessageEnvelope))
instance (C.Parse MessageEnvelope (C.Parsed MessageEnvelope)) where
    parse raw_ = (MessageEnvelope <$> (GH.parseField #version raw_)
                                  <*> (GH.parseField #sourceId raw_)
                                  <*> (GH.parseField #target raw_)
                                  <*> (GH.parseField #sequence raw_)
                                  <*> (GH.parseField #payload raw_))
instance (C.Marshal MessageEnvelope (C.Parsed MessageEnvelope)) where
    marshalInto raw_ MessageEnvelope{..} = (do
        (GH.encodeField #version version raw_)
        (GH.encodeField #sourceId sourceId raw_)
        (GH.encodeField #target target raw_)
        (GH.encodeField #sequence sequence raw_)
        (GH.encodeField #payload payload raw_)
        (Std_.pure ())
        )
instance (GH.HasField "version" GH.Slot MessageEnvelope Std_.Word16) where
    fieldByLabel  = (GH.dataField 0 0 16 0)
instance (GH.HasField "sourceId" GH.Slot MessageEnvelope Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "target" GH.Slot MessageEnvelope Target) where
    fieldByLabel  = (GH.ptrField 1)
instance (GH.HasField "sequence" GH.Slot MessageEnvelope Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 1 64 0)
instance (GH.HasField "payload" GH.Slot MessageEnvelope Message) where
    fieldByLabel  = (GH.ptrField 2)
data Target 
type instance (R.ReprFor Target) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId Target) where
    typeId  = 15449841730969850392
instance (C.TypedStruct Target) where
    numStructWords  = 1
    numStructPtrs  = 1
instance (C.Allocate Target) where
    type AllocHint Target = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc Target (C.Parsed Target))
instance (C.AllocateList Target) where
    type ListAllocHint Target = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc Target (C.Parsed Target))
data instance C.Parsed Target
    = Target 
        {union' :: (C.Parsed (GH.Which Target))}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed Target))
deriving instance (Std_.Eq (C.Parsed Target))
instance (C.Parse Target (C.Parsed Target)) where
    parse raw_ = (Target <$> (C.parse (GH.structUnion raw_)))
instance (C.Marshal Target (C.Parsed Target)) where
    marshalInto raw_ Target{..} = (do
        (C.marshalInto (GH.structUnion raw_) union')
        )
instance (GH.HasUnion Target) where
    unionField  = (GH.dataField 0 0 16 0)
    data RawWhich Target mut_
        = RW_Target'cell (R.Raw Basics.Data mut_)
        | RW_Target'plug (R.Raw Basics.Data mut_)
        | RW_Target'broadcast (R.Raw () mut_)
        | RW_Target'unknown' Std_.Word16
    internalWhich tag_ struct_ = case tag_ of
        0 ->
            (RW_Target'cell <$> (GH.readVariant #cell struct_))
        1 ->
            (RW_Target'plug <$> (GH.readVariant #plug struct_))
        2 ->
            (RW_Target'broadcast <$> (GH.readVariant #broadcast struct_))
        _ ->
            (Std_.pure (RW_Target'unknown' tag_))
    data Which Target
instance (GH.HasVariant "cell" GH.Slot Target Basics.Data) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 0)
instance (GH.HasVariant "plug" GH.Slot Target Basics.Data) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 1)
instance (GH.HasVariant "broadcast" GH.Slot Target ()) where
    variantByLabel  = (GH.Variant GH.voidField 2)
data instance C.Parsed (GH.Which Target)
    = Target'cell (RP.Parsed Basics.Data)
    | Target'plug (RP.Parsed Basics.Data)
    | Target'broadcast 
    | Target'unknown' Std_.Word16
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed (GH.Which Target)))
deriving instance (Std_.Eq (C.Parsed (GH.Which Target)))
instance (C.Parse (GH.Which Target) (C.Parsed (GH.Which Target))) where
    parse raw_ = (do
        rawWhich_ <- (GH.unionWhich raw_)
        case rawWhich_ of
            (RW_Target'cell rawArg_) ->
                (Target'cell <$> (C.parse rawArg_))
            (RW_Target'plug rawArg_) ->
                (Target'plug <$> (C.parse rawArg_))
            (RW_Target'broadcast _) ->
                (Std_.pure Target'broadcast)
            (RW_Target'unknown' tag_) ->
                (Std_.pure (Target'unknown' tag_))
        )
instance (C.Marshal (GH.Which Target) (C.Parsed (GH.Which Target))) where
    marshalInto raw_ parsed_ = case parsed_ of
        (Target'cell arg_) ->
            (GH.encodeVariant #cell arg_ (GH.unionStruct raw_))
        (Target'plug arg_) ->
            (GH.encodeVariant #plug arg_ (GH.unionStruct raw_))
        (Target'broadcast) ->
            (GH.encodeVariant #broadcast () (GH.unionStruct raw_))
        (Target'unknown' tag_) ->
            (GH.encodeField GH.unionField tag_ (GH.unionStruct raw_))
data PlugCapabilities 
type instance (R.ReprFor PlugCapabilities) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId PlugCapabilities) where
    typeId  = 16614206261467079352
instance (C.TypedStruct PlugCapabilities) where
    numStructWords  = 1
    numStructPtrs  = 0
instance (C.Allocate PlugCapabilities) where
    type AllocHint PlugCapabilities = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc PlugCapabilities (C.Parsed PlugCapabilities))
instance (C.AllocateList PlugCapabilities) where
    type ListAllocHint PlugCapabilities = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc PlugCapabilities (C.Parsed PlugCapabilities))
data instance C.Parsed PlugCapabilities
    = PlugCapabilities 
        {terminal :: (RP.Parsed Std_.Bool)
        ,operator :: (RP.Parsed Std_.Bool)
        ,devshell :: (RP.Parsed Std_.Bool)
        ,processMgr :: (RP.Parsed Std_.Bool)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed PlugCapabilities))
deriving instance (Std_.Eq (C.Parsed PlugCapabilities))
instance (C.Parse PlugCapabilities (C.Parsed PlugCapabilities)) where
    parse raw_ = (PlugCapabilities <$> (GH.parseField #terminal raw_)
                                   <*> (GH.parseField #operator raw_)
                                   <*> (GH.parseField #devshell raw_)
                                   <*> (GH.parseField #processMgr raw_))
instance (C.Marshal PlugCapabilities (C.Parsed PlugCapabilities)) where
    marshalInto raw_ PlugCapabilities{..} = (do
        (GH.encodeField #terminal terminal raw_)
        (GH.encodeField #operator operator raw_)
        (GH.encodeField #devshell devshell raw_)
        (GH.encodeField #processMgr processMgr raw_)
        (Std_.pure ())
        )
instance (GH.HasField "terminal" GH.Slot PlugCapabilities Std_.Bool) where
    fieldByLabel  = (GH.dataField 0 0 1 0)
instance (GH.HasField "operator" GH.Slot PlugCapabilities Std_.Bool) where
    fieldByLabel  = (GH.dataField 1 0 1 0)
instance (GH.HasField "devshell" GH.Slot PlugCapabilities Std_.Bool) where
    fieldByLabel  = (GH.dataField 2 0 1 0)
instance (GH.HasField "processMgr" GH.Slot PlugCapabilities Std_.Bool) where
    fieldByLabel  = (GH.dataField 3 0 1 0)
data PlugInfo 
type instance (R.ReprFor PlugInfo) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId PlugInfo) where
    typeId  = 10636058856639296524
instance (C.TypedStruct PlugInfo) where
    numStructWords  = 0
    numStructPtrs  = 3
instance (C.Allocate PlugInfo) where
    type AllocHint PlugInfo = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc PlugInfo (C.Parsed PlugInfo))
instance (C.AllocateList PlugInfo) where
    type ListAllocHint PlugInfo = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc PlugInfo (C.Parsed PlugInfo))
data instance C.Parsed PlugInfo
    = PlugInfo 
        {id :: (RP.Parsed Basics.Data)
        ,name :: (RP.Parsed Basics.Text)
        ,capabilities :: (RP.Parsed PlugCapabilities)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed PlugInfo))
deriving instance (Std_.Eq (C.Parsed PlugInfo))
instance (C.Parse PlugInfo (C.Parsed PlugInfo)) where
    parse raw_ = (PlugInfo <$> (GH.parseField #id raw_)
                           <*> (GH.parseField #name raw_)
                           <*> (GH.parseField #capabilities raw_))
instance (C.Marshal PlugInfo (C.Parsed PlugInfo)) where
    marshalInto raw_ PlugInfo{..} = (do
        (GH.encodeField #id id raw_)
        (GH.encodeField #name name raw_)
        (GH.encodeField #capabilities capabilities raw_)
        (Std_.pure ())
        )
instance (GH.HasField "id" GH.Slot PlugInfo Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "name" GH.Slot PlugInfo Basics.Text) where
    fieldByLabel  = (GH.ptrField 1)
instance (GH.HasField "capabilities" GH.Slot PlugInfo PlugCapabilities) where
    fieldByLabel  = (GH.ptrField 2)
data CellInfo 
type instance (R.ReprFor CellInfo) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId CellInfo) where
    typeId  = 11382791798476728113
instance (C.TypedStruct CellInfo) where
    numStructWords  = 0
    numStructPtrs  = 2
instance (C.Allocate CellInfo) where
    type AllocHint CellInfo = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc CellInfo (C.Parsed CellInfo))
instance (C.AllocateList CellInfo) where
    type ListAllocHint CellInfo = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc CellInfo (C.Parsed CellInfo))
data instance C.Parsed CellInfo
    = CellInfo 
        {id :: (RP.Parsed Basics.Data)
        ,directory :: (RP.Parsed Basics.Text)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed CellInfo))
deriving instance (Std_.Eq (C.Parsed CellInfo))
instance (C.Parse CellInfo (C.Parsed CellInfo)) where
    parse raw_ = (CellInfo <$> (GH.parseField #id raw_)
                           <*> (GH.parseField #directory raw_))
instance (C.Marshal CellInfo (C.Parsed CellInfo)) where
    marshalInto raw_ CellInfo{..} = (do
        (GH.encodeField #id id raw_)
        (GH.encodeField #directory directory raw_)
        (Std_.pure ())
        )
instance (GH.HasField "id" GH.Slot CellInfo Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "directory" GH.Slot CellInfo Basics.Text) where
    fieldByLabel  = (GH.ptrField 1)
data Message 
type instance (R.ReprFor Message) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId Message) where
    typeId  = 11832648270090372720
instance (C.TypedStruct Message) where
    numStructWords  = 1
    numStructPtrs  = 1
instance (C.Allocate Message) where
    type AllocHint Message = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc Message (C.Parsed Message))
instance (C.AllocateList Message) where
    type ListAllocHint Message = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc Message (C.Parsed Message))
data instance C.Parsed Message
    = Message 
        {union' :: (C.Parsed (GH.Which Message))}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed Message))
deriving instance (Std_.Eq (C.Parsed Message))
instance (C.Parse Message (C.Parsed Message)) where
    parse raw_ = (Message <$> (C.parse (GH.structUnion raw_)))
instance (C.Marshal Message (C.Parsed Message)) where
    marshalInto raw_ Message{..} = (do
        (C.marshalInto (GH.structUnion raw_) union')
        )
instance (GH.HasUnion Message) where
    unionField  = (GH.dataField 0 0 16 0)
    data RawWhich Message mut_
        = RW_Message'plugRegister (R.Raw PlugInfo mut_)
        | RW_Message'plugRegistered (R.Raw Basics.Data mut_)
        | RW_Message'plugDeregister (R.Raw Basics.Data mut_)
        | RW_Message'cellCreate (R.Raw CellCreate mut_)
        | RW_Message'cellDestroy (R.Raw Basics.Data mut_)
        | RW_Message'cellAttach (R.Raw CellAttach mut_)
        | RW_Message'cellDetach (R.Raw CellDetach mut_)
        | RW_Message'stateUpdate (R.Raw StateUpdate mut_)
        | RW_Message'fetchLines (R.Raw FetchLines mut_)
        | RW_Message'fetchLinesResp (R.Raw FetchLinesResponse mut_)
        | RW_Message'listCells (R.Raw () mut_)
        | RW_Message'listCellsResp (R.Raw (R.List CellInfo) mut_)
        | RW_Message'input (R.Raw TerminalIO mut_)
        | RW_Message'output (R.Raw TerminalIO mut_)
        | RW_Message'error (R.Raw Basics.Text mut_)
        | RW_Message'unknown' Std_.Word16
    internalWhich tag_ struct_ = case tag_ of
        0 ->
            (RW_Message'plugRegister <$> (GH.readVariant #plugRegister struct_))
        1 ->
            (RW_Message'plugRegistered <$> (GH.readVariant #plugRegistered struct_))
        2 ->
            (RW_Message'plugDeregister <$> (GH.readVariant #plugDeregister struct_))
        3 ->
            (RW_Message'cellCreate <$> (GH.readVariant #cellCreate struct_))
        4 ->
            (RW_Message'cellDestroy <$> (GH.readVariant #cellDestroy struct_))
        5 ->
            (RW_Message'cellAttach <$> (GH.readVariant #cellAttach struct_))
        6 ->
            (RW_Message'cellDetach <$> (GH.readVariant #cellDetach struct_))
        7 ->
            (RW_Message'stateUpdate <$> (GH.readVariant #stateUpdate struct_))
        8 ->
            (RW_Message'fetchLines <$> (GH.readVariant #fetchLines struct_))
        9 ->
            (RW_Message'fetchLinesResp <$> (GH.readVariant #fetchLinesResp struct_))
        10 ->
            (RW_Message'listCells <$> (GH.readVariant #listCells struct_))
        11 ->
            (RW_Message'listCellsResp <$> (GH.readVariant #listCellsResp struct_))
        12 ->
            (RW_Message'input <$> (GH.readVariant #input struct_))
        13 ->
            (RW_Message'output <$> (GH.readVariant #output struct_))
        14 ->
            (RW_Message'error <$> (GH.readVariant #error struct_))
        _ ->
            (Std_.pure (RW_Message'unknown' tag_))
    data Which Message
instance (GH.HasVariant "plugRegister" GH.Slot Message PlugInfo) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 0)
instance (GH.HasVariant "plugRegistered" GH.Slot Message Basics.Data) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 1)
instance (GH.HasVariant "plugDeregister" GH.Slot Message Basics.Data) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 2)
instance (GH.HasVariant "cellCreate" GH.Slot Message CellCreate) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 3)
instance (GH.HasVariant "cellDestroy" GH.Slot Message Basics.Data) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 4)
instance (GH.HasVariant "cellAttach" GH.Slot Message CellAttach) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 5)
instance (GH.HasVariant "cellDetach" GH.Slot Message CellDetach) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 6)
instance (GH.HasVariant "stateUpdate" GH.Slot Message StateUpdate) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 7)
instance (GH.HasVariant "fetchLines" GH.Slot Message FetchLines) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 8)
instance (GH.HasVariant "fetchLinesResp" GH.Slot Message FetchLinesResponse) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 9)
instance (GH.HasVariant "listCells" GH.Slot Message ()) where
    variantByLabel  = (GH.Variant GH.voidField 10)
instance (GH.HasVariant "listCellsResp" GH.Slot Message (R.List CellInfo)) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 11)
instance (GH.HasVariant "input" GH.Slot Message TerminalIO) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 12)
instance (GH.HasVariant "output" GH.Slot Message TerminalIO) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 13)
instance (GH.HasVariant "error" GH.Slot Message Basics.Text) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 14)
data instance C.Parsed (GH.Which Message)
    = Message'plugRegister (RP.Parsed PlugInfo)
    | Message'plugRegistered (RP.Parsed Basics.Data)
    | Message'plugDeregister (RP.Parsed Basics.Data)
    | Message'cellCreate (RP.Parsed CellCreate)
    | Message'cellDestroy (RP.Parsed Basics.Data)
    | Message'cellAttach (RP.Parsed CellAttach)
    | Message'cellDetach (RP.Parsed CellDetach)
    | Message'stateUpdate (RP.Parsed StateUpdate)
    | Message'fetchLines (RP.Parsed FetchLines)
    | Message'fetchLinesResp (RP.Parsed FetchLinesResponse)
    | Message'listCells 
    | Message'listCellsResp (RP.Parsed (R.List CellInfo))
    | Message'input (RP.Parsed TerminalIO)
    | Message'output (RP.Parsed TerminalIO)
    | Message'error (RP.Parsed Basics.Text)
    | Message'unknown' Std_.Word16
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed (GH.Which Message)))
deriving instance (Std_.Eq (C.Parsed (GH.Which Message)))
instance (C.Parse (GH.Which Message) (C.Parsed (GH.Which Message))) where
    parse raw_ = (do
        rawWhich_ <- (GH.unionWhich raw_)
        case rawWhich_ of
            (RW_Message'plugRegister rawArg_) ->
                (Message'plugRegister <$> (C.parse rawArg_))
            (RW_Message'plugRegistered rawArg_) ->
                (Message'plugRegistered <$> (C.parse rawArg_))
            (RW_Message'plugDeregister rawArg_) ->
                (Message'plugDeregister <$> (C.parse rawArg_))
            (RW_Message'cellCreate rawArg_) ->
                (Message'cellCreate <$> (C.parse rawArg_))
            (RW_Message'cellDestroy rawArg_) ->
                (Message'cellDestroy <$> (C.parse rawArg_))
            (RW_Message'cellAttach rawArg_) ->
                (Message'cellAttach <$> (C.parse rawArg_))
            (RW_Message'cellDetach rawArg_) ->
                (Message'cellDetach <$> (C.parse rawArg_))
            (RW_Message'stateUpdate rawArg_) ->
                (Message'stateUpdate <$> (C.parse rawArg_))
            (RW_Message'fetchLines rawArg_) ->
                (Message'fetchLines <$> (C.parse rawArg_))
            (RW_Message'fetchLinesResp rawArg_) ->
                (Message'fetchLinesResp <$> (C.parse rawArg_))
            (RW_Message'listCells _) ->
                (Std_.pure Message'listCells)
            (RW_Message'listCellsResp rawArg_) ->
                (Message'listCellsResp <$> (C.parse rawArg_))
            (RW_Message'input rawArg_) ->
                (Message'input <$> (C.parse rawArg_))
            (RW_Message'output rawArg_) ->
                (Message'output <$> (C.parse rawArg_))
            (RW_Message'error rawArg_) ->
                (Message'error <$> (C.parse rawArg_))
            (RW_Message'unknown' tag_) ->
                (Std_.pure (Message'unknown' tag_))
        )
instance (C.Marshal (GH.Which Message) (C.Parsed (GH.Which Message))) where
    marshalInto raw_ parsed_ = case parsed_ of
        (Message'plugRegister arg_) ->
            (GH.encodeVariant #plugRegister arg_ (GH.unionStruct raw_))
        (Message'plugRegistered arg_) ->
            (GH.encodeVariant #plugRegistered arg_ (GH.unionStruct raw_))
        (Message'plugDeregister arg_) ->
            (GH.encodeVariant #plugDeregister arg_ (GH.unionStruct raw_))
        (Message'cellCreate arg_) ->
            (GH.encodeVariant #cellCreate arg_ (GH.unionStruct raw_))
        (Message'cellDestroy arg_) ->
            (GH.encodeVariant #cellDestroy arg_ (GH.unionStruct raw_))
        (Message'cellAttach arg_) ->
            (GH.encodeVariant #cellAttach arg_ (GH.unionStruct raw_))
        (Message'cellDetach arg_) ->
            (GH.encodeVariant #cellDetach arg_ (GH.unionStruct raw_))
        (Message'stateUpdate arg_) ->
            (GH.encodeVariant #stateUpdate arg_ (GH.unionStruct raw_))
        (Message'fetchLines arg_) ->
            (GH.encodeVariant #fetchLines arg_ (GH.unionStruct raw_))
        (Message'fetchLinesResp arg_) ->
            (GH.encodeVariant #fetchLinesResp arg_ (GH.unionStruct raw_))
        (Message'listCells) ->
            (GH.encodeVariant #listCells () (GH.unionStruct raw_))
        (Message'listCellsResp arg_) ->
            (GH.encodeVariant #listCellsResp arg_ (GH.unionStruct raw_))
        (Message'input arg_) ->
            (GH.encodeVariant #input arg_ (GH.unionStruct raw_))
        (Message'output arg_) ->
            (GH.encodeVariant #output arg_ (GH.unionStruct raw_))
        (Message'error arg_) ->
            (GH.encodeVariant #error arg_ (GH.unionStruct raw_))
        (Message'unknown' tag_) ->
            (GH.encodeField GH.unionField tag_ (GH.unionStruct raw_))
data CellCreate 
type instance (R.ReprFor CellCreate) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId CellCreate) where
    typeId  = 10578102169335903908
instance (C.TypedStruct CellCreate) where
    numStructWords  = 0
    numStructPtrs  = 3
instance (C.Allocate CellCreate) where
    type AllocHint CellCreate = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc CellCreate (C.Parsed CellCreate))
instance (C.AllocateList CellCreate) where
    type ListAllocHint CellCreate = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc CellCreate (C.Parsed CellCreate))
data instance C.Parsed CellCreate
    = CellCreate 
        {cellId :: (RP.Parsed Basics.Data)
        ,directory :: (RP.Parsed Basics.Text)
        ,shell :: (RP.Parsed Basics.Text)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed CellCreate))
deriving instance (Std_.Eq (C.Parsed CellCreate))
instance (C.Parse CellCreate (C.Parsed CellCreate)) where
    parse raw_ = (CellCreate <$> (GH.parseField #cellId raw_)
                             <*> (GH.parseField #directory raw_)
                             <*> (GH.parseField #shell raw_))
instance (C.Marshal CellCreate (C.Parsed CellCreate)) where
    marshalInto raw_ CellCreate{..} = (do
        (GH.encodeField #cellId cellId raw_)
        (GH.encodeField #directory directory raw_)
        (GH.encodeField #shell shell raw_)
        (Std_.pure ())
        )
instance (GH.HasField "cellId" GH.Slot CellCreate Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "directory" GH.Slot CellCreate Basics.Text) where
    fieldByLabel  = (GH.ptrField 1)
instance (GH.HasField "shell" GH.Slot CellCreate Basics.Text) where
    fieldByLabel  = (GH.ptrField 2)
data CellAttach 
type instance (R.ReprFor CellAttach) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId CellAttach) where
    typeId  = 13397079483514974707
instance (C.TypedStruct CellAttach) where
    numStructWords  = 0
    numStructPtrs  = 2
instance (C.Allocate CellAttach) where
    type AllocHint CellAttach = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc CellAttach (C.Parsed CellAttach))
instance (C.AllocateList CellAttach) where
    type ListAllocHint CellAttach = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc CellAttach (C.Parsed CellAttach))
data instance C.Parsed CellAttach
    = CellAttach 
        {cellId :: (RP.Parsed Basics.Data)
        ,plugId :: (RP.Parsed Basics.Data)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed CellAttach))
deriving instance (Std_.Eq (C.Parsed CellAttach))
instance (C.Parse CellAttach (C.Parsed CellAttach)) where
    parse raw_ = (CellAttach <$> (GH.parseField #cellId raw_)
                             <*> (GH.parseField #plugId raw_))
instance (C.Marshal CellAttach (C.Parsed CellAttach)) where
    marshalInto raw_ CellAttach{..} = (do
        (GH.encodeField #cellId cellId raw_)
        (GH.encodeField #plugId plugId raw_)
        (Std_.pure ())
        )
instance (GH.HasField "cellId" GH.Slot CellAttach Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "plugId" GH.Slot CellAttach Basics.Data) where
    fieldByLabel  = (GH.ptrField 1)
data CellDetach 
type instance (R.ReprFor CellDetach) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId CellDetach) where
    typeId  = 12580391210944533362
instance (C.TypedStruct CellDetach) where
    numStructWords  = 0
    numStructPtrs  = 2
instance (C.Allocate CellDetach) where
    type AllocHint CellDetach = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc CellDetach (C.Parsed CellDetach))
instance (C.AllocateList CellDetach) where
    type ListAllocHint CellDetach = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc CellDetach (C.Parsed CellDetach))
data instance C.Parsed CellDetach
    = CellDetach 
        {cellId :: (RP.Parsed Basics.Data)
        ,plugId :: (RP.Parsed Basics.Data)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed CellDetach))
deriving instance (Std_.Eq (C.Parsed CellDetach))
instance (C.Parse CellDetach (C.Parsed CellDetach)) where
    parse raw_ = (CellDetach <$> (GH.parseField #cellId raw_)
                             <*> (GH.parseField #plugId raw_))
instance (C.Marshal CellDetach (C.Parsed CellDetach)) where
    marshalInto raw_ CellDetach{..} = (do
        (GH.encodeField #cellId cellId raw_)
        (GH.encodeField #plugId plugId raw_)
        (Std_.pure ())
        )
instance (GH.HasField "cellId" GH.Slot CellDetach Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "plugId" GH.Slot CellDetach Basics.Data) where
    fieldByLabel  = (GH.ptrField 1)
data StateUpdate 
type instance (R.ReprFor StateUpdate) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId StateUpdate) where
    typeId  = 9974176449039351549
instance (C.TypedStruct StateUpdate) where
    numStructWords  = 0
    numStructPtrs  = 2
instance (C.Allocate StateUpdate) where
    type AllocHint StateUpdate = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc StateUpdate (C.Parsed StateUpdate))
instance (C.AllocateList StateUpdate) where
    type ListAllocHint StateUpdate = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc StateUpdate (C.Parsed StateUpdate))
data instance C.Parsed StateUpdate
    = StateUpdate 
        {cellId :: (RP.Parsed Basics.Data)
        ,delta :: (RP.Parsed Tank.Gen.ById.Xa3e8f1b2c4d56789.GridDelta)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed StateUpdate))
deriving instance (Std_.Eq (C.Parsed StateUpdate))
instance (C.Parse StateUpdate (C.Parsed StateUpdate)) where
    parse raw_ = (StateUpdate <$> (GH.parseField #cellId raw_)
                              <*> (GH.parseField #delta raw_))
instance (C.Marshal StateUpdate (C.Parsed StateUpdate)) where
    marshalInto raw_ StateUpdate{..} = (do
        (GH.encodeField #cellId cellId raw_)
        (GH.encodeField #delta delta raw_)
        (Std_.pure ())
        )
instance (GH.HasField "cellId" GH.Slot StateUpdate Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "delta" GH.Slot StateUpdate Tank.Gen.ById.Xa3e8f1b2c4d56789.GridDelta) where
    fieldByLabel  = (GH.ptrField 1)
data FetchLines 
type instance (R.ReprFor FetchLines) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId FetchLines) where
    typeId  = 17894126670690775107
instance (C.TypedStruct FetchLines) where
    numStructWords  = 2
    numStructPtrs  = 1
instance (C.Allocate FetchLines) where
    type AllocHint FetchLines = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc FetchLines (C.Parsed FetchLines))
instance (C.AllocateList FetchLines) where
    type ListAllocHint FetchLines = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc FetchLines (C.Parsed FetchLines))
data instance C.Parsed FetchLines
    = FetchLines 
        {cellId :: (RP.Parsed Basics.Data)
        ,fromLine :: (RP.Parsed Std_.Word64)
        ,toLine :: (RP.Parsed Std_.Word64)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed FetchLines))
deriving instance (Std_.Eq (C.Parsed FetchLines))
instance (C.Parse FetchLines (C.Parsed FetchLines)) where
    parse raw_ = (FetchLines <$> (GH.parseField #cellId raw_)
                             <*> (GH.parseField #fromLine raw_)
                             <*> (GH.parseField #toLine raw_))
instance (C.Marshal FetchLines (C.Parsed FetchLines)) where
    marshalInto raw_ FetchLines{..} = (do
        (GH.encodeField #cellId cellId raw_)
        (GH.encodeField #fromLine fromLine raw_)
        (GH.encodeField #toLine toLine raw_)
        (Std_.pure ())
        )
instance (GH.HasField "cellId" GH.Slot FetchLines Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "fromLine" GH.Slot FetchLines Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 0 64 0)
instance (GH.HasField "toLine" GH.Slot FetchLines Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 1 64 0)
data FetchLinesResponse 
type instance (R.ReprFor FetchLinesResponse) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId FetchLinesResponse) where
    typeId  = 11822359742128803025
instance (C.TypedStruct FetchLinesResponse) where
    numStructWords  = 0
    numStructPtrs  = 2
instance (C.Allocate FetchLinesResponse) where
    type AllocHint FetchLinesResponse = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc FetchLinesResponse (C.Parsed FetchLinesResponse))
instance (C.AllocateList FetchLinesResponse) where
    type ListAllocHint FetchLinesResponse = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc FetchLinesResponse (C.Parsed FetchLinesResponse))
data instance C.Parsed FetchLinesResponse
    = FetchLinesResponse 
        {cellId :: (RP.Parsed Basics.Data)
        ,lines :: (RP.Parsed (R.List ScrollbackLine))}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed FetchLinesResponse))
deriving instance (Std_.Eq (C.Parsed FetchLinesResponse))
instance (C.Parse FetchLinesResponse (C.Parsed FetchLinesResponse)) where
    parse raw_ = (FetchLinesResponse <$> (GH.parseField #cellId raw_)
                                     <*> (GH.parseField #lines raw_))
instance (C.Marshal FetchLinesResponse (C.Parsed FetchLinesResponse)) where
    marshalInto raw_ FetchLinesResponse{..} = (do
        (GH.encodeField #cellId cellId raw_)
        (GH.encodeField #lines lines raw_)
        (Std_.pure ())
        )
instance (GH.HasField "cellId" GH.Slot FetchLinesResponse Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "lines" GH.Slot FetchLinesResponse (R.List ScrollbackLine)) where
    fieldByLabel  = (GH.ptrField 1)
data ScrollbackLine 
type instance (R.ReprFor ScrollbackLine) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId ScrollbackLine) where
    typeId  = 9366825427246951218
instance (C.TypedStruct ScrollbackLine) where
    numStructWords  = 1
    numStructPtrs  = 1
instance (C.Allocate ScrollbackLine) where
    type AllocHint ScrollbackLine = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc ScrollbackLine (C.Parsed ScrollbackLine))
instance (C.AllocateList ScrollbackLine) where
    type ListAllocHint ScrollbackLine = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc ScrollbackLine (C.Parsed ScrollbackLine))
data instance C.Parsed ScrollbackLine
    = ScrollbackLine 
        {absLine :: (RP.Parsed Std_.Word64)
        ,content :: (RP.Parsed Basics.Text)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed ScrollbackLine))
deriving instance (Std_.Eq (C.Parsed ScrollbackLine))
instance (C.Parse ScrollbackLine (C.Parsed ScrollbackLine)) where
    parse raw_ = (ScrollbackLine <$> (GH.parseField #absLine raw_)
                                 <*> (GH.parseField #content raw_))
instance (C.Marshal ScrollbackLine (C.Parsed ScrollbackLine)) where
    marshalInto raw_ ScrollbackLine{..} = (do
        (GH.encodeField #absLine absLine raw_)
        (GH.encodeField #content content raw_)
        (Std_.pure ())
        )
instance (GH.HasField "absLine" GH.Slot ScrollbackLine Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 0 64 0)
instance (GH.HasField "content" GH.Slot ScrollbackLine Basics.Text) where
    fieldByLabel  = (GH.ptrField 0)
data TerminalIO 
type instance (R.ReprFor TerminalIO) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId TerminalIO) where
    typeId  = 12963538626472698212
instance (C.TypedStruct TerminalIO) where
    numStructWords  = 0
    numStructPtrs  = 2
instance (C.Allocate TerminalIO) where
    type AllocHint TerminalIO = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc TerminalIO (C.Parsed TerminalIO))
instance (C.AllocateList TerminalIO) where
    type ListAllocHint TerminalIO = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc TerminalIO (C.Parsed TerminalIO))
data instance C.Parsed TerminalIO
    = TerminalIO 
        {cellId :: (RP.Parsed Basics.Data)
        ,data_ :: (RP.Parsed Basics.Data)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed TerminalIO))
deriving instance (Std_.Eq (C.Parsed TerminalIO))
instance (C.Parse TerminalIO (C.Parsed TerminalIO)) where
    parse raw_ = (TerminalIO <$> (GH.parseField #cellId raw_)
                             <*> (GH.parseField #data_ raw_))
instance (C.Marshal TerminalIO (C.Parsed TerminalIO)) where
    marshalInto raw_ TerminalIO{..} = (do
        (GH.encodeField #cellId cellId raw_)
        (GH.encodeField #data_ data_ raw_)
        (Std_.pure ())
        )
instance (GH.HasField "cellId" GH.Slot TerminalIO Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "data_" GH.Slot TerminalIO Basics.Data) where
    fieldByLabel  = (GH.ptrField 1)