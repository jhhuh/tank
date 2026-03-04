{-# LANGUAGE OverloadedStrings #-}

-- Minimal PTY terminal — debug version with polling instead of threadWaitRead
module Main where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (void, when, unless, forever)
import qualified Data.ByteString as BS
import qualified Control.Exception as E
import Data.IORef
import System.Environment (lookupEnv)
import System.IO (hSetBuffering, hFlush, stdout, stderr, hPutStrLn, BufferMode(..))
import System.Posix.IO (stdInput, setFdOption, FdOption(NonBlockingRead))
import qualified System.Posix.IO.ByteString as PIO
import System.Posix.Pty (Pty, spawnWithPty, writePty, readPty, threadWaitReadPty)
import System.Posix.Terminal
import System.Posix.Types (Fd)
import System.Process (waitForProcess)
import Unsafe.Coerce (unsafeCoerce)

ptyToFd :: Pty -> Fd
ptyToFd = unsafeCoerce

main :: IO ()
main = do
  hSetBuffering stderr LineBuffering
  hPutStrLn stderr "DEBUG: starting"

  shell <- do
    m <- lookupEnv "SHELL"
    pure $ maybe "/bin/sh" id m

  hPutStrLn stderr $ "DEBUG: shell = " ++ shell

  -- Step 1: spawn PTY FIRST (before raw mode)
  hPutStrLn stderr "DEBUG: spawning PTY"
  (pty, ph) <- spawnWithPty Nothing True shell [] (80, 24)
  let fd = ptyToFd pty
  hPutStrLn stderr $ "DEBUG: pty fd = " ++ show fd

  running <- newIORef True

  -- Step 2: try reading PTY output directly (blocking, before raw mode)
  hPutStrLn stderr "DEBUG: waiting 1s for shell to start..."
  threadDelay 1000000

  hPutStrLn stderr "DEBUG: trying direct readPty..."
  result1 <- E.try (readPty pty) :: IO (Either E.SomeException BS.ByteString)
  case result1 of
    Left e -> hPutStrLn stderr $ "DEBUG: readPty failed: " ++ show e
    Right bs -> hPutStrLn stderr $ "DEBUG: readPty got " ++ show (BS.length bs) ++ " bytes"

  hPutStrLn stderr "DEBUG: trying fdRead on pty fd..."
  setFdOption fd NonBlockingRead True
  result2 <- E.try (PIO.fdRead fd 4096) :: IO (Either E.SomeException BS.ByteString)
  case result2 of
    Left e -> hPutStrLn stderr $ "DEBUG: fdRead pty failed: " ++ show e
    Right bs -> hPutStrLn stderr $ "DEBUG: fdRead pty got " ++ show (BS.length bs) ++ " bytes"

  -- Step 3: now set raw mode
  hPutStrLn stderr "DEBUG: setting raw mode"
  origAttrs <- getTerminalAttributes stdInput
  let rawAttrs = foldl withoutMode origAttrs
        [ EnableEcho, ProcessInput, KeyboardInterrupts
        , StartStopInput, ExtendedFunctions ]
  setTerminalAttributes stdInput rawAttrs Immediately
  hSetBuffering stdout NoBuffering
  setFdOption stdInput NonBlockingRead True

  -- Step 4: PTY reader thread using polling
  hPutStrLn stderr "DEBUG: starting pty reader (polling)"
  void $ forkIO $ do
    let go = do
          alive <- readIORef running
          when alive $ do
            result <- E.try (PIO.fdRead fd 4096) :: IO (Either E.SomeException BS.ByteString)
            case result of
              Left _ -> threadDelay 10000 >> go  -- EAGAIN, retry after 10ms
              Right bs -> do
                unless (BS.null bs) $ do
                  BS.hPut stdout bs
                  hFlush stdout
                threadDelay 10000
                go
    go

  -- Step 5: process watcher
  void $ forkIO $ do
    _ <- waitForProcess ph
    hPutStrLn stderr "DEBUG: shell exited"
    writeIORef running False

  -- Step 6: input loop using polling
  hPutStrLn stderr "DEBUG: entering input loop (polling)"
  let go = do
        alive <- readIORef running
        when alive $ do
          result <- E.try (PIO.fdRead stdInput 1) :: IO (Either E.SomeException BS.ByteString)
          case result of
            Left _ -> threadDelay 10000 >> go  -- EAGAIN, retry
            Right bs -> do
              unless (BS.null bs) $
                writePty pty bs
              threadDelay 1000
              go
  go

  -- Restore
  hPutStrLn stderr "DEBUG: restoring terminal"
  setTerminalAttributes stdInput origAttrs Immediately
  hPutStrLn stderr "DEBUG: done"
