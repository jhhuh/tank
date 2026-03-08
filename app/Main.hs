{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import qualified Data.ByteString as BS
import qualified Data.Set as Set
import Data.UUID (fromString)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr, stdout, hFlush)
import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Core.Types (CellId(..))
import Tank.Daemon.Main (startDaemon, stopDaemon)
import Tank.Daemon.Socket (socketPath)
import Tank.Plug.Client (PlugClient(..), connectDaemon, sendMsg, recvMsg, disconnectPlug)
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
    ["list-cells"]  -> cmdListCells
    ["attach-to-cell", cellIdStr] -> cmdAttachToCell cellIdStr
    ["--help"]      -> printUsage
    ["-h"]          -> printUsage
    []              -> runTerminalPlug  -- default: standalone terminal
    _               -> do
      hPutStrLn stderr $ "tank: unknown command: " ++ unwords args
      printUsage

-- | Query daemon for active cells and print them.
cmdListCells :: IO ()
cmdListCells = do
  sockPath <- socketPath "default"
  mClient <- connectDaemon sockPath "list-cells" Set.empty
  case mClient of
    Nothing -> do
      hPutStrLn stderr "tank: daemon not running"
      exitFailure
    Just client -> do
      let pid = pcPlugId client
          env = MessageEnvelope 1 pid TargetBroadcast 2 MsgListCells
      sendMsg client env
      resp <- recvMsg client
      case resp of
        Right rEnv | MsgListCellsResponse cells <- mePayload rEnv -> do
          if null cells
            then putStrLn "No active cells."
            else mapM_ (\(CellId uid, dir) ->
                   putStrLn $ show uid ++ "  " ++ dir) cells
        _ -> hPutStrLn stderr "tank: unexpected response"
      disconnectPlug client

-- | Attach terminal to an existing cell by ID.
cmdAttachToCell :: String -> IO ()
cmdAttachToCell cellIdStr = case fromString cellIdStr of
  Nothing -> do
    hPutStrLn stderr $ "tank: invalid cell ID: " ++ cellIdStr
    exitFailure
  Just uuid -> do
    sockPath <- socketPath "default"
    mClient <- connectDaemon sockPath "attach-cell" Set.empty
    case mClient of
      Nothing -> do
        hPutStrLn stderr "tank: daemon not running"
        exitFailure
      Just client -> do
        let pid = pcPlugId client
            cid = CellId uuid
        sendMsg client $ MessageEnvelope 1 pid (TargetCell cid) 2
                           (MsgCellAttach cid pid)
        hPutStrLn stderr $ "tank: attached to " ++ cellIdStr
        let loop = do
              result <- recvMsg client
              case result of
                Left _ -> hPutStrLn stderr "tank: connection lost"
                Right env -> do
                  case mePayload env of
                    MsgOutput _cid bs -> BS.hPut stdout bs >> hFlush stdout
                    _ -> pure ()
                  loop
        loop
        disconnectPlug client

printUsage :: IO ()
printUsage = do
  putStrLn "tank - protocol-centric workspace system"
  putStrLn ""
  putStrLn "Usage:"
  putStrLn "  tank start                 Start the daemon"
  putStrLn "  tank attach                Attach to running daemon"
  putStrLn "  tank list-cells            List active cells"
  putStrLn "  tank attach-to-cell <ID>   Attach to an existing cell"
  putStrLn "  tank kill-server           Stop the daemon"
  putStrLn "  tank --help                Show this help"
