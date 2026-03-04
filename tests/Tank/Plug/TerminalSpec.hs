{-# LANGUAGE OverloadedStrings #-}

module Tank.Plug.TerminalSpec (spec) where

import Test.Hspec
import Control.Concurrent (threadDelay)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Control.Exception as E
import GHC.Conc (threadWaitRead)
import System.Posix.IO (setFdOption, FdOption(NonBlockingRead))
import qualified System.Posix.IO.ByteString as PIO
import System.Posix.Pty (Pty, spawnWithPty, writePty)
import System.Posix.Types (Fd)
import System.Timeout (timeout)
import Unsafe.Coerce (unsafeCoerce)

ptyToFd :: Pty -> Fd
ptyToFd = unsafeCoerce

spec :: Spec
spec = do
  describe "PTY basics" $ do
    it "can spawn /bin/sh and read output" $ do
      result <- timeout 5000000 $ do
        (pty, _ph) <- spawnWithPty Nothing True "/bin/sh" [] (80, 24)
        let fd = ptyToFd pty
        setFdOption fd NonBlockingRead True
        threadDelay 500000
        writePty pty "echo tank-pty-test\n"
        threadDelay 500000
        output <- drainFd fd
        BS8.unpack output `shouldSatisfy` ("tank-pty-test" `isInfixOfStr`)
        writePty pty "exit\n"
      result `shouldSatisfy` (/= Nothing)

drainFd :: Fd -> IO BS.ByteString
drainFd fd = do
  threadWaitRead fd
  chunks <- drainLoop 10 []
  pure $ BS.concat (reverse chunks)
  where
    drainLoop 0 acc = pure acc
    drainLoop n acc = do
      result <- E.try (PIO.fdRead fd 4096) :: IO (Either E.SomeException BS.ByteString)
      case result of
        Left _ -> pure acc
        Right bs
          | BS.null bs -> pure acc
          | otherwise -> drainLoop (n - 1 :: Int) (bs : acc)

isInfixOfStr :: String -> String -> Bool
isInfixOfStr needle haystack = any (isPrefixOfStr needle) (tails' haystack)

isPrefixOfStr :: String -> String -> Bool
isPrefixOfStr [] _ = True
isPrefixOfStr _ [] = False
isPrefixOfStr (x:xs) (y:ys) = x == y && isPrefixOfStr xs ys

tails' :: [a] -> [[a]]
tails' [] = [[]]
tails' xs@(_:xs') = xs : tails' xs'
