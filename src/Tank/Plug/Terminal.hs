{-# LANGUAGE OverloadedStrings #-}

module Tank.Plug.Terminal
  ( runTerminalPlug
  ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (bracket_, finally, SomeException, try)
import Control.Monad (void, when, unless, forM_)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import Data.Char (chr, isDigit, digitToInt, ord)
import qualified Data.IntMap.Strict as IM
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word8)
import Data.IORef
import System.Environment (lookupEnv)
import System.IO
import System.Posix.IO (stdInput, setFdOption, FdOption(NonBlockingRead))
import qualified System.Posix.IO.ByteString as PIO
import System.Posix.Types (Fd)
import GHC.Conc (threadWaitRead)
import System.Posix.Pty (Pty, spawnWithPty, writePty, resizePty)
import Unsafe.Coerce (unsafeCoerce)
import System.Posix.Signals (installHandler, Handler(Catch))
import System.Posix.Signals.Exts (windowChange)
import System.Posix.Terminal
  ( getTerminalAttributes, setTerminalAttributes
  , withoutMode, withMinInput, withTime
  , TerminalMode(..), TerminalState(..)
  )
import System.Process (waitForProcess, ProcessHandle)
import qualified System.Console.Terminal.Size as TS

import Tank.Plug.Operator (AgentState, newAgentState, agentStepWith)
import Tank.Plug.Operator.Overlay
  ( OverlayState(..), OverlayAction(..), Role(..)
  , newOverlayState, renderOverlay, handleOverlayKey
  , addMessage, setStatus
  )
import qualified Data.Set as Set
import Data.UUID.V4 (nextRandom)
import Tank.Core.Types (CellId(..), PlugCapability(..))
import Tank.Core.Protocol (Message(..), MessageEnvelope(..), Target(..))
import Tank.Plug.Client (PlugClient, connectDaemon, sendMsg, recvMsg, disconnectPlug, pcPlugId)
import Tank.Daemon.Socket (socketPath)
import Tank.Terminal.Emulator
  ( VTerm, mkVTerm, vtFeed, vtResize, vtGetCell, vtGetCursor, vtGetSize
  , Cell(..), Attrs(..), Color(..), defaultAttrs, defaultCell
  , hasFlag, attrBold, attrDim, attrUnderline, attrInverse
  , vtScrollbackLines, vtScrollbackSize
  )
import Tank.Terminal.CellAdapter (vtermToCellGrid)
import Tank.Layout.Render (renderLayout)
import Tank.Layout.Cell (CellGrid(..))
import qualified Tank.Layout.Cell as LC
import Tank.Layout.Types (Layout(..), Dir(..), Content(..))
import Tank.Layout.Backend.ANSI (renderRowANSI)
import qualified Data.Vector as V

-- | A single pane: one PTY, one agent overlay, one virtual screen
data Pane = Pane
  { pPty     :: !Pty
  , pRunning :: !(IORef Bool)
  , pOverlay :: !(IORef OverlayState)
  , pAgent   :: !(IORef AgentState)
  , pVTerm   :: !(IORef VTerm)
  , pCellId  :: !(Maybe CellId)
  }

-- | How panes are arranged within a window.
-- Named PaneSplit/PaneLayout to distinguish from tank-layout's rendering types.
data PaneSplit = PHorizontal | PVertical deriving (Eq, Show)

data PaneLayout
  = LPane !Int                                    -- single pane by id
  | LSplit !PaneSplit !Float PaneLayout PaneLayout -- direction, ratio (0..1), first, second
  deriving (Show)

-- | A window: a layout of panes
data Window = Window
  { wLayout :: !(IORef PaneLayout)
  , wActive :: !(IORef Int)     -- active pane id within this window
  }

-- | Global terminal state
data TermState = TermState
  { tsPanes     :: !(IORef (IM.IntMap Pane))
  , tsWindows   :: !(IORef (IM.IntMap Window))
  , tsActiveWin :: !(IORef Int)
  , tsNextPaneId :: !(IORef Int)
  , tsNextWinId  :: !(IORef Int)
  , tsRunning   :: !(IORef Bool)
  , tsPrefix    :: !(IORef Bool)
  , tsCols      :: !(IORef Int)
  , tsShell     :: !String
  , tsCopyScroll :: !(IORef Int)  -- 0 = normal, >0 = copy mode scroll offset
  , tsDaemon     :: !(IORef (Maybe PlugClient))
  }

-- | Run the terminal UI plug
runTerminalPlug :: IO ()
runTerminalPlug = do
  shell <- getShell

  origAttrs <- getTerminalAttributes stdInput
  let raw1 = foldl withoutMode origAttrs
               [ EnableEcho, ProcessInput, KeyboardInterrupts
               , StartStopInput, ExtendedFunctions
               , MapCRtoLF, CheckParity, StripHighBit
               , StartStopOutput, ProcessOutput ]
      rawAttrs = (`withTime` 0) . (`withMinInput` 1) $ raw1
  let restore = setTerminalAttributes stdInput origAttrs Immediately

  bracket_ (setTerminalAttributes stdInput rawAttrs Immediately) restore $ do
    hSetBuffering stdout NoBuffering
    hSetBuffering stdin NoBuffering
    hSetBuffering stderr LineBuffering

    (cols, rows) <- getTermSize
    setFdOption stdInput NonBlockingRead True

    -- Clear screen, set scroll region, cursor home
    BS.hPut stdout $ BS8.pack $
      "\x1b[2J\x1b[1;" ++ show rows ++ "r\x1b[H"
    hFlush stdout

    ts <- do
      panesRef   <- newIORef IM.empty
      windowsRef <- newIORef IM.empty
      activeWin  <- newIORef 0
      nextPane   <- newIORef 0
      nextWin    <- newIORef 0
      runningRef <- newIORef True
      prefixRef  <- newIORef False
      colsRef    <- newIORef cols
      copyRef    <- newIORef 0
      daemonRef  <- newIORef Nothing
      pure TermState
        { tsPanes      = panesRef
        , tsWindows    = windowsRef
        , tsActiveWin  = activeWin
        , tsNextPaneId = nextPane
        , tsNextWinId  = nextWin
        , tsRunning    = runningRef
        , tsPrefix     = prefixRef
        , tsCols       = colsRef
        , tsShell      = shell
        , tsCopyScroll = copyRef
        , tsDaemon     = daemonRef
        }

    -- Try connecting to daemon (optional — works standalone if not running)
    daemonSockPath <- socketPath "default"
    mClient <- connectDaemon daemonSockPath "terminal" (Set.singleton CapTerminal)
    writeIORef (tsDaemon ts) mClient
    case mClient of
      Just client -> do
        hPutStrLn stderr $ "tank: connected to daemon as " ++ show (pcPlugId client)
        void $ forkIO $ daemonReaderThread ts client
      Nothing -> hPutStrLn stderr "tank: running standalone (no daemon)"

    void $ installHandler windowChange (Catch $ handleResizeAll ts) Nothing

    -- Create first window with one pane
    void $ createWindowWithPane ts

    drawStatusLine ts False
    hFlush stdout

    inputLoop ts `finally` do
      -- Disconnect from daemon
      mClient' <- readIORef (tsDaemon ts)
      case mClient' of
        Just client' -> disconnectPlug client'
        Nothing -> pure ()
      -- Restore terminal
      (_, finalRows) <- getTermSize
      BS.hPut stdout $ BS8.pack $
        "\x1b[r\x1b[" ++ show (finalRows + 1) ++ ";1H\x1b[2K"
      hFlush stdout

-- | Create a new pane with a PTY
createPane :: TermState -> Int -> Int -> IO Int
createPane ts cols rows = do
  paneId <- readIORef (tsNextPaneId ts)
  modifyIORef' (tsNextPaneId ts) (+ 1)
  (pty, ph) <- spawnWithPty Nothing True (tsShell ts) ["-l"] (cols, rows)
  pRunRef  <- newIORef True
  pOvRef   <- newIORef newOverlayState
  pAgRef   <- newIORef =<< newAgentState
  pVtRef   <- newIORef (mkVTerm cols rows)

  -- Generate CellId if connected to daemon
  mClient <- readIORef (tsDaemon ts)
  mCid <- case mClient of
    Nothing -> pure Nothing
    Just client -> do
      cuid <- nextRandom
      let cid = CellId cuid
          pid = pcPlugId client
      sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
        (MsgCellCreate cid ".")
      sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
        (MsgCellAttach cid pid)
      pure (Just cid)

  let pane = Pane pty pRunRef pOvRef pAgRef pVtRef mCid
  modifyIORef' (tsPanes ts) (IM.insert paneId pane)
  -- PTY reader thread
  void $ forkIO $ paneReaderThread ts pane paneId
  -- Process watcher
  void $ forkIO $ paneProcessWatcher ts paneId ph
  pure paneId

-- | Create a new window with a single pane
createWindowWithPane :: TermState -> IO Int
createWindowWithPane ts = do
  (cols, rows) <- getTermSize
  paneId <- createPane ts cols rows
  winId <- readIORef (tsNextWinId ts)
  modifyIORef' (tsNextWinId ts) (+ 1)
  layoutRef <- newIORef (LPane paneId)
  activeRef <- newIORef paneId
  let win = Window layoutRef activeRef
  modifyIORef' (tsWindows ts) (IM.insert winId win)
  switchToWindow ts winId
  pure winId

-- | Split the active pane in the active window
splitActivePane :: TermState -> PaneSplit -> IO ()
splitActivePane ts dir = do
  mwin <- getActiveWindow ts
  case mwin of
    Nothing -> pure ()
    Just (_winId, win) -> do
      activePaneId <- readIORef (wActive win)
      -- Compute the new pane's dimensions based on split
      layout <- readIORef (wLayout win)
      (cols, rows) <- getTermSize
      let (_, _, w, h) = findPaneRegion layout activePaneId cols rows
          (newW, newH) = case dir of
            PVertical   -> (w `div` 2, h)
            PHorizontal -> (w, h `div` 2)
          (oldW, oldH) = case dir of
            PVertical   -> (w - newW - 1, h)       -- -1 for border
            PHorizontal -> (w, h - newH - 1)
      -- Resize the existing pane
      panes <- readIORef (tsPanes ts)
      case IM.lookup activePaneId panes of
        Nothing -> pure ()
        Just oldPane -> do
          resizePty (pPty oldPane) (max 1 oldW, max 1 oldH)
          modifyIORef' (pVTerm oldPane) (vtResize (max 1 oldW) (max 1 oldH))
      -- Create new pane
      newPaneId <- createPane ts (max 1 newW) (max 1 newH)
      -- Update layout: replace LPane activePaneId with LSplit
      let newLayout = replacePaneInLayout activePaneId
            (LSplit dir 0.5 (LPane activePaneId) (LPane newPaneId)) layout
      writeIORef (wLayout win) newLayout
      -- Redraw everything
      renderAllPanes ts

-- | Replace a pane id in the layout tree with a new subtree
replacePaneInLayout :: Int -> PaneLayout -> PaneLayout -> PaneLayout
replacePaneInLayout target replacement (LPane pid)
  | pid == target = replacement
  | otherwise     = LPane pid
replacePaneInLayout target replacement (LSplit d r l1 l2) =
  LSplit d r (replacePaneInLayout target replacement l1)
             (replacePaneInLayout target replacement l2)

-- | Find the screen region for a pane: (row, col, width, height)
findPaneRegion :: PaneLayout -> Int -> Int -> Int -> (Int, Int, Int, Int)
findPaneRegion layout paneId totalW totalH = go layout 0 0 totalW totalH
  where
    go (LPane pid) r c w h
      | pid == paneId = (r, c, w, h)
      | otherwise     = (-1, -1, 0, 0)
    go (LSplit dir ratio l1 l2) r c w h =
      let result1 = case dir of
            PVertical ->
              let w1 = floor (fromIntegral w * ratio) - 1  -- -1 for border
              in go l1 r c (max 1 w1) h
            PHorizontal ->
              let h1 = floor (fromIntegral h * ratio) - 1
              in go l1 r c w (max 1 h1)
          result2 = case dir of
            PVertical ->
              let w1 = floor (fromIntegral w * ratio)
              in go l2 r (c + w1) (max 1 (w - w1)) h
            PHorizontal ->
              let h1 = floor (fromIntegral h * ratio)
              in go l2 (r + h1) c w (max 1 (h - h1))
      in if fst4 result1 >= 0 then result1 else result2
    fst4 (a, _, _, _) = a

-- | PTY reader thread
paneReaderThread :: TermState -> Pane -> Int -> IO ()
paneReaderThread ts pane paneId = do
  let fd = ptyToFd (pPty pane)
  setFdOption fd NonBlockingRead True
  go fd
  where
    go fd' = do
      alive <- readIORef (pRunning pane)
      gAlive <- readIORef (tsRunning ts)
      when (alive && gAlive) $ do
        threadWaitRead fd'
        result <- try (PIO.fdRead fd' 4096) :: IO (Either SomeException ByteString)
        case result of
          Left _e -> writeIORef (pRunning pane) False
          Right bs -> do
            unless (BS.null bs) $ do
              -- Update virtual screen
              modifyIORef' (pVTerm pane) (vtFeed bs)
              -- Forward to daemon for other plugs
              case pCellId pane of
                Nothing -> pure ()
                Just cid -> do
                  mClient <- readIORef (tsDaemon ts)
                  case mClient of
                    Nothing -> pure ()
                    Just client -> do
                      let pid = pcPlugId client
                      sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
                            (MsgOutput cid bs)
              -- Check if this pane is visible and active
              mwin <- getActiveWindow ts
              case mwin of
                Nothing -> pure ()
                Just (_, win) -> do
                  layout <- readIORef (wLayout win)
                  let isSingle = case layout of LPane _ -> True; _ -> False
                  if isSingle && layoutContains paneId layout
                    then do
                      -- Single-pane window: raw passthrough for performance
                      BS.hPut stdout bs
                      hFlush stdout
                      ov <- readIORef (pOverlay pane)
                      when (osVisible ov) $ renderOverlayNow ov
                    else when (layoutContains paneId layout) $ do
                      -- Multi-pane: render this pane from VTerm
                      renderSinglePane ts pane paneId
            go fd'

-- | Background thread reading messages from the daemon.
-- Handles MsgInput from remote sources by writing to the appropriate PTY.
daemonReaderThread :: TermState -> PlugClient -> IO ()
daemonReaderThread ts client = go
  where
    go = do
      alive <- readIORef (tsRunning ts)
      when alive $ do
        result <- recvMsg client
        case result of
          Left _err -> pure ()  -- daemon disconnected, stop thread
          Right env -> do
            case mePayload env of
              MsgInput _cid bytes -> do
                -- Find pane with matching CellId and write to its PTY
                panes <- readIORef (tsPanes ts)
                let matching = [ p | p <- IM.elems panes
                               , pCellId p == Just _cid ]
                case matching of
                  (pane:_) -> writePty (pPty pane) bytes
                  []       -> pure ()
              _ -> pure ()  -- ignore other messages for now
            go

-- | Check if a pane id is in a layout
layoutContains :: Int -> PaneLayout -> Bool
layoutContains pid (LPane p) = pid == p
layoutContains pid (LSplit _ _ l1 l2) = layoutContains pid l1 || layoutContains pid l2

-- | Get all pane ids from a layout
layoutPaneIds :: PaneLayout -> [Int]
layoutPaneIds (LPane pid) = [pid]
layoutPaneIds (LSplit _ _ l1 l2) = layoutPaneIds l1 ++ layoutPaneIds l2

-- | Process watcher for a pane
paneProcessWatcher :: TermState -> Int -> ProcessHandle -> IO ()
paneProcessWatcher ts paneId ph = do
  _ <- waitForProcess ph
  panes <- readIORef (tsPanes ts)
  case IM.lookup paneId panes of
    Nothing -> pure ()
    Just pane -> do
      writeIORef (pRunning pane) False
      threadDelay 50000
      modifyIORef' (tsPanes ts) (IM.delete paneId)
      -- Notify daemon about cell destruction
      case pCellId pane of
        Nothing -> pure ()
        Just cid -> do
          mClient <- readIORef (tsDaemon ts)
          case mClient of
            Nothing -> pure ()
            Just client -> do
              let pid = pcPlugId client
              sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
                (MsgCellDetach cid pid)
              sendMsg client $ MessageEnvelope 1 pid TargetBroadcast 0
                (MsgCellDestroy cid)
      -- Remove pane from its window layout
      windows <- readIORef (tsWindows ts)
      forM_ (IM.toList windows) $ \(winId, win) -> do
        layout <- readIORef (wLayout win)
        when (layoutContains paneId layout) $ do
          let newLayout = removePaneFromLayout paneId layout
          case newLayout of
            Nothing -> do
              -- Window is empty, remove it
              modifyIORef' (tsWindows ts) (IM.delete winId)
              activeWin <- readIORef (tsActiveWin ts)
              when (activeWin == winId) $ do
                remaining <- readIORef (tsWindows ts)
                if IM.null remaining
                  then writeIORef (tsRunning ts) False
                  else do
                    let (nextWinId, _) = IM.findMin remaining
                    switchToWindow ts nextWinId
                    drawStatusLine ts False
                    hFlush stdout
            Just layout' -> do
              writeIORef (wLayout win) layout'
              -- Update active pane if needed
              active <- readIORef (wActive win)
              when (active == paneId) $ do
                let pids = layoutPaneIds layout'
                case pids of
                  (p:_) -> writeIORef (wActive win) p
                  []    -> pure ()
              -- Resize remaining panes and redraw
              resizePanesInLayout ts layout'
              renderAllPanes ts

-- | Remove a pane from layout, returning Nothing if layout becomes empty
removePaneFromLayout :: Int -> PaneLayout -> Maybe PaneLayout
removePaneFromLayout pid (LPane p)
  | pid == p  = Nothing
  | otherwise = Just (LPane p)
removePaneFromLayout pid (LSplit _ _ l1 l2) =
  case (removePaneFromLayout pid l1, removePaneFromLayout pid l2) of
    (Nothing, Nothing) -> Nothing
    (Nothing, Just r)  -> Just r
    (Just l, Nothing)  -> Just l
    (Just l, Just r)   -> Just (LSplit PVertical 0.5 l r)  -- keep same dir?

-- | Resize all panes in a layout to fit their computed regions
resizePanesInLayout :: TermState -> PaneLayout -> IO ()
resizePanesInLayout ts layout = do
  (totalW, totalH) <- getTermSize
  panes <- readIORef (tsPanes ts)
  let allPids = layoutPaneIds layout
  forM_ allPids $ \pid ->
    case IM.lookup pid panes of
      Nothing -> pure ()
      Just pane -> do
        let (_, _, w, h) = findPaneRegion layout pid totalW totalH
        when (w > 0 && h > 0) $ do
          resizePty (pPty pane) (w, h)
          modifyIORef' (pVTerm pane) (vtResize w h)

-- | Switch to a window
switchToWindow :: TermState -> Int -> IO ()
switchToWindow ts winId = do
  windows <- readIORef (tsWindows ts)
  case IM.lookup winId windows of
    Nothing -> pure ()
    Just _win -> do
      writeIORef (tsActiveWin ts) winId
      renderAllPanes ts

-- | Cycle to next pane within the active window
cyclePaneInWindow :: TermState -> IO ()
cyclePaneInWindow ts = do
  mwin <- getActiveWindow ts
  case mwin of
    Nothing -> pure ()
    Just (_, win) -> do
      layout <- readIORef (wLayout win)
      active <- readIORef (wActive win)
      let pids = layoutPaneIds layout
      case pids of
        [] -> pure ()
        _  -> do
          case lookup active (zip pids [0..]) of
            Nothing -> pure ()
            Just pos -> do
              let nextPos = (pos + 1) `mod` length pids
                  nextPid = pids !! nextPos
              writeIORef (wActive win) nextPid
              renderAllPanes ts

-- | Get the active window
getActiveWindow :: TermState -> IO (Maybe (Int, Window))
getActiveWindow ts = do
  activeWin <- readIORef (tsActiveWin ts)
  windows <- readIORef (tsWindows ts)
  pure $ case IM.lookup activeWin windows of
    Nothing  -> Nothing
    Just win -> Just (activeWin, win)

-- | Get the active pane
getActivePane :: TermState -> IO (Maybe Pane)
getActivePane ts = do
  mwin <- getActiveWindow ts
  case mwin of
    Nothing -> pure Nothing
    Just (_, win) -> do
      activePid <- readIORef (wActive win)
      panes <- readIORef (tsPanes ts)
      pure $ IM.lookup activePid panes

-- | Convert a PaneLayout tree to a tank-layout Layout tree.
-- Reads VTerm state from each pane and converts to CellContent.
buildLayout :: IM.IntMap Pane -> PaneLayout -> IO Layout
buildLayout panes (LPane pid) =
  case IM.lookup pid panes of
    Nothing -> pure $ Leaf (Fill ' ' LC.Default)
    Just pane -> do
      vterm <- readIORef (pVTerm pane)
      let lcGrid = vtermToCellGrid vterm
      pure $ Leaf (CellContent lcGrid)
buildLayout panes (LSplit dir _ratio l1 l2) = do
  ll <- buildLayout panes l1
  rl <- buildLayout panes l2
  -- PVertical splits columns (left|right) → tank-layout Horizontal (splits width)
  -- PHorizontal splits rows (top|bottom) → tank-layout Vertical (splits height)
  let d = case dir of
        PVertical   -> Horizontal
        PHorizontal -> Vertical
  pure $ Split d _ratio ll rl

-- | Emit a CellGrid to stdout, one row per line, at terminal position.
emitGrid :: CellGrid -> IO ()
emitGrid (CellGrid rows) = do
  V.iforM_ rows $ \rowIdx row -> do
    BS.hPut stdout $ BS8.pack $
      "\x1b[" ++ show (rowIdx + 1) ++ ";1H"
    BS.hPut stdout $ renderRowANSI row
  BS.hPut stdout "\x1b[0m"

-- | Draw pane borders by overwriting split positions.
-- Preserves active-pane highlighting (green for active, dim for inactive).
drawPaneBorders :: PaneLayout -> Int -> Int -> Int -> Int -> Int -> IO ()
drawPaneBorders (LPane _) _ _ _ _ _ = pure ()
drawPaneBorders (LSplit dir _ratio l1 l2) activePid r c w h = do
  let activeInL1 = layoutContains activePid l1
      activeInL2 = layoutContains activePid l2
      -- Green for border next to active pane, dim for inactive
      borderSGR = if activeInL1 || activeInL2
                  then "\x1b[32m"  -- green
                  else "\x1b[2m"   -- dim
  case dir of
    PVertical -> do
      let w1 = w `div` 2
      forM_ [0 .. h - 1] $ \row ->
        BS.hPut stdout $ BS8.pack
          ("\x1b[" ++ show (r + row + 1) ++ ";" ++ show (c + w1 + 1) ++ "H" ++ borderSGR)
          <> encodeUtf8 "\x2502"
      BS.hPut stdout "\x1b[0m"
      drawPaneBorders l1 activePid r c w1 h
      drawPaneBorders l2 activePid r (c + w1 + 1) (w - w1 - 1) h
    PHorizontal -> do
      let h1 = h `div` 2
      BS.hPut stdout $ BS8.pack
        ("\x1b[" ++ show (r + h1 + 1) ++ ";" ++ show (c + 1) ++ "H" ++ borderSGR)
        <> BS.concat (replicate w (encodeUtf8 "\x2500"))
      BS.hPut stdout "\x1b[0m"
      drawPaneBorders l1 activePid r c w h1
      drawPaneBorders l2 activePid (r + h1 + 1) c w (h - h1 - 1)

-- | Render all visible panes in the active window
renderAllPanes :: TermState -> IO ()
renderAllPanes ts = do
  mwin <- getActiveWindow ts
  case mwin of
    Nothing -> pure ()
    Just (_, win) -> do
      layout <- readIORef (wLayout win)
      activePid <- readIORef (wActive win)
      (totalW, totalH) <- getTermSize
      panes <- readIORef (tsPanes ts)
      -- Clear screen
      BS.hPut stdout $ BS8.pack $
        "\x1b[1;" ++ show totalH ++ "r\x1b[2J\x1b[H"
      -- Build layout tree and render to grid
      tankLayout <- buildLayout panes layout
      let grid = renderLayout totalW totalH tankLayout
      emitGrid grid
      -- Draw borders between panes
      drawPaneBorders layout activePid 0 0 totalW totalH
      -- Restore cursor to active pane
      case IM.lookup activePid panes of
        Just pane -> do
          vterm <- readIORef (pVTerm pane)
          let (cr, cc) = vtGetCursor vterm
              (pr, pc, _, _) = findPaneRegion layout activePid totalW totalH
          BS.hPut stdout $ BS8.pack $
            "\x1b[" ++ show (pr + cr + 1) ++ ";" ++ show (pc + cc + 1) ++ "H"
        Nothing -> pure ()
      drawStatusLine ts False
      hFlush stdout

-- | Render a VTerm into a specific screen region with SGR attributes.
-- Uses delta-encoding: only emits SGR when attributes change between cells.
renderVTermAt :: VTerm -> Int -> Int -> Int -> Int -> IO ()
renderVTermAt vterm startRow startCol w h = do
  let (vtW, vtH) = vtGetSize vterm
      renderW = min w vtW
      renderH = min h vtH
  forM_ [0 .. renderH - 1] $ \row -> do
    BS.hPut stdout $ BS8.pack $
      "\x1b[" ++ show (startRow + row + 1) ++ ";" ++ show (startCol + 1) ++ "H"
    -- Reset attrs at start of each row
    BS.hPut stdout "\x1b[0m"
    let cells = [ vtGetCell row col vterm | col <- [0 .. renderW - 1] ]
    renderCellsWithSGR defaultAttrs cells
  -- Reset attributes after rendering
  BS.hPut stdout "\x1b[0m"

-- | Render cells, emitting SGR only when attributes change
renderCellsWithSGR :: Attrs -> [Cell] -> IO ()
renderCellsWithSGR _ [] = pure ()
renderCellsWithSGR prevAttrs (Cell ch attrs : rest) = do
  when (attrs /= prevAttrs) $
    BS.hPut stdout $ sgrForAttrs attrs
  BS.hPut stdout $ encodeUtf8 (T.singleton ch)
  renderCellsWithSGR attrs rest

-- | Generate an SGR escape sequence for the given attributes
sgrForAttrs :: Attrs -> BS.ByteString
sgrForAttrs attrs =
  let parts = ["0"]  -- always reset first for simplicity
        ++ ["1" | hasFlag attrBold attrs]
        ++ ["2" | hasFlag attrDim attrs]
        ++ ["4" | hasFlag attrUnderline attrs]
        ++ ["7" | hasFlag attrInverse attrs]
        ++ fgPart (aFg attrs)
        ++ bgPart (aBg attrs)
  in BS8.pack $ "\x1b[" ++ joinSemi parts ++ "m"
  where
    fgPart DefaultColor = []
    fgPart (Color256 c) = let n = fromIntegral c :: Int in
      if n < 8     then [show (30 + n)]
      else if n < 16 then [show (90 + n - 8)]
      else ["38", "5", show n]
    bgPart DefaultColor = []
    bgPart (Color256 c) = let n = fromIntegral c :: Int in
      if n < 8     then [show (40 + n)]
      else if n < 16 then [show (100 + n - 8)]
      else ["48", "5", show n]
    joinSemi [] = ""
    joinSemi [x] = x
    joinSemi (x:xs) = x ++ ";" ++ joinSemi xs

-- | Render a single pane (for incremental updates in split mode)
renderSinglePane :: TermState -> Pane -> Int -> IO ()
renderSinglePane ts pane paneId = do
  mwin <- getActiveWindow ts
  case mwin of
    Nothing -> pure ()
    Just (_, win) -> do
      layout <- readIORef (wLayout win)
      (totalW, totalH) <- getTermSize
      let (r, c, w, h) = findPaneRegion layout paneId totalW totalH
      when (w > 0 && h > 0) $ do
        vterm <- readIORef (pVTerm pane)
        renderVTermAt vterm r c w h
        -- Restore cursor to active pane
        activePid <- readIORef (wActive win)
        when (activePid == paneId) $ do
          let (cr, cc) = vtGetCursor vterm
          BS.hPut stdout $ BS8.pack $
            "\x1b[" ++ show (r + cr + 1) ++ ";" ++ show (c + cc + 1) ++ "H"
        hFlush stdout

-- | Main input loop
inputLoop :: TermState -> IO ()
inputLoop ts = go
  where
    go = do
      alive <- readIORef (tsRunning ts)
      when alive $ do
        threadWaitRead stdInput
        result <- try (PIO.fdRead stdInput 1) :: IO (Either SomeException ByteString)
        let c = case result of
              Left _  -> BS.empty
              Right bs -> bs
        unless (BS.null c) $ do
          let byte = BS.head c
          prefix <- readIORef (tsPrefix ts)

          -- Check copy mode first
          copyScroll <- readIORef (tsCopyScroll ts)
          if copyScroll > 0 then
            handleCopyModeKey ts byte
          else
            handleNormalInput ts byte c prefix

        go

-- | Handle normal (non-copy-mode) input
handleNormalInput :: TermState -> Word8 -> ByteString -> Bool -> IO ()
handleNormalInput ts byte c prefix = do
  let workDir = "."
  mActivePane <- getActivePane ts
  case mActivePane of
    Nothing -> pure ()
    Just pane -> do
      if prefix then do
        writeIORef (tsPrefix ts) False
        handlePrefixCommand ts byte pane
        drawStatusLine ts False
      else if byte == 2 then do
        writeIORef (tsPrefix ts) True
        drawStatusLine ts True
      else do
        overlay <- readIORef (pOverlay pane)
        if osVisible overlay then do
          let (overlay', action) = handleOverlayKey overlay byte
          writeIORef (pOverlay pane) overlay'
          case action of
            OASendMessage msg -> do
              let ov = addMessage User msg overlay'
              let ov' = setStatus "thinking..." ov
              writeIORef (pOverlay pane) ov'
              renderOverlayNow ov'
              void $ forkIO $ do
                agent <- readIORef (pAgent pane)
                let progressCb evType detail = do
                      let role = case evType :: T.Text of
                            "tool_use"    -> ToolUse
                            "tool_result" -> ToolResult
                            _             -> System
                      modifyIORef' (pOverlay pane) $
                        addMessage role detail . setStatus (evType <> "…")
                      ov'' <- readIORef (pOverlay pane)
                      renderOverlayNow ov''
                (agent', response) <- agentStepWith agent workDir msg (Just progressCb)
                writeIORef (pAgent pane) agent'
                modifyIORef' (pOverlay pane) (addMessage Assistant response . setStatus "idle")
                ov'' <- readIORef (pOverlay pane)
                renderOverlayNow ov''
            OAClose -> do
              writeIORef (pOverlay pane) overlay' { osVisible = False }
              renderAllPanes ts
              writePty (pPty pane) (BS.singleton 12)
            OANone ->
              renderOverlayNow overlay'
        else
          writePty (pPty pane) c

-- | Handle prefix commands
handlePrefixCommand :: TermState -> Word8 -> Pane -> IO ()
handlePrefixCommand ts byte pane = case chr (fromIntegral byte) of
  'q' -> writeIORef (tsRunning ts) False
  'd' -> writeIORef (tsRunning ts) False
  'b' -> writePty (pPty pane) (BS.singleton 2)
  'c' -> void $ createWindowWithPane ts
  'n' -> switchNextWindow ts 1
  'p' -> switchNextWindow ts (-1)
  '%' -> splitActivePane ts PVertical      -- vertical split
  '"' -> splitActivePane ts PHorizontal   -- horizontal split
  'o' -> cyclePaneInWindow ts             -- cycle panes
  'a' -> do
    ov <- readIORef (pOverlay pane)
    let ov' = ov { osVisible = not (osVisible ov) }
    writeIORef (pOverlay pane) ov'
    if osVisible ov'
      then renderOverlayNow ov'
      else do
        renderAllPanes ts
        writePty (pPty pane) (BS.singleton 12)
  '[' -> do
    -- Enter copy mode
    writeIORef (tsCopyScroll ts) 1
    renderCopyMode ts
  ch | isDigit ch -> do
    let idx = digitToInt ch
    windows <- readIORef (tsWindows ts)
    when (IM.member idx windows) $ switchToWindow ts idx
  _ -> pure ()

-- | Switch to next/previous window
switchNextWindow :: TermState -> Int -> IO ()
switchNextWindow ts dir = do
  active <- readIORef (tsActiveWin ts)
  windows <- readIORef (tsWindows ts)
  let keys = IM.keys windows
  case keys of
    [] -> pure ()
    _  -> case lookup active (zip keys [0..]) of
      Nothing -> pure ()
      Just curPos -> do
        let nextPos = (curPos + dir) `mod` length keys
            nextId = keys !! nextPos
        when (nextId /= active) $ switchToWindow ts nextId

-- | Handle keys in copy mode
handleCopyModeKey :: TermState -> Word8 -> IO ()
handleCopyModeKey ts byte = do
  scroll <- readIORef (tsCopyScroll ts)
  case byte of
    -- q or Escape: exit copy mode
    _ | byte == fromIntegral (ord 'q') || byte == 27 -> do
      writeIORef (tsCopyScroll ts) 0
      renderAllPanes ts
    -- k or Up arrow (handled via ESC sequence — just use k for now)
    _ | byte == fromIntegral (ord 'k') || byte == 16 -> do  -- k or Ctrl-P
      mPane <- getActivePane ts
      case mPane of
        Nothing -> pure ()
        Just pane -> do
          vterm <- readIORef (pVTerm pane)
          let maxScroll = vtScrollbackSize vterm
              newScroll = min maxScroll (scroll + 1)
          writeIORef (tsCopyScroll ts) newScroll
          renderCopyMode ts
    -- j or Down
    _ | byte == fromIntegral (ord 'j') || byte == 14 -> do  -- j or Ctrl-N
      let newScroll = max 1 (scroll - 1)
      writeIORef (tsCopyScroll ts) newScroll
      renderCopyMode ts
    -- Page up (Ctrl-U)
    _ | byte == 21 -> do
      (_, h) <- getTermSize
      mPane <- getActivePane ts
      case mPane of
        Nothing -> pure ()
        Just pane -> do
          vterm <- readIORef (pVTerm pane)
          let maxScroll = vtScrollbackSize vterm
              newScroll = min maxScroll (scroll + h `div` 2)
          writeIORef (tsCopyScroll ts) newScroll
          renderCopyMode ts
    -- Page down (Ctrl-D)
    _ | byte == 4 -> do
      (_, h) <- getTermSize
      let newScroll = max 1 (scroll - h `div` 2)
      writeIORef (tsCopyScroll ts) newScroll
      renderCopyMode ts
    _ -> pure ()  -- ignore other keys in copy mode

-- | Render the screen in copy mode (scrollback + current screen)
renderCopyMode :: TermState -> IO ()
renderCopyMode ts = do
  mPane <- getActivePane ts
  case mPane of
    Nothing -> pure ()
    Just pane -> do
      vterm <- readIORef (pVTerm pane)
      scroll <- readIORef (tsCopyScroll ts)
      (totalW, totalH) <- getTermSize
      let (vtW, vtH) = vtGetSize vterm
          w = min totalW vtW
          h = totalH
          sb = vtScrollbackLines vterm
          sbLen = vtScrollbackSize vterm
          -- Total virtual lines = scrollback + screen
          -- Display from (total - h - scroll + 1) to (total - scroll)
          -- where total = sbLen + vtH
      -- Clear screen
      BS.hPut stdout $ BS8.pack $
        "\x1b[1;" ++ show totalH ++ "r\x1b[2J\x1b[H"
      -- Render each display row
      forM_ [0 .. h - 1] $ \row -> do
        let virtualLine = (sbLen + vtH - h) - (scroll - 1) + row
        BS.hPut stdout $ BS8.pack $
          "\x1b[" ++ show (row + 1) ++ ";1H"
        if virtualLine < 0 then
          -- Before scrollback: empty
          BS.hPut stdout $ BS8.pack $ replicate w ' '
        else if virtualLine < sbLen then do
          -- In scrollback
          let sbIdx = sbLen - 1 - virtualLine  -- convert to list index
          if sbIdx >= 0 && sbIdx < length sb then do
            let sbRow = sb !! sbIdx
            -- Render this scrollback row
            BS.hPut stdout "\x1b[0m"
            renderCellsWithSGR defaultAttrs
              [if c < V.length sbRow then sbRow V.! c else defaultCell { cChar = ' ' }
              | c <- [0 .. w - 1]]
          else
            BS.hPut stdout $ BS8.pack $ replicate w ' '
        else do
          -- In current screen
          let screenRow = virtualLine - sbLen
          if screenRow >= 0 && screenRow < vtH then do
            BS.hPut stdout "\x1b[0m"
            renderCellsWithSGR defaultAttrs
              [vtGetCell screenRow col vterm | col <- [0 .. w - 1]]
          else
            BS.hPut stdout $ BS8.pack $ replicate w ' '
      BS.hPut stdout "\x1b[0m"
      -- Draw copy mode status
      drawCopyModeStatus ts scroll sbLen
      hFlush stdout

-- | Draw copy mode status line
drawCopyModeStatus :: TermState -> Int -> Int -> IO ()
drawCopyModeStatus ts scroll totalScrollback = do
  cols <- readIORef (tsCols ts)
  (_, termH) <- getTermSize
  let statusRow = termH + 1
      statusText = " [copy mode] " ++ show scroll ++ "/" ++ show totalScrollback
                   ++ " | k/j:scroll Ctrl-U/D:page q:exit"
      padded = take cols (statusText ++ repeat ' ')
  BS.hPut stdout $ BS8.pack $
    "\x1b7\x1b[" ++ show statusRow ++ ";1H\x1b[43;30m"
    ++ padded ++ "\x1b[0m\x1b8"

-- | Draw status line
drawStatusLine :: TermState -> Bool -> IO ()
drawStatusLine ts prefix = do
  cols <- readIORef (tsCols ts)
  (_, termH) <- getTermSize
  let statusRow = termH + 1
  activeWin <- readIORef (tsActiveWin ts)
  windows <- readIORef (tsWindows ts)
  -- Also show pane count for active window
  paneCount <- case IM.lookup activeWin windows of
    Nothing -> pure 1
    Just win -> do
      layout <- readIORef (wLayout win)
      pure $ length (layoutPaneIds layout)
  let windowTags = map (formatWindowTag activeWin paneCount) (IM.toList windows)
      windowList = unwords windowTags
      statusText = if prefix
        then " tank | " ++ windowList ++ " | PREFIX (c new, %/\" split, o pane, a agent, q quit)"
        else " tank | " ++ windowList ++ " | ^B prefix"
      padded = take cols (statusText ++ repeat ' ')
  BS.hPut stdout $ BS8.pack $
    "\x1b7\x1b[" ++ show statusRow ++ ";1H\x1b[7m"
    ++ padded ++ "\x1b[0m\x1b8"
  hFlush stdout

-- | Format window tag: "0:sh[2]*" (2 panes, active)
formatWindowTag :: Int -> Int -> (Int, Window) -> String
formatWindowTag activeWin activePaneCount (winId, _win)
  | winId == activeWin && activePaneCount > 1 =
      show winId ++ ":sh[" ++ show activePaneCount ++ "]*"
  | winId == activeWin = show winId ++ ":sh*"
  | otherwise = show winId ++ ":sh"

-- | Render overlay
renderOverlayNow :: OverlayState -> IO ()
renderOverlayNow ov = do
  (w, rows) <- getTermSize
  BS.hPut stdout (renderOverlay ov w rows)
  hFlush stdout

-- | Handle resize
handleResizeAll :: TermState -> IO ()
handleResizeAll ts = do
  (cols, rows) <- getTermSize
  writeIORef (tsCols ts) cols
  -- Resize all panes in the active window based on layout
  mwin <- getActiveWindow ts
  case mwin of
    Nothing -> pure ()
    Just (_, win) -> do
      layout <- readIORef (wLayout win)
      resizePanesInLayout ts layout
  -- Update scroll region and redraw
  BS.hPut stdout $ BS8.pack $ "\x1b[1;" ++ show rows ++ "r"
  renderAllPanes ts

-- | Get terminal size (cols, rows excluding status line)
getTermSize :: IO (Int, Int)
getTermSize = do
  mSize <- TS.size :: IO (Maybe (TS.Window Int))
  pure $ case mSize of
    Just s  -> (TS.width s, TS.height s - 1)
    Nothing -> (80, 23)

getShell :: IO String
getShell = do
  mShell <- lookupEnv "SHELL"
  pure $ maybe "/bin/sh" id mShell

ptyToFd :: Pty -> Fd
ptyToFd = unsafeCoerce
