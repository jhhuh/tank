module Tank.Core.CRDTSpec (spec) where

import Test.Hspec
import Data.UUID (nil)
import Tank.Core.CRDT

rid1 :: ReplicaId
rid1 = ReplicaId nil

spec :: Spec
spec = do
  describe "LWW Register" $ do
    it "keeps the value with higher timestamp" $ do
      let a = mkLWW rid1 10 "old"
          b = mkLWW rid1 20 "new"
      lwwValue (mergeLWW a b) `shouldBe` "new"
      lwwValue (mergeLWW b a) `shouldBe` "new"

    it "is commutative" $ do
      let a = mkLWW rid1 10 "a"
          b = mkLWW rid1 20 "b"
      lwwValue (mergeLWW a b) `shouldBe` lwwValue (mergeLWW b a)

    it "is idempotent" $ do
      let a = mkLWW rid1 10 "a"
      lwwValue (mergeLWW a a) `shouldBe` lwwValue a

  describe "EpochLWW Register" $ do
    it "prefers higher epoch" $ do
      let a = mkEpochLWW rid1 10 1 "old-epoch"
          b = mkEpochLWW rid1 5  2 "new-epoch"
      elwwValue (mergeEpochLWW a b) `shouldBe` "new-epoch"

    it "within same epoch, prefers higher timestamp" $ do
      let a = mkEpochLWW rid1 10 1 "old"
          b = mkEpochLWW rid1 20 1 "new"
      elwwValue (mergeEpochLWW a b) `shouldBe` "new"

    it "detects stale cells" $ do
      let cell = mkEpochLWW rid1 10 1 "content"
      isStale 2 cell `shouldBe` True
      isStale 1 cell `shouldBe` False
      isStale 0 cell `shouldBe` False
