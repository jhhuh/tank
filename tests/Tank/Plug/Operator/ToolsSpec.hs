{-# LANGUAGE OverloadedStrings #-}

module Tank.Plug.Operator.ToolsSpec (spec) where

import Data.Either (isLeft, isRight)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import Tank.Plug.Operator.Tools

spec :: Spec
spec = do
  describe "readFileTool" $ do
    it "reads an existing file" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      let fp = tmp </> "hello.txt"
      TIO.writeFile fp "hello world"
      result <- readFileTool tmp "hello.txt"
      result `shouldBe` Right "hello world"

    it "reads a file with absolute path" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      let fp = tmp </> "abs.txt"
      TIO.writeFile fp "absolute"
      result <- readFileTool "/nowhere" fp
      result `shouldBe` Right "absolute"

    it "returns error for nonexistent file" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      result <- readFileTool tmp "nonexistent.txt"
      result `shouldSatisfy` isLeft

  describe "writeFileTool" $ do
    it "creates a file with content" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      result <- writeFileTool tmp "out.txt" "some content"
      result `shouldSatisfy` isRight
      content <- TIO.readFile (tmp </> "out.txt")
      content `shouldBe` "some content"

    it "creates parent directories" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      result <- writeFileTool tmp "a/b/c/deep.txt" "deep"
      result `shouldSatisfy` isRight
      content <- TIO.readFile (tmp </> "a" </> "b" </> "c" </> "deep.txt")
      content `shouldBe` "deep"

    it "returns the written path in success message" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      result <- writeFileTool tmp "msg.txt" ""
      case result of
        Right msg -> msg `shouldSatisfy` T.isInfixOf "msg.txt"
        Left _    -> expectationFailure "expected Right"

  describe "executeTool" $ do
    it "captures stdout from echo" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      result <- executeTool tmp "echo hello"
      case result of
        Right out -> out `shouldSatisfy` T.isInfixOf "hello"
        Left err  -> expectationFailure $ "expected Right, got: " ++ T.unpack err

    it "handles a failing command" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      result <- executeTool tmp "exit 42"
      case result of
        Right out -> out `shouldSatisfy` T.isInfixOf "[exit code: 42]"
        Left err  -> expectationFailure $ "expected Right with exit code, got Left: " ++ T.unpack err

    it "captures stderr" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      result <- executeTool tmp "echo oops >&2"
      case result of
        Right out -> out `shouldSatisfy` T.isInfixOf "oops"
        Left err  -> expectationFailure $ "expected Right, got: " ++ T.unpack err

  describe "grepTool" $ do
    it "finds a pattern in a file" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      TIO.writeFile (tmp </> "data.txt") "foo bar\nbaz quux\nfoo again"
      result <- grepTool tmp "foo" Nothing
      case result of
        Right out -> do
          out `shouldSatisfy` T.isInfixOf "foo bar"
          out `shouldSatisfy` T.isInfixOf "foo again"
        Left err -> expectationFailure $ "expected Right, got: " ++ T.unpack err

    it "returns empty for no matches" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      TIO.writeFile (tmp </> "data.txt") "nothing here"
      result <- grepTool tmp "zzzzz" Nothing
      result `shouldBe` Right ""

    it "filters by glob pattern" $ withSystemTempDirectory "tools-test" $ \tmp -> do
      TIO.writeFile (tmp </> "match.hs") "target line"
      TIO.writeFile (tmp </> "skip.txt") "target line"
      result <- grepTool tmp "target" (Just "*.hs")
      case result of
        Right out -> do
          out `shouldSatisfy` T.isInfixOf "match.hs"
          out `shouldSatisfy` (not . T.isInfixOf "skip.txt")
        Left err -> expectationFailure $ "expected Right, got: " ++ T.unpack err
