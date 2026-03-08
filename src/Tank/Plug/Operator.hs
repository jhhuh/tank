{-# LANGUAGE OverloadedStrings #-}

module Tank.Plug.Operator
  ( runOperatorPlug
  , AgentState(..)
  , newAgentState
  , agentStep
  , agentStepWith
  , ProgressCallback
  ) where

import Control.Concurrent (forkIO)
import Control.Monad (forM_, void)
import qualified Control.Exception as E
import Data.Aeson (Value(..), object, (.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Vector as V
import qualified Data.Text.Encoding as TE
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.IORef
import qualified Data.Set as Set
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import System.Directory (getCurrentDirectory)
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr, hFlush, stdout)

import Tank.Core.Types (PlugCapability(..))
import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Daemon.Socket (socketPath)
import Tank.Plug.Client (PlugClient(..), connectDaemon, sendMsg, recvMsg, disconnectPlug)
import Tank.Plug.Operator.Tools (readFileTool, writeFileTool, executeTool, grepTool)

-- | Agent state. Messages are stored as raw JSON Values so that
-- assistant responses with tool_use content blocks can be sent back
-- verbatim, and user messages with tool_result blocks are preserved.
data AgentState = AgentState
  { asMessages :: ![Value]      -- ^ Conversation messages as JSON objects
  , asSystem   :: !Text         -- ^ System prompt (sent separately)
  , asStatus   :: !Text
  , asModel    :: !Text
  , asApiKey   :: !(Maybe Text)
  } deriving (Show)

newAgentState :: IO AgentState
newAgentState = do
  mKey <- lookupEnv "ANTHROPIC_API_KEY"
  pure AgentState
    { asMessages = []
    , asSystem   = systemPrompt
    , asStatus   = "idle"
    , asModel    = "claude-sonnet-4-20250514"
    , asApiKey   = T.pack <$> mKey
    }

systemPrompt :: Text
systemPrompt = T.unlines
  [ "You are a coding agent running inside a tank terminal pane."
  , "You have access to tools for reading files, writing files, executing commands, and searching with grep."
  , "Use them as needed to accomplish tasks. Keep responses concise. Focus on the task."
  ]

-- | Tool definitions for the Claude API request.
toolDefinitions :: [Value]
toolDefinitions =
  [ object
      [ "name" .= ("read_file" :: Text)
      , "description" .= ("Read the contents of a file" :: Text)
      , "input_schema" .= object
          [ "type" .= ("object" :: Text)
          , "properties" .= object
              [ "path" .= object
                  [ "type" .= ("string" :: Text)
                  , "description" .= ("File path (absolute or relative to working dir)" :: Text)
                  ]
              ]
          , "required" .= (["path"] :: [Text])
          ]
      ]
  , object
      [ "name" .= ("write_file" :: Text)
      , "description" .= ("Write content to a file, creating parent directories if needed" :: Text)
      , "input_schema" .= object
          [ "type" .= ("object" :: Text)
          , "properties" .= object
              [ "path" .= object
                  [ "type" .= ("string" :: Text)
                  , "description" .= ("File path (absolute or relative to working dir)" :: Text)
                  ]
              , "content" .= object
                  [ "type" .= ("string" :: Text)
                  , "description" .= ("Content to write to the file" :: Text)
                  ]
              ]
          , "required" .= (["path", "content"] :: [Text])
          ]
      ]
  , object
      [ "name" .= ("execute" :: Text)
      , "description" .= ("Run a shell command and return stdout+stderr. Times out after 30 seconds." :: Text)
      , "input_schema" .= object
          [ "type" .= ("object" :: Text)
          , "properties" .= object
              [ "command" .= object
                  [ "type" .= ("string" :: Text)
                  , "description" .= ("Shell command to execute" :: Text)
                  ]
              ]
          , "required" .= (["command"] :: [Text])
          ]
      ]
  , object
      [ "name" .= ("grep" :: Text)
      , "description" .= ("Search for a pattern in files using grep -rn" :: Text)
      , "input_schema" .= object
          [ "type" .= ("object" :: Text)
          , "properties" .= object
              [ "pattern" .= object
                  [ "type" .= ("string" :: Text)
                  , "description" .= ("Pattern to search for" :: Text)
                  ]
              , "glob" .= object
                  [ "type" .= ("string" :: Text)
                  , "description" .= ("Optional glob to filter files (e.g. \"*.hs\")" :: Text)
                  ]
              ]
          , "required" .= (["pattern"] :: [Text])
          ]
      ]
  ]

-- | Maximum number of tool-call rounds per agentStep invocation.
maxToolRounds :: Int
maxToolRounds = 10

-- | Progress callback: receives (event_type, detail) for tool use visibility.
-- event_type is "tool_use" or "tool_result"
type ProgressCallback = Text -> Text -> IO ()

-- | Run one step of the agent loop: send user message, handle tool calls,
-- return final text response.
agentStep :: AgentState -> FilePath -> Text -> IO (AgentState, Text)
agentStep state workDir userMsg = agentStepWith state workDir userMsg Nothing

-- | Like agentStep but with an optional progress callback for tool visibility.
agentStepWith :: AgentState -> FilePath -> Text -> Maybe ProgressCallback -> IO (AgentState, Text)
agentStepWith state workDir userMsg mcb = do
  let userJSON = object
        [ "role" .= ("user" :: Text)
        , "content" .= userMsg
        ]
      state' = state
        { asMessages = asMessages state ++ [userJSON]
        , asStatus = "thinking..."
        }

  case asApiKey state' of
    Nothing -> pure (state' { asStatus = "no API key" },
                     "Error: ANTHROPIC_API_KEY not set")
    Just apiKey -> do
      manager <- newManager tlsManagerSettings
      agentLoop manager apiKey state' workDir 0 mcb

-- | The core agent loop. Calls the API, processes tool calls, repeats.
agentLoop :: Manager -> Text -> AgentState -> FilePath -> Int -> Maybe ProgressCallback -> IO (AgentState, Text)
agentLoop manager apiKey state workDir iterations mcb
  | iterations >= maxToolRounds = do
      let state' = state { asStatus = "max tool rounds reached" }
      pure (state', "Error: reached maximum tool call iterations (" <> T.pack (show maxToolRounds) <> ")")
  | otherwise = do
      result <- callClaudeAPI manager apiKey (asModel state) (asSystem state) (asMessages state)
      case result of
        Left err -> pure (state { asStatus = "error" }, "Error: " <> err)
        Right respObj -> do
          let stopReason = getTextField "stop_reason" respObj
              contentBlocks = getContentBlocks respObj
              assistantMsg = object
                [ "role" .= ("assistant" :: Text)
                , "content" .= contentBlocks
                ]
              state' = state { asMessages = asMessages state ++ [assistantMsg] }

          case stopReason of
            Just "tool_use" -> do
              let toolCalls = extractToolCalls contentBlocks
              -- Notify callback about each tool call
              forM_ toolCalls $ \(_tid, tname, tinput) ->
                case mcb of
                  Just cb -> cb "tool_use" (tname <> ": " <> summarizeInput tinput)
                  Nothing -> pure ()
              toolResults <- mapM (executeToolCall workDir) toolCalls
              -- Notify callback about results
              forM_ toolResults $ \resultVal ->
                case mcb of
                  Just cb -> cb "tool_result" (summarizeToolResult resultVal)
                  Nothing -> pure ()
              let toolResultMsg = object
                    [ "role" .= ("user" :: Text)
                    , "content" .= toolResults
                    ]
                  state'' = state' { asMessages = asMessages state' ++ [toolResultMsg]
                                   , asStatus = "thinking..." }
              agentLoop manager apiKey state'' workDir (iterations + 1) mcb

            _ -> do
              let textParts = extractTextBlocks contentBlocks
                  responseText = T.intercalate "\n" textParts
              pure (state' { asStatus = "idle" }, responseText)

-- | Call the Claude API, returning the parsed response object.
callClaudeAPI :: Manager -> Text -> Text -> Text -> [Value] -> IO (Either Text Value)
callClaudeAPI manager apiKey model sysPrompt msgs = do
  let body = object
        [ "model" .= model
        , "max_tokens" .= (4096 :: Int)
        , "tools" .= toolDefinitions
        , "system" .= sysPrompt
        , "messages" .= msgs
        ]
  initReq <- parseRequest "https://api.anthropic.com/v1/messages"
  let req = initReq
        { method = "POST"
        , requestHeaders =
            [ ("content-type", "application/json")
            , ("x-api-key", TE.encodeUtf8 apiKey)
            , ("anthropic-version", "2023-06-01")
            ]
        , requestBody = RequestBodyLBS (Aeson.encode body)
        }
  resp <- httpLbs req manager
  case Aeson.decode (responseBody resp) of
    Nothing -> pure $ Left "Failed to parse API response"
    Just val@(Object obj) -> case KM.lookup "error" obj of
      Just (Object errObj) -> case KM.lookup "message" errObj of
        Just (String errMsg) -> pure $ Left errMsg
        _ -> pure $ Left "Unknown API error"
      _ -> pure $ Right val
    _ -> pure $ Left "Unexpected response type"

-- | Extract content blocks array from a response object.
getContentBlocks :: Value -> [Value]
getContentBlocks (Object obj) = case KM.lookup "content" obj of
  Just (Array arr) -> V.toList arr
  _ -> []
getContentBlocks _ = []

-- | Get a text field from a JSON object.
getTextField :: Text -> Value -> Maybe Text
getTextField key (Object obj) = case KM.lookup (Key.fromText key) obj of
  Just (String t) -> Just t
  _ -> Nothing
getTextField _ _ = Nothing

-- | Extract tool_use blocks from content blocks.
-- Returns list of (tool_use_id, tool_name, input_object).
extractToolCalls :: [Value] -> [(Text, Text, Value)]
extractToolCalls = concatMap go
  where
    go (Object block) = case KM.lookup "type" block of
      Just (String "tool_use") ->
        case (KM.lookup "id" block, KM.lookup "name" block, KM.lookup "input" block) of
          (Just (String tid), Just (String name), Just input) -> [(tid, name, input)]
          _ -> []
      _ -> []
    go _ = []

-- | Extract text blocks from content blocks.
extractTextBlocks :: [Value] -> [Text]
extractTextBlocks = concatMap go
  where
    go (Object block) = case KM.lookup "type" block of
      Just (String "text") -> case KM.lookup "text" block of
        Just (String t) -> [t]
        _ -> []
      _ -> []
    go _ = []

-- | Execute a single tool call, returning a tool_result JSON value.
executeToolCall :: FilePath -> (Text, Text, Value) -> IO Value
executeToolCall workDir (toolId, toolName, input) = do
  result <- dispatchTool workDir toolName input
  let content = case result of
        Left err  -> err
        Right out -> out
  pure $ object
    [ "type" .= ("tool_result" :: Text)
    , "tool_use_id" .= toolId
    , "content" .= content
    ]

-- | Summarize tool input for display
summarizeInput :: Value -> Text
summarizeInput (Object obj) = case KM.lookup "command" obj of
  Just (String cmd) -> T.take 60 cmd
  _ -> case KM.lookup "path" obj of
    Just (String p) -> T.take 60 p
    _ -> case KM.lookup "pattern" obj of
      Just (String pat) -> T.take 60 pat
      _ -> "(…)"
summarizeInput _ = "(…)"

-- | Summarize a tool result for display (first line, truncated)
summarizeToolResult :: Value -> Text
summarizeToolResult (Object obj) = case KM.lookup "content" obj of
  Just (String t) -> T.take 80 (head' (T.lines t))
  _ -> "(no output)"
  where
    head' [] = ""
    head' (x:_) = x
summarizeToolResult _ = "(…)"

-- | Dispatch a tool call to the appropriate tool function.
dispatchTool :: FilePath -> Text -> Value -> IO (Either Text Text)
dispatchTool workDir "read_file" (Object input) =
  case KM.lookup "path" input of
    Just (String path) -> readFileTool workDir (T.unpack path)
    _ -> pure $ Left "read_file: missing 'path' parameter"
dispatchTool workDir "write_file" (Object input) =
  case (KM.lookup "path" input, KM.lookup "content" input) of
    (Just (String path), Just (String content)) ->
      writeFileTool workDir (T.unpack path) content
    _ -> pure $ Left "write_file: missing 'path' or 'content' parameter"
dispatchTool workDir "execute" (Object input) =
  case KM.lookup "command" input of
    Just (String cmd) -> executeTool workDir cmd
    _ -> pure $ Left "execute: missing 'command' parameter"
dispatchTool workDir "grep" (Object input) =
  case KM.lookup "pattern" input of
    Just (String pat) -> do
      let mGlob = case KM.lookup "glob" input of
            Just (String g) -> Just g
            _ -> Nothing
      grepTool workDir pat mGlob
    _ -> pure $ Left "grep: missing 'pattern' parameter"
dispatchTool _ name _ =
  pure $ Left $ "Unknown tool: " <> name

-- | Run the operator plug. Connects to daemon if available, otherwise standalone.
runOperatorPlug :: IO ()
runOperatorPlug = do
  state <- newAgentState
  workDir <- getCurrentDirectory

  -- Try connecting to daemon
  sockPath <- socketPath "default"
  mClient <- connectDaemon sockPath "operator" (Set.singleton CapOperator)
  case mClient of
    Nothing -> do
      hPutStrLn stderr "tank operator: standalone mode (no daemon)"
      replLoop state workDir Nothing
    Just client -> do
      hPutStrLn stderr $ "tank operator: connected as " ++ show (pcPlugId client)
      -- Query cells and attach to first one if available
      let pid = pcPlugId client
      sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0 MsgListCells
      resp <- recvMsg client
      case resp of
        Right env | MsgListCellsResponse ((cid, dir):_) <- mePayload env -> do
          hPutStrLn stderr $ "tank operator: attaching to cell " ++ show cid ++ " in " ++ dir
          sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
            (MsgCellAttach cid pid)
          -- Background thread: receive daemon messages (MsgOutput, etc.)
          screenRef <- newIORef ""
          void $ forkIO $ operatorDaemonReader client screenRef
          replLoop state dir (Just screenRef)
        _ -> do
          hPutStrLn stderr "tank operator: no cells found, running standalone"
          replLoop state workDir Nothing

      disconnectPlug client

-- | Background thread: receives daemon messages and updates screen context.
operatorDaemonReader :: PlugClient -> IORef Text -> IO ()
operatorDaemonReader client screenRef = go
  where
    go = do
      result <- recvMsg client
      case result of
        Left _err -> hPutStrLn stderr "tank operator: daemon connection lost"
        Right env -> do
          case mePayload env of
            MsgOutput _cid bs -> do
              -- Accumulate raw output as context (simplified — real impl would use VTerm)
              let chunk = TE.decodeUtf8With (\_ _ -> Just '?') bs
              modifyIORef' screenRef (\old -> T.takeEnd 4096 (old <> chunk))
            _ -> pure ()
          go

-- | REPL loop for operator prompts.
replLoop :: AgentState -> FilePath -> Maybe (IORef Text) -> IO ()
replLoop st wd mScreenRef = do
  TIO.putStr "> "
  hFlush stdout
  mLine <- E.try TIO.getLine :: IO (Either E.IOException Text)
  case mLine of
    Left _ -> pure ()
    Right line -> do
      -- Include screen context if available
      ctx <- case mScreenRef of
        Nothing -> pure ""
        Just ref -> do
          screen <- readIORef ref
          if T.null screen
            then pure ""
            else pure $ "\n\n[Current terminal output (last 4096 chars)]:\n" <> screen <> "\n\n"
      let fullMsg = if T.null ctx then line else ctx <> line
      (st', response) <- agentStep st wd fullMsg
      TIO.putStrLn response
      replLoop st' wd mScreenRef
