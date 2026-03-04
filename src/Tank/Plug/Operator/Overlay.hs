{-# LANGUAGE OverloadedStrings #-}

module Tank.Plug.Operator.Overlay
  ( OverlayState(..)
  , OverlayAction(..)
  , Role(..)
  , newOverlayState
  , renderOverlay
  , handleOverlayKey
  , addMessage
  , setStatus
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as B8
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word8)

data Role = User | Assistant | System | ToolUse | ToolResult
  deriving (Eq, Show)

data OverlayState = OverlayState
  { osVisible    :: !Bool
  , osMessages   :: ![(Role, Text)]
  , osInputBuf   :: !Text
  , osCursorPos  :: !Int
  , osScrollPos  :: !Int
  , osStatus     :: !Text
  } deriving (Show)

data OverlayAction
  = OASendMessage !Text
  | OAClose
  | OANone
  deriving (Eq, Show)

newOverlayState :: OverlayState
newOverlayState = OverlayState
  { osVisible   = False
  , osMessages  = []
  , osInputBuf  = ""
  , osCursorPos = 0
  , osScrollPos = 0
  , osStatus    = "idle"
  }

-- | Render the overlay as raw ANSI escape sequences.
-- Returns a ByteString that, when written to the terminal, draws a floating
-- box on the right side without clearing the content behind it.
renderOverlay :: OverlayState -> Int -> Int -> ByteString
renderOverlay _st termW termH
  | termW < 20 || termH < 5 = B8.empty
renderOverlay st termW termH =
  let boxW = min 60 (termW * 40 `div` 100)
      boxH = termH - 2
      innerW = boxW - 2   -- space inside the vertical borders
      startCol = termW - boxW + 1

      -- Format all messages into display lines
      allLines = concatMap (formatMessage innerW) (osMessages st)
      totalLines = length allLines

      -- Reserve 2 lines inside the box for the input area (separator + input)
      msgAreaH = boxH - 2
      -- Clamp scroll position
      maxScroll = max 0 (totalLines - msgAreaH)
      scroll = min (osScrollPos st) maxScroll
      -- Visible message lines
      visibleMsgLines = take msgAreaH (drop scroll allLines)
      -- Pad to fill message area
      paddedMsgLines = take msgAreaH (visibleMsgLines ++ repeat "")

      -- Input line: "> input█" truncated to fit
      inputText = "> " <> T.take (innerW - 3) (osInputBuf st) <> "\x2588"
      inputLine = padLine innerW inputText

      -- Title bar
      titleTag = "\x2524 tank operator \x251C"
      titleTagLen = T.length titleTag
      topBorder = "\x250C" <> "\x2500"
                  <> titleTag
                  <> T.replicate (boxW - 2 - 1 - titleTagLen) "\x2500"
                  <> "\x2510"

      -- Status bar in bottom border
      statusTag = "\x2500\x2524 " <> T.take (innerW - 4) (osStatus st) <> " \x251C"
      statusTagLen = T.length statusTag
      bottomBorder = "\x2514"
                     <> statusTag
                     <> T.replicate (boxW - 1 - statusTagLen) "\x2500"
                     <> "\x2518"

      -- Build output: save cursor, draw rows, restore cursor
      header = B8.pack "\x1b7"  -- save cursor
      footer = B8.pack "\x1b8"  -- restore cursor

      drawLine row txt = moveTo row startCol <> encodeUtf8 txt

      -- Row 1: top border
      rows = [drawLine 1 topBorder]
          ++ [drawLine (r + 2) (boxedLine innerW ln) | (r, ln) <- zip [0..] paddedMsgLines]
          ++ [drawLine (msgAreaH + 2) (boxedLine innerW inputLine)]
          ++ [drawLine (msgAreaH + 3) bottomBorder]

  in header <> B8.concat rows <> footer

-- | Move cursor to (row, col) using ANSI escape.
moveTo :: Int -> Int -> ByteString
moveTo row col = B8.pack ("\x1b[" ++ show row ++ ";" ++ show col ++ "H")

-- | Wrap a content line with box-drawing vertical borders.
boxedLine :: Int -> Text -> Text
boxedLine innerW content =
  "\x2502" <> padLine innerW content <> "\x2502"

-- | Pad or truncate a text line to exactly the given width.
padLine :: Int -> Text -> Text
padLine w t
  | T.length t >= w = T.take w t
  | otherwise       = t <> T.replicate (w - T.length t) " "

-- | Format a message into display lines, wrapping to fit the inner width.
formatMessage :: Int -> (Role, Text) -> [Text]
formatMessage innerW (role, content) =
  let prefix = case role of
        User       -> "> "
        Assistant  -> "  "
        System     -> "  "
        ToolUse    -> "  "
        ToolResult -> "  "
      formatted = case role of
        ToolUse    -> "[tool: " <> content <> "]"
        ToolResult -> "\x2192 " <> content
        _          -> content
      fullText = prefix <> formatted
  in wrapText innerW fullText

-- | Wrap a single text into lines of at most the given width.
wrapText :: Int -> Text -> [Text]
wrapText w t
  | w <= 0    = [""]
  | T.null t  = [""]
  | otherwise = go t
  where
    go remaining
      | T.null remaining = []
      | otherwise =
          let (line, rest) = T.splitAt w remaining
          in line : go rest

-- | Process a single byte of keyboard input.
handleOverlayKey :: OverlayState -> Word8 -> (OverlayState, OverlayAction)
handleOverlayKey st key
  -- Enter: send message
  | key == 13 =
      let msg = osInputBuf st
      in if T.null msg
         then (st, OANone)
         else (st { osInputBuf = "", osCursorPos = 0 }, OASendMessage msg)
  -- Escape: close overlay
  | key == 27 = (st, OAClose)
  -- Backspace (127): delete before cursor
  | key == 127 =
      let pos = osCursorPos st
          buf = osInputBuf st
      in if pos > 0
         then let (before, after) = T.splitAt pos buf
                  newBuf = T.init before <> after
              in (st { osInputBuf = newBuf, osCursorPos = pos - 1 }, OANone)
         else (st, OANone)
  -- Ctrl-P (16): scroll up
  | key == 16 =
      let newScroll = max 0 (osScrollPos st - 1)
      in (st { osScrollPos = newScroll }, OANone)
  -- Ctrl-N (14): scroll down
  | key == 14 =
      let newScroll = osScrollPos st + 1
      in (st { osScrollPos = newScroll }, OANone)
  -- Printable ASCII (32-126): insert character
  | key >= 32 && key <= 126 =
      let ch = toEnum (fromIntegral key) :: Char
          pos = osCursorPos st
          buf = osInputBuf st
          (before, after) = T.splitAt pos buf
          newBuf = before <> T.singleton ch <> after
      in (st { osInputBuf = newBuf, osCursorPos = pos + 1 }, OANone)
  -- Everything else: ignore
  | otherwise = (st, OANone)

-- | Append a message and auto-scroll to the bottom.
addMessage :: Role -> Text -> OverlayState -> OverlayState
addMessage role content st =
  let st' = st { osMessages = osMessages st ++ [(role, content)] }
  in st' { osScrollPos = maxScroll st' }
  where
    -- Compute a scroll value large enough to show the bottom.
    -- renderOverlay clamps it, so overshooting is fine.
    maxScroll s = length (osMessages s) * 10  -- generous upper bound

-- | Update the status text.
setStatus :: Text -> OverlayState -> OverlayState
setStatus s st = st { osStatus = s }
