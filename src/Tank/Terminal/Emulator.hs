{-# LANGUAGE OverloadedStrings #-}

-- | Minimal VT100/ANSI terminal emulator.
-- Parses a byte stream from a PTY and maintains a virtual screen grid.
module Tank.Terminal.Emulator
  ( VTerm
  , Cell(..)
  , Attrs(..)
  , Color(..)
  , mkVTerm
  , vtFeed
  , vtGetCell
  , vtGetCursor
  , vtGetSize
  , vtResize
  , vtRenderRegion
  , defaultAttrs
  , defaultCell
  , hasFlag
  , attrBold
  , attrDim
  , attrUnderline
  , attrInverse
  , vtScrollbackLines
  , vtScrollbackSize
  ) where

import Data.Bits (setBit, testBit, (.&.), complement)
import qualified Data.ByteString as BS
import Data.Char (chr, ord, isPrint)
import qualified Data.Vector as V
import qualified Data.Vector.Mutable as MV
import Data.Word (Word8)

-- | Terminal colors
data Color = DefaultColor | Color256 !Word8
  deriving (Eq, Show)

-- | Character attributes
data Attrs = Attrs
  { aFg     :: !Color
  , aBg     :: !Color
  , aFlags  :: !Word8  -- bit 0=bold, 1=underline, 2=inverse, 3=dim
  } deriving (Eq, Show)

defaultAttrs :: Attrs
defaultAttrs = Attrs DefaultColor DefaultColor 0

attrBold, attrUnderline, attrInverse, attrDim :: Word8
attrBold      = 0
attrUnderline = 1
attrInverse   = 2
attrDim       = 3

setFlag :: Word8 -> Attrs -> Attrs
setFlag bit a = a { aFlags = setBit (aFlags a) (fromIntegral bit) }

clearFlag :: Word8 -> Attrs -> Attrs
clearFlag bit a = a { aFlags = aFlags a .&. complement (setBit 0 (fromIntegral bit) :: Word8) }

hasFlag :: Word8 -> Attrs -> Bool
hasFlag bit a = testBit (aFlags a) (fromIntegral bit)

-- | A single cell on screen
data Cell = Cell
  { cChar  :: {-# UNPACK #-} !Char
  , cAttrs :: !Attrs
  } deriving (Eq, Show)

defaultCell :: Cell
defaultCell = Cell ' ' defaultAttrs

-- | Parser state
data ParseState = Ground | Escape | CSI | OSC
  deriving (Eq, Show)

-- | Virtual terminal state
data VTerm = VTerm
  { vtCols       :: !Int
  , vtRows       :: !Int
  , vtGrid       :: !(V.Vector (V.Vector Cell))  -- rows × cols
  , vtCursorR    :: !Int
  , vtCursorC    :: !Int
  , vtAttrs      :: !Attrs
  , vtState      :: !ParseState
  , vtParams     :: ![Int]        -- CSI parameter accumulator
  , vtCurParam   :: !Int          -- current param being built
  , vtHasParam   :: !Bool         -- whether we've seen any digit for current param
  , vtPrivate    :: !Bool         -- CSI ? prefix
  , vtSavedR     :: !Int
  , vtSavedC     :: !Int
  , vtScrollTop  :: !Int
  , vtScrollBot  :: !Int
  , vtAltGrid    :: !(V.Vector (V.Vector Cell))  -- alternate screen
  , vtOnAlt      :: !Bool
  , vtScrollback    :: ![V.Vector Cell]  -- scrollback buffer, most recent first
  , vtScrollbackLen :: !Int              -- current scrollback length
  , vtMaxScrollback :: !Int              -- max scrollback lines (default 1000)
  } deriving (Show)

-- | Create a new virtual terminal
mkVTerm :: Int -> Int -> VTerm
mkVTerm cols rows = VTerm
  { vtCols      = cols
  , vtRows      = rows
  , vtGrid      = emptyGrid cols rows
  , vtCursorR   = 0
  , vtCursorC   = 0
  , vtAttrs     = defaultAttrs
  , vtState     = Ground
  , vtParams    = []
  , vtCurParam  = 0
  , vtHasParam  = False
  , vtPrivate   = False
  , vtSavedR    = 0
  , vtSavedC    = 0
  , vtScrollTop = 0
  , vtScrollBot = rows - 1
  , vtAltGrid   = emptyGrid cols rows
  , vtOnAlt     = False
  , vtScrollback    = []
  , vtScrollbackLen = 0
  , vtMaxScrollback = 1000
  }

emptyGrid :: Int -> Int -> V.Vector (V.Vector Cell)
emptyGrid cols rows = V.replicate rows (V.replicate cols defaultCell)

emptyRow :: Int -> V.Vector Cell
emptyRow cols = V.replicate cols defaultCell

-- | Feed bytes into the terminal emulator, returns updated state
vtFeed :: BS.ByteString -> VTerm -> VTerm
vtFeed bs vt = BS.foldl' processByte vt bs

-- | Get cell at (row, col)
vtGetCell :: Int -> Int -> VTerm -> Cell
vtGetCell r c vt
  | r >= 0 && r < vtRows vt && c >= 0 && c < vtCols vt =
      (vtGrid vt V.! r) V.! c
  | otherwise = defaultCell

-- | Get cursor position (row, col)
vtGetCursor :: VTerm -> (Int, Int)
vtGetCursor vt = (vtCursorR vt, vtCursorC vt)

-- | Get terminal size (cols, rows)
vtGetSize :: VTerm -> (Int, Int)
vtGetSize vt = (vtCols vt, vtRows vt)

-- | Resize the terminal
vtResize :: Int -> Int -> VTerm -> VTerm
vtResize newCols newRows vt =
  let oldGrid = vtGrid vt
      newGrid = V.generate newRows $ \r ->
        if r < V.length oldGrid
          then let oldRow = oldGrid V.! r
               in V.generate newCols $ \c ->
                    if c < V.length oldRow then oldRow V.! c else defaultCell
          else emptyRow newCols
  in vt { vtCols = newCols
        , vtRows = newRows
        , vtGrid = newGrid
        , vtCursorR = min (vtCursorR vt) (newRows - 1)
        , vtCursorC = min (vtCursorC vt) (newCols - 1)
        , vtScrollTop = 0
        , vtScrollBot = newRows - 1
        }

-- | Render a region of the screen as ANSI escape sequences.
-- Renders rows [startRow..endRow) at terminal position (destRow, destCol).
vtRenderRegion :: VTerm -> Int -> Int -> Int -> Int -> BS.ByteString
vtRenderRegion vt startRow endRow destRow destCol =
  BS.concat [ renderRow r (destRow + r - startRow) | r <- [startRow .. endRow - 1] ]
  where
    renderRow r dr =
      let row = if r < vtRows vt then vtGrid vt V.! r else emptyRow (vtCols vt)
          moveTo = BS.pack $ map (fromIntegral . ord) $
            "\x1b[" ++ show (dr + 1) ++ ";" ++ show (destCol + 1) ++ "H"
          cells = BS.concat [ encodeCell (row V.! c) | c <- [0 .. min (vtCols vt) (V.length row) - 1] ]
      in moveTo <> cells

    encodeCell (Cell ch attrs) =
      let sgr = encodeSGR attrs
          chBs = BS.pack [fromIntegral (ord ch)]
      in sgr <> chBs

    encodeSGR attrs =
      let parts = ["0"]  -- reset first
            ++ (if hasFlag attrBold attrs then ["1"] else [])
            ++ (if hasFlag attrDim attrs then ["2"] else [])
            ++ (if hasFlag attrUnderline attrs then ["4"] else [])
            ++ (if hasFlag attrInverse attrs then ["7"] else [])
            ++ fgPart (aFg attrs)
            ++ bgPart (aBg attrs)
      in BS.pack $ map (fromIntegral . ord) $ "\x1b[" ++ joinWith ";" parts ++ "m"

    fgPart DefaultColor = []
    fgPart (Color256 c)
      | c < 8     = [show (30 + fromIntegral c)]
      | c < 16    = [show (90 + fromIntegral c - 8)]
      | otherwise = ["38", "5", show c]

    bgPart DefaultColor = []
    bgPart (Color256 c)
      | c < 8     = [show (40 + fromIntegral c)]
      | c < 16    = [show (100 + fromIntegral c - 8)]
      | otherwise = ["48", "5", show c]

    joinWith _ [] = ""
    joinWith _ [x] = x
    joinWith sep (x:xs) = x ++ sep ++ joinWith sep xs

-- | Get the number of scrollback lines
vtScrollbackSize :: VTerm -> Int
vtScrollbackSize = vtScrollbackLen

-- | Get scrollback lines (most recent first). Each line is a row of cells.
vtScrollbackLines :: VTerm -> [V.Vector Cell]
vtScrollbackLines = vtScrollback

-- Process a single byte through the state machine
processByte :: VTerm -> Word8 -> VTerm
processByte vt b = case vtState vt of
  Ground -> processGround vt b
  Escape -> processEscape vt b
  CSI    -> processCSI vt b
  OSC    -> processOSC vt b

processGround :: VTerm -> Word8 -> VTerm
processGround vt b
  | b == 0x1b = vt { vtState = Escape }          -- ESC
  | b == 0x07 = vt                                -- BEL (ignore)
  | b == 0x08 = cursorLeft vt                     -- BS
  | b == 0x09 = tabForward vt                     -- HT
  | b == 0x0a || b == 0x0b || b == 0x0c = lineFeed vt  -- LF, VT, FF
  | b == 0x0d = vt { vtCursorC = 0 }              -- CR
  | b >= 0x20 = putChar' vt (chr (fromIntegral b))
  | otherwise = vt  -- ignore other control chars

processEscape :: VTerm -> Word8 -> VTerm
processEscape vt b
  | b == 0x5b = vt { vtState = CSI, vtParams = [], vtCurParam = 0
                    , vtHasParam = False, vtPrivate = False }  -- [
  | b == 0x5d = vt { vtState = OSC }              -- ]
  | b == 0x37 = vt { vtState = Ground             -- 7 = save cursor
                    , vtSavedR = vtCursorR vt
                    , vtSavedC = vtCursorC vt }
  | b == 0x38 = vt { vtState = Ground             -- 8 = restore cursor
                    , vtCursorR = vtSavedR vt
                    , vtCursorC = vtSavedC vt }
  | b == 0x44 = lineFeed (vt { vtState = Ground })  -- D = index (IND)
  | b == 0x4d = reverseIndex (vt { vtState = Ground })  -- M = reverse index (RI)
  | b == 0x63 = mkVTerm (vtCols vt) (vtRows vt)     -- c = full reset (RIS)
  | otherwise = vt { vtState = Ground }            -- unknown, back to ground

processCSI :: VTerm -> Word8 -> VTerm
processCSI vt b
  | b == 0x3f = vt { vtPrivate = True }           -- ? prefix
  | b >= 0x30 && b <= 0x39 =                      -- digit
      vt { vtCurParam = vtCurParam vt * 10 + fromIntegral (b - 0x30)
         , vtHasParam = True }
  | b == 0x3b =                                   -- ; separator
      vt { vtParams = vtParams vt ++ [if vtHasParam vt then vtCurParam vt else 0]
         , vtCurParam = 0, vtHasParam = False }
  | b >= 0x40 =                                   -- final byte
      let params = vtParams vt ++ [if vtHasParam vt then vtCurParam vt else 0]
      in execCSI (vt { vtState = Ground }) params (vtPrivate vt) b
  | otherwise = vt                                -- intermediate bytes, ignore

processOSC :: VTerm -> Word8 -> VTerm
processOSC vt b
  | b == 0x07 = vt { vtState = Ground }           -- BEL terminates OSC
  | b == 0x1b = vt { vtState = Escape }           -- ESC might start ST
  | otherwise = vt                                -- absorb OSC content

-- Execute a CSI sequence
execCSI :: VTerm -> [Int] -> Bool -> Word8 -> VTerm
execCSI vt params private final
  -- Private mode set/reset (DECSET/DECRST)
  | private && final == 0x68 = execDECSET vt params  -- ?h
  | private && final == 0x6c = execDECRST vt params  -- ?l

  -- Cursor movement
  | final == 0x41 = moveCursor vt (-(param1 1)) 0    -- CUU (A)
  | final == 0x42 = moveCursor vt (param1 1) 0       -- CUD (B)
  | final == 0x43 = moveCursor vt 0 (param1 1)       -- CUF (C)
  | final == 0x44 = moveCursor vt 0 (-(param1 1))    -- CUB (D)
  | final == 0x48 || final == 0x66 =                  -- CUP (H/f)
      setCursor vt (param1 1 - 1) (param2 1 - 1)
  | final == 0x64 =                                   -- VPA (d) - line absolute
      vt { vtCursorR = clamp 0 (vtRows vt - 1) (param1 1 - 1) }
  | final == 0x47 =                                   -- CHA (G) - column absolute
      vt { vtCursorC = clamp 0 (vtCols vt - 1) (param1 1 - 1) }

  -- Erase
  | final == 0x4a = eraseDisplay vt (param1 0)        -- ED (J)
  | final == 0x4b = eraseLine vt (param1 0)           -- EL (K)
  | final == 0x58 = eraseChars vt (param1 1)          -- ECH (X)

  -- Line/char operations
  | final == 0x4c = insertLines vt (param1 1)         -- IL (L)
  | final == 0x4d = deleteLines vt (param1 1)         -- DL (M)
  | final == 0x40 = insertChars vt (param1 1)         -- ICH (@)
  | final == 0x50 = deleteChars vt (param1 1)         -- DCH (P)

  -- Scroll
  | final == 0x53 = scrollUp vt (param1 1)            -- SU (S)
  | final == 0x54 = scrollDown vt (param1 1)          -- SD (T)

  -- Scroll region
  | final == 0x72 =                                   -- DECSTBM (r)
      let top = param1 1 - 1
          bot = param2 (vtRows vt) - 1
      in vt { vtScrollTop = clamp 0 (vtRows vt - 1) top
            , vtScrollBot = clamp 0 (vtRows vt - 1) bot
            , vtCursorR = 0, vtCursorC = 0 }

  -- SGR
  | final == 0x6d = applySGR vt params                -- SGR (m)

  | otherwise = vt  -- unknown CSI, ignore
  where
    param1 def = case params of
      (p:_) | p /= 0 -> p
      _               -> def
    param2 def = case params of
      (_:p:_) | p /= 0 -> p
      _                 -> def

-- DECSET: set private mode
execDECSET :: VTerm -> [Int] -> VTerm
execDECSET vt [] = vt
execDECSET vt (p:ps) = execDECSET (setMode vt p) ps
  where
    setMode v 1049 = switchToAlt v   -- alt screen
    setMode v 47   = switchToAlt v
    setMode v 1047 = switchToAlt v
    setMode v _    = v

-- DECRST: reset private mode
execDECRST :: VTerm -> [Int] -> VTerm
execDECRST vt [] = vt
execDECRST vt (p:ps) = execDECRST (resetMode vt p) ps
  where
    resetMode v 1049 = switchFromAlt v
    resetMode v 47   = switchFromAlt v
    resetMode v 1047 = switchFromAlt v
    resetMode v _    = v

switchToAlt :: VTerm -> VTerm
switchToAlt vt
  | vtOnAlt vt = vt
  | otherwise  = vt { vtAltGrid = vtGrid vt
                     , vtGrid = emptyGrid (vtCols vt) (vtRows vt)
                     , vtOnAlt = True
                     , vtCursorR = 0, vtCursorC = 0 }

switchFromAlt :: VTerm -> VTerm
switchFromAlt vt
  | not (vtOnAlt vt) = vt
  | otherwise = vt { vtGrid = vtAltGrid vt
                    , vtAltGrid = emptyGrid (vtCols vt) (vtRows vt)
                    , vtOnAlt = False }

-- Apply SGR parameters
applySGR :: VTerm -> [Int] -> VTerm
applySGR vt [] = vt
applySGR vt [0] = vt { vtAttrs = defaultAttrs }
applySGR vt (p:ps) = applySGR (applyOneSGR vt p ps) (drop (consumed p ps) ps)
  where
    consumed 38 (5:_:_) = 2  -- skip the "5;n" part
    consumed 48 (5:_:_) = 2
    consumed _ _ = 0

applyOneSGR :: VTerm -> Int -> [Int] -> VTerm
applyOneSGR vt p rest = case p of
  0  -> vt { vtAttrs = defaultAttrs }
  1  -> vt { vtAttrs = setFlag attrBold (vtAttrs vt) }
  2  -> vt { vtAttrs = setFlag attrDim (vtAttrs vt) }
  4  -> vt { vtAttrs = setFlag attrUnderline (vtAttrs vt) }
  7  -> vt { vtAttrs = setFlag attrInverse (vtAttrs vt) }
  21 -> vt { vtAttrs = clearFlag attrBold (vtAttrs vt) }
  22 -> vt { vtAttrs = clearFlag attrBold . clearFlag attrDim $ vtAttrs vt }
  24 -> vt { vtAttrs = clearFlag attrUnderline (vtAttrs vt) }
  27 -> vt { vtAttrs = clearFlag attrInverse (vtAttrs vt) }
  -- Foreground colors
  n | n >= 30 && n <= 37 -> vt { vtAttrs = (vtAttrs vt) { aFg = Color256 (fromIntegral (n - 30)) } }
  39 -> vt { vtAttrs = (vtAttrs vt) { aFg = DefaultColor } }
  n | n >= 90 && n <= 97 -> vt { vtAttrs = (vtAttrs vt) { aFg = Color256 (fromIntegral (n - 90 + 8)) } }
  -- Background colors
  n | n >= 40 && n <= 47 -> vt { vtAttrs = (vtAttrs vt) { aBg = Color256 (fromIntegral (n - 40)) } }
  49 -> vt { vtAttrs = (vtAttrs vt) { aBg = DefaultColor } }
  n | n >= 100 && n <= 107 -> vt { vtAttrs = (vtAttrs vt) { aBg = Color256 (fromIntegral (n - 100 + 8)) } }
  -- 256-color: 38;5;n or 48;5;n
  38 | (5:c:_) <- rest -> vt { vtAttrs = (vtAttrs vt) { aFg = Color256 (fromIntegral c) } }
  48 | (5:c:_) <- rest -> vt { vtAttrs = (vtAttrs vt) { aBg = Color256 (fromIntegral c) } }
  _  -> vt  -- unknown SGR param

-- Put a printable character at cursor, advance cursor
putChar' :: VTerm -> Char -> VTerm
putChar' vt ch =
  let r = vtCursorR vt
      c = vtCursorC vt
      cell = Cell ch (vtAttrs vt)
      vt' = if r >= 0 && r < vtRows vt && c >= 0 && c < vtCols vt
            then vt { vtGrid = modifyCell r c cell (vtGrid vt) }
            else vt
  in if c + 1 >= vtCols vt'
     then wrapCursor vt'
     else vt' { vtCursorC = c + 1 }

wrapCursor :: VTerm -> VTerm
wrapCursor vt =
  let r = vtCursorR vt
  in if r >= vtScrollBot vt
     then scrollUp (vt { vtCursorC = 0 }) 1
     else vt { vtCursorR = r + 1, vtCursorC = 0 }

-- Modify a single cell in the grid
modifyCell :: Int -> Int -> Cell -> V.Vector (V.Vector Cell) -> V.Vector (V.Vector Cell)
modifyCell r c cell grid =
  let row = grid V.! r
      row' = V.modify (\mv -> MV.write mv c cell) row
  in V.modify (\mv -> MV.write mv r row') grid

-- Cursor movement
cursorLeft :: VTerm -> VTerm
cursorLeft vt = vt { vtCursorC = max 0 (vtCursorC vt - 1) }

moveCursor :: VTerm -> Int -> Int -> VTerm
moveCursor vt dr dc = vt
  { vtCursorR = clamp 0 (vtRows vt - 1) (vtCursorR vt + dr)
  , vtCursorC = clamp 0 (vtCols vt - 1) (vtCursorC vt + dc)
  }

setCursor :: VTerm -> Int -> Int -> VTerm
setCursor vt r c = vt
  { vtCursorR = clamp 0 (vtRows vt - 1) r
  , vtCursorC = clamp 0 (vtCols vt - 1) c
  }

tabForward :: VTerm -> VTerm
tabForward vt =
  let c = vtCursorC vt
      nextTab = ((c `div` 8) + 1) * 8
  in vt { vtCursorC = min (vtCols vt - 1) nextTab }

-- Line feed: move cursor down, scroll if at bottom of scroll region
lineFeed :: VTerm -> VTerm
lineFeed vt
  | vtCursorR vt >= vtScrollBot vt = scrollUp vt 1
  | otherwise = vt { vtCursorR = vtCursorR vt + 1 }

-- Reverse index: move cursor up, scroll down if at top of scroll region
reverseIndex :: VTerm -> VTerm
reverseIndex vt
  | vtCursorR vt <= vtScrollTop vt = scrollDown vt 1
  | otherwise = vt { vtCursorR = vtCursorR vt - 1 }

-- Scroll up: remove top line of scroll region, add blank at bottom.
-- When scrolling the full screen (not alt screen), save lines to scrollback.
scrollUp :: VTerm -> Int -> VTerm
scrollUp vt 0 = vt
scrollUp vt n =
  let top = vtScrollTop vt
      bot = vtScrollBot vt
      grid = vtGrid vt
      blank = emptyRow (vtCols vt)
      count = min n (bot - top + 1)
      -- Save scrolled-off lines to scrollback (only for full-screen scroll, not alt)
      isFullScreen = top == 0 && bot == vtRows vt - 1 && not (vtOnAlt vt)
      scrolledRows = if isFullScreen
                     then [grid V.! r | r <- [top .. top + count - 1]]
                     else []
      newScrollback = take (vtMaxScrollback vt)
                        (reverse scrolledRows ++ vtScrollback vt)
      newScrollbackLen = min (vtMaxScrollback vt)
                           (vtScrollbackLen vt + length scrolledRows)
      -- Shift lines up within scroll region
      grid' = V.modify (\mv -> do
        mapM_ (\r -> do
          if r + count <= bot
            then MV.write mv r (grid V.! (r + count))
            else MV.write mv r blank
          ) [top .. bot]
        ) grid
  in vt { vtGrid = grid'
        , vtScrollback = newScrollback
        , vtScrollbackLen = newScrollbackLen
        }

-- Scroll down: add blank at top of scroll region, push lines down
scrollDown :: VTerm -> Int -> VTerm
scrollDown vt 0 = vt
scrollDown vt n =
  let top = vtScrollTop vt
      bot = vtScrollBot vt
      grid = vtGrid vt
      blank = emptyRow (vtCols vt)
      grid' = V.modify (\mv -> do
        let count = min n (bot - top + 1)
        mapM_ (\r -> do
          if r - count >= top
            then MV.write mv r (grid V.! (r - count))
            else MV.write mv r blank
          ) (reverse [top .. bot])
        ) grid
  in vt { vtGrid = grid' }

-- Erase display
eraseDisplay :: VTerm -> Int -> VTerm
eraseDisplay vt mode =
  let r = vtCursorR vt
      c = vtCursorC vt
      blank = defaultCell
      grid = vtGrid vt
  in case mode of
    0 -> -- Erase below (from cursor to end)
      vt { vtGrid = V.modify (\mv -> do
        -- Clear rest of current line
        let row = grid V.! r
        MV.write mv r (V.modify (\rv -> mapM_ (\col -> MV.write rv col blank) [c .. vtCols vt - 1]) row)
        -- Clear lines below
        mapM_ (\row' -> MV.write mv row' (emptyRow (vtCols vt))) [r + 1 .. vtRows vt - 1]
        ) grid }
    1 -> -- Erase above (from start to cursor)
      vt { vtGrid = V.modify (\mv -> do
        mapM_ (\row' -> MV.write mv row' (emptyRow (vtCols vt))) [0 .. r - 1]
        let row = grid V.! r
        MV.write mv r (V.modify (\rv -> mapM_ (\col -> MV.write rv col blank) [0 .. c]) row)
        ) grid }
    2 -> -- Erase all
      vt { vtGrid = emptyGrid (vtCols vt) (vtRows vt) }
    3 -> -- Erase all + scrollback (we don't have scrollback yet)
      vt { vtGrid = emptyGrid (vtCols vt) (vtRows vt) }
    _ -> vt

-- Erase in line
eraseLine :: VTerm -> Int -> VTerm
eraseLine vt mode =
  let r = vtCursorR vt
      c = vtCursorC vt
      blank = defaultCell
      grid = vtGrid vt
      row = grid V.! r
      row' = case mode of
        0 -> V.modify (\rv -> mapM_ (\col -> MV.write rv col blank) [c .. vtCols vt - 1]) row
        1 -> V.modify (\rv -> mapM_ (\col -> MV.write rv col blank) [0 .. c]) row
        2 -> emptyRow (vtCols vt)
        _ -> row
  in vt { vtGrid = V.modify (\mv -> MV.write mv r row') grid }

-- Erase characters at cursor
eraseChars :: VTerm -> Int -> VTerm
eraseChars vt n =
  let r = vtCursorR vt
      c = vtCursorC vt
      blank = defaultCell
      grid = vtGrid vt
      row = grid V.! r
      row' = V.modify (\rv -> mapM_ (\col -> MV.write rv col blank) [c .. min (vtCols vt - 1) (c + n - 1)]) row
  in vt { vtGrid = V.modify (\mv -> MV.write mv r row') grid }

-- Insert lines at cursor
insertLines :: VTerm -> Int -> VTerm
insertLines vt n =
  let r = vtCursorR vt
      bot = vtScrollBot vt
  in if r < vtScrollTop vt || r > bot then vt
     else let grid = vtGrid vt
              blank = emptyRow (vtCols vt)
              grid' = V.modify (\mv -> do
                mapM_ (\row -> do
                  if row - n >= r
                    then MV.write mv row (grid V.! (row - n))
                    else MV.write mv row blank
                  ) (reverse [r .. bot])
                ) grid
          in vt { vtGrid = grid' }

-- Delete lines at cursor
deleteLines :: VTerm -> Int -> VTerm
deleteLines vt n =
  let r = vtCursorR vt
      bot = vtScrollBot vt
  in if r < vtScrollTop vt || r > bot then vt
     else let grid = vtGrid vt
              blank = emptyRow (vtCols vt)
              grid' = V.modify (\mv -> do
                mapM_ (\row -> do
                  if row + n <= bot
                    then MV.write mv row (grid V.! (row + n))
                    else MV.write mv row blank
                  ) [r .. bot]
                ) grid
          in vt { vtGrid = grid' }

-- Insert characters at cursor
insertChars :: VTerm -> Int -> VTerm
insertChars vt n =
  let r = vtCursorR vt
      c = vtCursorC vt
      grid = vtGrid vt
      row = grid V.! r
      blank = defaultCell
      row' = V.modify (\rv -> do
        mapM_ (\col -> do
          if col - n >= c
            then MV.write rv col (row V.! (col - n))
            else MV.write rv col blank
          ) (reverse [c .. vtCols vt - 1])
        ) row
  in vt { vtGrid = V.modify (\mv -> MV.write mv r row') grid }

-- Delete characters at cursor
deleteChars :: VTerm -> Int -> VTerm
deleteChars vt n =
  let r = vtCursorR vt
      c = vtCursorC vt
      grid = vtGrid vt
      row = grid V.! r
      blank = defaultCell
      row' = V.modify (\rv -> do
        mapM_ (\col -> do
          if col + n < vtCols vt
            then MV.write rv col (row V.! (col + n))
            else MV.write rv col blank
          ) [c .. vtCols vt - 1]
        ) row
  in vt { vtGrid = V.modify (\mv -> MV.write mv r row') grid }

clamp :: Int -> Int -> Int -> Int
clamp lo hi x = max lo (min hi x)
