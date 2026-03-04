{-# LANGUAGE OverloadedStrings #-}

module Tank.Plug.Operator.Tools
  ( readFileTool
  , writeFileTool
  , executeTool
  , grepTool
  ) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (newEmptyMVar, tryPutMVar, takeMVar)
import Control.Exception (SomeException, try)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode(..))
import System.FilePath ((</>), isAbsolute, takeDirectory)
import System.Process (readCreateProcessWithExitCode, proc, CreateProcess(..))

-- | Read a file's contents. Path can be relative to workDir or absolute.
readFileTool :: FilePath -> FilePath -> IO (Either Text Text)
readFileTool workDir path = do
  let fullPath = resolvePath workDir path
  result <- try (TIO.readFile fullPath) :: IO (Either SomeException Text)
  pure $ case result of
    Left err  -> Left $ "Error reading file: " <> T.pack (show err)
    Right txt -> Right txt

-- | Write content to a file, creating parent directories if needed.
writeFileTool :: FilePath -> FilePath -> Text -> IO (Either Text Text)
writeFileTool workDir path content = do
  let fullPath = resolvePath workDir path
  result <- try go :: IO (Either SomeException ())
  pure $ case result of
    Left err -> Left $ "Error writing file: " <> T.pack (show err)
    Right () -> Right $ "File written: " <> T.pack fullPath
  where
    go = do
      let fp = resolvePath workDir path
      createDirectoryIfMissing True (takeDirectory fp)
      TIO.writeFile fp content

-- | Execute a shell command in workDir, capturing stdout+stderr.
-- Times out after 30 seconds.
executeTool :: FilePath -> Text -> IO (Either Text Text)
executeTool workDir command = do
  let cp = (proc "sh" ["-c", T.unpack command]) { cwd = Just workDir }
  doneVar <- newEmptyMVar

  tid <- forkIO $ do
    result <- try (readCreateProcessWithExitCode cp "")
              :: IO (Either SomeException (ExitCode, String, String))
    _ <- tryPutMVar doneVar (Just result)
    pure ()

  _ <- forkIO $ do
    threadDelay (30 * 1000000)
    didPut <- tryPutMVar doneVar Nothing
    if didPut then killThread tid else pure ()

  mResult <- takeMVar doneVar
  pure $ case mResult of
    Nothing -> Left "Command timed out after 30 seconds"
    Just (Left err) -> Left $ "Error running command: " <> T.pack (show err)
    Just (Right (ExitSuccess, out, err)) ->
      Right $ T.pack out <> T.pack err
    Just (Right (ExitFailure code, out, err)) ->
      Right $ T.pack out <> T.pack err <> "\n[exit code: " <> T.pack (show code) <> "]"

-- | Search for a pattern in files under workDir using grep.
grepTool :: FilePath -> Text -> Maybe Text -> IO (Either Text Text)
grepTool workDir pattern mGlob = do
  let args = ["-rn"] ++ globArg ++ ["--", T.unpack pattern, workDir]
      globArg = case mGlob of
        Nothing -> []
        Just g  -> ["--include=" ++ T.unpack g]
      cp = proc "grep" args
  result <- try (readCreateProcessWithExitCode cp "")
            :: IO (Either SomeException (ExitCode, String, String))
  pure $ case result of
    Left err -> Left $ "Error running grep: " <> T.pack (show err)
    Right (ExitSuccess, out, _) -> Right $ T.pack out
    Right (ExitFailure 1, _, _) -> Right ""  -- no matches
    Right (ExitFailure _, _, err) -> Left $ "grep error: " <> T.pack err

-- | Resolve a path relative to workDir, or return absolute path as-is.
resolvePath :: FilePath -> FilePath -> FilePath
resolvePath workDir path
  | isAbsolute path = path
  | otherwise       = workDir </> path
