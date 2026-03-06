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
module Tank.Gen.Grid where
import qualified Capnp.Repr as R
import qualified Capnp.Repr.Parsed as RP
import qualified Capnp.Basics as Basics
import qualified GHC.OverloadedLabels as OL
import qualified Capnp.GenHelpers as GH
import qualified Capnp.Classes as C
import qualified GHC.Generics as Generics
import qualified Prelude as Std_
import qualified Data.Word as Std_
import qualified Data.Int as Std_
import Prelude ((<$>), (<*>), (>>=))
data Color 
type instance (R.ReprFor Color) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId Color) where
    typeId  = 13557185953406707471
instance (C.TypedStruct Color) where
    numStructWords  = 1
    numStructPtrs  = 1
instance (C.Allocate Color) where
    type AllocHint Color = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc Color (C.Parsed Color))
instance (C.AllocateList Color) where
    type ListAllocHint Color = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc Color (C.Parsed Color))
data instance C.Parsed Color
    = Color 
        {union' :: (C.Parsed (GH.Which Color))}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed Color))
deriving instance (Std_.Eq (C.Parsed Color))
instance (C.Parse Color (C.Parsed Color)) where
    parse raw_ = (Color <$> (C.parse (GH.structUnion raw_)))
instance (C.Marshal Color (C.Parsed Color)) where
    marshalInto raw_ Color{..} = (do
        (C.marshalInto (GH.structUnion raw_) union')
        )
instance (GH.HasUnion Color) where
    unionField  = (GH.dataField 0 0 16 0)
    data RawWhich Color mut_
        = RW_Color'default_ (R.Raw () mut_)
        | RW_Color'index (R.Raw Std_.Word8 mut_)
        | RW_Color'rgb (R.Raw RGB mut_)
        | RW_Color'unknown' Std_.Word16
    internalWhich tag_ struct_ = case tag_ of
        0 ->
            (RW_Color'default_ <$> (GH.readVariant #default_ struct_))
        1 ->
            (RW_Color'index <$> (GH.readVariant #index struct_))
        2 ->
            (RW_Color'rgb <$> (GH.readVariant #rgb struct_))
        _ ->
            (Std_.pure (RW_Color'unknown' tag_))
    data Which Color
instance (GH.HasVariant "default_" GH.Slot Color ()) where
    variantByLabel  = (GH.Variant GH.voidField 0)
instance (GH.HasVariant "index" GH.Slot Color Std_.Word8) where
    variantByLabel  = (GH.Variant (GH.dataField 16 0 8 0) 1)
instance (GH.HasVariant "rgb" GH.Slot Color RGB) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 2)
data instance C.Parsed (GH.Which Color)
    = Color'default_ 
    | Color'index (RP.Parsed Std_.Word8)
    | Color'rgb (RP.Parsed RGB)
    | Color'unknown' Std_.Word16
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed (GH.Which Color)))
deriving instance (Std_.Eq (C.Parsed (GH.Which Color)))
instance (C.Parse (GH.Which Color) (C.Parsed (GH.Which Color))) where
    parse raw_ = (do
        rawWhich_ <- (GH.unionWhich raw_)
        case rawWhich_ of
            (RW_Color'default_ _) ->
                (Std_.pure Color'default_)
            (RW_Color'index rawArg_) ->
                (Color'index <$> (C.parse rawArg_))
            (RW_Color'rgb rawArg_) ->
                (Color'rgb <$> (C.parse rawArg_))
            (RW_Color'unknown' tag_) ->
                (Std_.pure (Color'unknown' tag_))
        )
instance (C.Marshal (GH.Which Color) (C.Parsed (GH.Which Color))) where
    marshalInto raw_ parsed_ = case parsed_ of
        (Color'default_) ->
            (GH.encodeVariant #default_ () (GH.unionStruct raw_))
        (Color'index arg_) ->
            (GH.encodeVariant #index arg_ (GH.unionStruct raw_))
        (Color'rgb arg_) ->
            (GH.encodeVariant #rgb arg_ (GH.unionStruct raw_))
        (Color'unknown' tag_) ->
            (GH.encodeField GH.unionField tag_ (GH.unionStruct raw_))
data RGB 
type instance (R.ReprFor RGB) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId RGB) where
    typeId  = 18110821668609514806
instance (C.TypedStruct RGB) where
    numStructWords  = 1
    numStructPtrs  = 0
instance (C.Allocate RGB) where
    type AllocHint RGB = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc RGB (C.Parsed RGB))
instance (C.AllocateList RGB) where
    type ListAllocHint RGB = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc RGB (C.Parsed RGB))
data instance C.Parsed RGB
    = RGB 
        {r :: (RP.Parsed Std_.Word8)
        ,g :: (RP.Parsed Std_.Word8)
        ,b :: (RP.Parsed Std_.Word8)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed RGB))
deriving instance (Std_.Eq (C.Parsed RGB))
instance (C.Parse RGB (C.Parsed RGB)) where
    parse raw_ = (RGB <$> (GH.parseField #r raw_)
                      <*> (GH.parseField #g raw_)
                      <*> (GH.parseField #b raw_))
instance (C.Marshal RGB (C.Parsed RGB)) where
    marshalInto raw_ RGB{..} = (do
        (GH.encodeField #r r raw_)
        (GH.encodeField #g g raw_)
        (GH.encodeField #b b raw_)
        (Std_.pure ())
        )
instance (GH.HasField "r" GH.Slot RGB Std_.Word8) where
    fieldByLabel  = (GH.dataField 0 0 8 0)
instance (GH.HasField "g" GH.Slot RGB Std_.Word8) where
    fieldByLabel  = (GH.dataField 8 0 8 0)
instance (GH.HasField "b" GH.Slot RGB Std_.Word8) where
    fieldByLabel  = (GH.dataField 16 0 8 0)
data CellAttrs 
type instance (R.ReprFor CellAttrs) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId CellAttrs) where
    typeId  = 17233756958161500482
instance (C.TypedStruct CellAttrs) where
    numStructWords  = 1
    numStructPtrs  = 0
instance (C.Allocate CellAttrs) where
    type AllocHint CellAttrs = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc CellAttrs (C.Parsed CellAttrs))
instance (C.AllocateList CellAttrs) where
    type ListAllocHint CellAttrs = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc CellAttrs (C.Parsed CellAttrs))
data instance C.Parsed CellAttrs
    = CellAttrs 
        {bold :: (RP.Parsed Std_.Bool)
        ,italic :: (RP.Parsed Std_.Bool)
        ,underline :: (RP.Parsed Std_.Bool)
        ,reverse :: (RP.Parsed Std_.Bool)
        ,blink :: (RP.Parsed Std_.Bool)
        ,dim :: (RP.Parsed Std_.Bool)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed CellAttrs))
deriving instance (Std_.Eq (C.Parsed CellAttrs))
instance (C.Parse CellAttrs (C.Parsed CellAttrs)) where
    parse raw_ = (CellAttrs <$> (GH.parseField #bold raw_)
                            <*> (GH.parseField #italic raw_)
                            <*> (GH.parseField #underline raw_)
                            <*> (GH.parseField #reverse raw_)
                            <*> (GH.parseField #blink raw_)
                            <*> (GH.parseField #dim raw_))
instance (C.Marshal CellAttrs (C.Parsed CellAttrs)) where
    marshalInto raw_ CellAttrs{..} = (do
        (GH.encodeField #bold bold raw_)
        (GH.encodeField #italic italic raw_)
        (GH.encodeField #underline underline raw_)
        (GH.encodeField #reverse reverse raw_)
        (GH.encodeField #blink blink raw_)
        (GH.encodeField #dim dim raw_)
        (Std_.pure ())
        )
instance (GH.HasField "bold" GH.Slot CellAttrs Std_.Bool) where
    fieldByLabel  = (GH.dataField 0 0 1 0)
instance (GH.HasField "italic" GH.Slot CellAttrs Std_.Bool) where
    fieldByLabel  = (GH.dataField 1 0 1 0)
instance (GH.HasField "underline" GH.Slot CellAttrs Std_.Bool) where
    fieldByLabel  = (GH.dataField 2 0 1 0)
instance (GH.HasField "reverse" GH.Slot CellAttrs Std_.Bool) where
    fieldByLabel  = (GH.dataField 3 0 1 0)
instance (GH.HasField "blink" GH.Slot CellAttrs Std_.Bool) where
    fieldByLabel  = (GH.dataField 4 0 1 0)
instance (GH.HasField "dim" GH.Slot CellAttrs Std_.Bool) where
    fieldByLabel  = (GH.dataField 5 0 1 0)
data GridCell 
type instance (R.ReprFor GridCell) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId GridCell) where
    typeId  = 9353755163873187240
instance (C.TypedStruct GridCell) where
    numStructWords  = 3
    numStructPtrs  = 4
instance (C.Allocate GridCell) where
    type AllocHint GridCell = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc GridCell (C.Parsed GridCell))
instance (C.AllocateList GridCell) where
    type ListAllocHint GridCell = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc GridCell (C.Parsed GridCell))
data instance C.Parsed GridCell
    = GridCell 
        {codepoint :: (RP.Parsed Std_.Word32)
        ,fg :: (RP.Parsed Color)
        ,bg :: (RP.Parsed Color)
        ,attrs :: (RP.Parsed CellAttrs)
        ,epoch :: (RP.Parsed Std_.Word64)
        ,timestamp :: (RP.Parsed Std_.Word64)
        ,replicaId :: (RP.Parsed Basics.Data)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed GridCell))
deriving instance (Std_.Eq (C.Parsed GridCell))
instance (C.Parse GridCell (C.Parsed GridCell)) where
    parse raw_ = (GridCell <$> (GH.parseField #codepoint raw_)
                           <*> (GH.parseField #fg raw_)
                           <*> (GH.parseField #bg raw_)
                           <*> (GH.parseField #attrs raw_)
                           <*> (GH.parseField #epoch raw_)
                           <*> (GH.parseField #timestamp raw_)
                           <*> (GH.parseField #replicaId raw_))
instance (C.Marshal GridCell (C.Parsed GridCell)) where
    marshalInto raw_ GridCell{..} = (do
        (GH.encodeField #codepoint codepoint raw_)
        (GH.encodeField #fg fg raw_)
        (GH.encodeField #bg bg raw_)
        (GH.encodeField #attrs attrs raw_)
        (GH.encodeField #epoch epoch raw_)
        (GH.encodeField #timestamp timestamp raw_)
        (GH.encodeField #replicaId replicaId raw_)
        (Std_.pure ())
        )
instance (GH.HasField "codepoint" GH.Slot GridCell Std_.Word32) where
    fieldByLabel  = (GH.dataField 0 0 32 0)
instance (GH.HasField "fg" GH.Slot GridCell Color) where
    fieldByLabel  = (GH.ptrField 0)
instance (GH.HasField "bg" GH.Slot GridCell Color) where
    fieldByLabel  = (GH.ptrField 1)
instance (GH.HasField "attrs" GH.Slot GridCell CellAttrs) where
    fieldByLabel  = (GH.ptrField 2)
instance (GH.HasField "epoch" GH.Slot GridCell Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 1 64 0)
instance (GH.HasField "timestamp" GH.Slot GridCell Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 2 64 0)
instance (GH.HasField "replicaId" GH.Slot GridCell Basics.Data) where
    fieldByLabel  = (GH.ptrField 3)
data CellUpdate 
type instance (R.ReprFor CellUpdate) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId CellUpdate) where
    typeId  = 14327242548630636678
instance (C.TypedStruct CellUpdate) where
    numStructWords  = 2
    numStructPtrs  = 1
instance (C.Allocate CellUpdate) where
    type AllocHint CellUpdate = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc CellUpdate (C.Parsed CellUpdate))
instance (C.AllocateList CellUpdate) where
    type ListAllocHint CellUpdate = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc CellUpdate (C.Parsed CellUpdate))
data instance C.Parsed CellUpdate
    = CellUpdate 
        {absLine :: (RP.Parsed Std_.Word64)
        ,col :: (RP.Parsed Std_.Word16)
        ,cell :: (RP.Parsed GridCell)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed CellUpdate))
deriving instance (Std_.Eq (C.Parsed CellUpdate))
instance (C.Parse CellUpdate (C.Parsed CellUpdate)) where
    parse raw_ = (CellUpdate <$> (GH.parseField #absLine raw_)
                             <*> (GH.parseField #col raw_)
                             <*> (GH.parseField #cell raw_))
instance (C.Marshal CellUpdate (C.Parsed CellUpdate)) where
    marshalInto raw_ CellUpdate{..} = (do
        (GH.encodeField #absLine absLine raw_)
        (GH.encodeField #col col raw_)
        (GH.encodeField #cell cell raw_)
        (Std_.pure ())
        )
instance (GH.HasField "absLine" GH.Slot CellUpdate Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 0 64 0)
instance (GH.HasField "col" GH.Slot CellUpdate Std_.Word16) where
    fieldByLabel  = (GH.dataField 0 1 16 0)
instance (GH.HasField "cell" GH.Slot CellUpdate GridCell) where
    fieldByLabel  = (GH.ptrField 0)
data GridDelta 
type instance (R.ReprFor GridDelta) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId GridDelta) where
    typeId  = 10859955936564465065
instance (C.TypedStruct GridDelta) where
    numStructWords  = 1
    numStructPtrs  = 1
instance (C.Allocate GridDelta) where
    type AllocHint GridDelta = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc GridDelta (C.Parsed GridDelta))
instance (C.AllocateList GridDelta) where
    type ListAllocHint GridDelta = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc GridDelta (C.Parsed GridDelta))
data instance C.Parsed GridDelta
    = GridDelta 
        {union' :: (C.Parsed (GH.Which GridDelta))}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed GridDelta))
deriving instance (Std_.Eq (C.Parsed GridDelta))
instance (C.Parse GridDelta (C.Parsed GridDelta)) where
    parse raw_ = (GridDelta <$> (C.parse (GH.structUnion raw_)))
instance (C.Marshal GridDelta (C.Parsed GridDelta)) where
    marshalInto raw_ GridDelta{..} = (do
        (C.marshalInto (GH.structUnion raw_) union')
        )
instance (GH.HasUnion GridDelta) where
    unionField  = (GH.dataField 0 0 16 0)
    data RawWhich GridDelta mut_
        = RW_GridDelta'cells (R.Raw (R.List CellUpdate) mut_)
        | RW_GridDelta'viewport (R.Raw ViewportUpdate mut_)
        | RW_GridDelta'epochUpdate (R.Raw EpochUpdate mut_)
        | RW_GridDelta'snapshot (R.Raw GridSnapshot mut_)
        | RW_GridDelta'unknown' Std_.Word16
    internalWhich tag_ struct_ = case tag_ of
        0 ->
            (RW_GridDelta'cells <$> (GH.readVariant #cells struct_))
        1 ->
            (RW_GridDelta'viewport <$> (GH.readVariant #viewport struct_))
        2 ->
            (RW_GridDelta'epochUpdate <$> (GH.readVariant #epochUpdate struct_))
        3 ->
            (RW_GridDelta'snapshot <$> (GH.readVariant #snapshot struct_))
        _ ->
            (Std_.pure (RW_GridDelta'unknown' tag_))
    data Which GridDelta
instance (GH.HasVariant "cells" GH.Slot GridDelta (R.List CellUpdate)) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 0)
instance (GH.HasVariant "viewport" GH.Slot GridDelta ViewportUpdate) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 1)
instance (GH.HasVariant "epochUpdate" GH.Slot GridDelta EpochUpdate) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 2)
instance (GH.HasVariant "snapshot" GH.Slot GridDelta GridSnapshot) where
    variantByLabel  = (GH.Variant (GH.ptrField 0) 3)
data instance C.Parsed (GH.Which GridDelta)
    = GridDelta'cells (RP.Parsed (R.List CellUpdate))
    | GridDelta'viewport (RP.Parsed ViewportUpdate)
    | GridDelta'epochUpdate (RP.Parsed EpochUpdate)
    | GridDelta'snapshot (RP.Parsed GridSnapshot)
    | GridDelta'unknown' Std_.Word16
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed (GH.Which GridDelta)))
deriving instance (Std_.Eq (C.Parsed (GH.Which GridDelta)))
instance (C.Parse (GH.Which GridDelta) (C.Parsed (GH.Which GridDelta))) where
    parse raw_ = (do
        rawWhich_ <- (GH.unionWhich raw_)
        case rawWhich_ of
            (RW_GridDelta'cells rawArg_) ->
                (GridDelta'cells <$> (C.parse rawArg_))
            (RW_GridDelta'viewport rawArg_) ->
                (GridDelta'viewport <$> (C.parse rawArg_))
            (RW_GridDelta'epochUpdate rawArg_) ->
                (GridDelta'epochUpdate <$> (C.parse rawArg_))
            (RW_GridDelta'snapshot rawArg_) ->
                (GridDelta'snapshot <$> (C.parse rawArg_))
            (RW_GridDelta'unknown' tag_) ->
                (Std_.pure (GridDelta'unknown' tag_))
        )
instance (C.Marshal (GH.Which GridDelta) (C.Parsed (GH.Which GridDelta))) where
    marshalInto raw_ parsed_ = case parsed_ of
        (GridDelta'cells arg_) ->
            (GH.encodeVariant #cells arg_ (GH.unionStruct raw_))
        (GridDelta'viewport arg_) ->
            (GH.encodeVariant #viewport arg_ (GH.unionStruct raw_))
        (GridDelta'epochUpdate arg_) ->
            (GH.encodeVariant #epochUpdate arg_ (GH.unionStruct raw_))
        (GridDelta'snapshot arg_) ->
            (GH.encodeVariant #snapshot arg_ (GH.unionStruct raw_))
        (GridDelta'unknown' tag_) ->
            (GH.encodeField GH.unionField tag_ (GH.unionStruct raw_))
data ViewportUpdate 
type instance (R.ReprFor ViewportUpdate) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId ViewportUpdate) where
    typeId  = 12012633157539630141
instance (C.TypedStruct ViewportUpdate) where
    numStructWords  = 2
    numStructPtrs  = 1
instance (C.Allocate ViewportUpdate) where
    type AllocHint ViewportUpdate = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc ViewportUpdate (C.Parsed ViewportUpdate))
instance (C.AllocateList ViewportUpdate) where
    type ListAllocHint ViewportUpdate = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc ViewportUpdate (C.Parsed ViewportUpdate))
data instance C.Parsed ViewportUpdate
    = ViewportUpdate 
        {absLine :: (RP.Parsed Std_.Word64)
        ,timestamp :: (RP.Parsed Std_.Word64)
        ,replicaId :: (RP.Parsed Basics.Data)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed ViewportUpdate))
deriving instance (Std_.Eq (C.Parsed ViewportUpdate))
instance (C.Parse ViewportUpdate (C.Parsed ViewportUpdate)) where
    parse raw_ = (ViewportUpdate <$> (GH.parseField #absLine raw_)
                                 <*> (GH.parseField #timestamp raw_)
                                 <*> (GH.parseField #replicaId raw_))
instance (C.Marshal ViewportUpdate (C.Parsed ViewportUpdate)) where
    marshalInto raw_ ViewportUpdate{..} = (do
        (GH.encodeField #absLine absLine raw_)
        (GH.encodeField #timestamp timestamp raw_)
        (GH.encodeField #replicaId replicaId raw_)
        (Std_.pure ())
        )
instance (GH.HasField "absLine" GH.Slot ViewportUpdate Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 0 64 0)
instance (GH.HasField "timestamp" GH.Slot ViewportUpdate Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 1 64 0)
instance (GH.HasField "replicaId" GH.Slot ViewportUpdate Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
data EpochUpdate 
type instance (R.ReprFor EpochUpdate) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId EpochUpdate) where
    typeId  = 11661298380870979299
instance (C.TypedStruct EpochUpdate) where
    numStructWords  = 2
    numStructPtrs  = 1
instance (C.Allocate EpochUpdate) where
    type AllocHint EpochUpdate = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc EpochUpdate (C.Parsed EpochUpdate))
instance (C.AllocateList EpochUpdate) where
    type ListAllocHint EpochUpdate = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc EpochUpdate (C.Parsed EpochUpdate))
data instance C.Parsed EpochUpdate
    = EpochUpdate 
        {epoch :: (RP.Parsed Std_.Word64)
        ,timestamp :: (RP.Parsed Std_.Word64)
        ,replicaId :: (RP.Parsed Basics.Data)}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed EpochUpdate))
deriving instance (Std_.Eq (C.Parsed EpochUpdate))
instance (C.Parse EpochUpdate (C.Parsed EpochUpdate)) where
    parse raw_ = (EpochUpdate <$> (GH.parseField #epoch raw_)
                              <*> (GH.parseField #timestamp raw_)
                              <*> (GH.parseField #replicaId raw_))
instance (C.Marshal EpochUpdate (C.Parsed EpochUpdate)) where
    marshalInto raw_ EpochUpdate{..} = (do
        (GH.encodeField #epoch epoch raw_)
        (GH.encodeField #timestamp timestamp raw_)
        (GH.encodeField #replicaId replicaId raw_)
        (Std_.pure ())
        )
instance (GH.HasField "epoch" GH.Slot EpochUpdate Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 0 64 0)
instance (GH.HasField "timestamp" GH.Slot EpochUpdate Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 1 64 0)
instance (GH.HasField "replicaId" GH.Slot EpochUpdate Basics.Data) where
    fieldByLabel  = (GH.ptrField 0)
data GridSnapshot 
type instance (R.ReprFor GridSnapshot) = (R.Ptr (Std_.Just R.Struct))
instance (C.HasTypeId GridSnapshot) where
    typeId  = 17610338283540556925
instance (C.TypedStruct GridSnapshot) where
    numStructWords  = 3
    numStructPtrs  = 1
instance (C.Allocate GridSnapshot) where
    type AllocHint GridSnapshot = ()
    new _ = C.newTypedStruct
instance (C.EstimateAlloc GridSnapshot (C.Parsed GridSnapshot))
instance (C.AllocateList GridSnapshot) where
    type ListAllocHint GridSnapshot = Std_.Int
    newList  = C.newTypedStructList
instance (C.EstimateListAlloc GridSnapshot (C.Parsed GridSnapshot))
data instance C.Parsed GridSnapshot
    = GridSnapshot 
        {width :: (RP.Parsed Std_.Word16)
        ,height :: (RP.Parsed Std_.Word16)
        ,bufferAbove :: (RP.Parsed Std_.Word16)
        ,bufferBelow :: (RP.Parsed Std_.Word16)
        ,viewport :: (RP.Parsed Std_.Word64)
        ,epoch :: (RP.Parsed Std_.Word64)
        ,cells :: (RP.Parsed (R.List CellUpdate))}
    deriving(Generics.Generic)
deriving instance (Std_.Show (C.Parsed GridSnapshot))
deriving instance (Std_.Eq (C.Parsed GridSnapshot))
instance (C.Parse GridSnapshot (C.Parsed GridSnapshot)) where
    parse raw_ = (GridSnapshot <$> (GH.parseField #width raw_)
                               <*> (GH.parseField #height raw_)
                               <*> (GH.parseField #bufferAbove raw_)
                               <*> (GH.parseField #bufferBelow raw_)
                               <*> (GH.parseField #viewport raw_)
                               <*> (GH.parseField #epoch raw_)
                               <*> (GH.parseField #cells raw_))
instance (C.Marshal GridSnapshot (C.Parsed GridSnapshot)) where
    marshalInto raw_ GridSnapshot{..} = (do
        (GH.encodeField #width width raw_)
        (GH.encodeField #height height raw_)
        (GH.encodeField #bufferAbove bufferAbove raw_)
        (GH.encodeField #bufferBelow bufferBelow raw_)
        (GH.encodeField #viewport viewport raw_)
        (GH.encodeField #epoch epoch raw_)
        (GH.encodeField #cells cells raw_)
        (Std_.pure ())
        )
instance (GH.HasField "width" GH.Slot GridSnapshot Std_.Word16) where
    fieldByLabel  = (GH.dataField 0 0 16 0)
instance (GH.HasField "height" GH.Slot GridSnapshot Std_.Word16) where
    fieldByLabel  = (GH.dataField 16 0 16 0)
instance (GH.HasField "bufferAbove" GH.Slot GridSnapshot Std_.Word16) where
    fieldByLabel  = (GH.dataField 32 0 16 0)
instance (GH.HasField "bufferBelow" GH.Slot GridSnapshot Std_.Word16) where
    fieldByLabel  = (GH.dataField 48 0 16 0)
instance (GH.HasField "viewport" GH.Slot GridSnapshot Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 1 64 0)
instance (GH.HasField "epoch" GH.Slot GridSnapshot Std_.Word64) where
    fieldByLabel  = (GH.dataField 0 2 64 0)
instance (GH.HasField "cells" GH.Slot GridSnapshot (R.List CellUpdate)) where
    fieldByLabel  = (GH.ptrField 0)