module Main (main) where

import System.Environment (getArgs)
import System.IO (hPutStrLn, stderr)
import Tank.Daemon.Main (startDaemon, stopDaemon)
import Tank.Plug.Terminal (runTerminalPlug)
import Tank.Plug.Operator (runOperatorPlug)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["start"]       -> startDaemon "default"
    ["attach"]      -> runTerminalPlug
    ["agent"]       -> runOperatorPlug
    ["kill-server"] -> stopDaemon "default"
    ["--help"]      -> printUsage
    ["-h"]          -> printUsage
    []              -> runTerminalPlug  -- default: standalone terminal
    _               -> do
      hPutStrLn stderr $ "tank: unknown command: " ++ unwords args
      printUsage

printUsage :: IO ()
printUsage = do
  putStrLn "tank - protocol-centric workspace system"
  putStrLn ""
  putStrLn "Usage:"
  putStrLn "  tank start        Start the daemon"
  putStrLn "  tank attach       Attach to running daemon"
  putStrLn "  tank kill-server  Stop the daemon"
  putStrLn "  tank --help       Show this help"
