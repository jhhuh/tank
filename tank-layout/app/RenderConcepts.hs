{-# LANGUAGE OverloadedStrings #-}
module Main where

import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.FilePath ((</>))

import Tank.Layout

-- ============================================================
-- Tokyo Night color palette
-- ============================================================

bg, fg, dim, blue, green, red, yellow, purple, orange, cyan, grey, barBg :: Color
bg     = RGB 26 27 38
fg     = RGB 192 202 245
dim    = RGB 86 95 137
blue   = RGB 122 162 247
green  = RGB 158 206 106
red    = RGB 247 118 142
yellow = RGB 224 175 104
purple = RGB 187 154 247
orange = RGB 255 158 100
cyan   = RGB 125 207 255
grey   = RGB 169 177 214
barBg  = RGB 36 40 59

-- ============================================================
-- Span helpers
-- ============================================================

-- | Plain text span (default color)
s :: Text -> Span
s = plainSpan

-- | Colored span
c :: Color -> Text -> Span
c col t = Span t (SpanStyle (Just col) False False)

-- | Bold colored span
b :: Color -> Text -> Span
b col t = Span t (SpanStyle (Just col) True False)

-- | Dim colored span
d :: Color -> Text -> Span
d col t = Span t (SpanStyle (Just col) False True)

-- | Newline span
nl :: Span
nl = s "\n"

-- ============================================================
-- Layout helpers
-- ============================================================

-- | Terminal width/height constants
termW, termH :: Int
termW = 120
termH = 36

-- | Build a status bar row from left and right span lists
statusBar :: [Span] -> [Span] -> [Span]
statusBar left right =
  let leftText = T.concat [t | Span t _ <- left]
      rightText = T.concat [t | Span t _ <- right]
      leftLen = T.length leftText
      rightLen = T.length rightText
      gap = max 0 (termW - leftLen - rightLen)
  in left ++ [Span (T.replicate gap " ") (SpanStyle (Just barBg) False False)] ++ right

-- | Create a status bar layout with background
statusBarLayout :: [Span] -> [Span] -> Layout
statusBarLayout left right =
  Styled defaultStyle { sBg = Just barBg }
    (spans (statusBar left right))

-- | Full-width line padded to terminal width
padLine :: [Span] -> [Span]
padLine ss =
  let len = sum [T.length t | Span t _ <- ss]
      gap = max 0 (termW - len)
  in ss ++ [s (T.replicate gap " ")]

-- | Build a full scenario with content lines and status bar
scenario :: [[Span]] -> [Span] -> [Span] -> Layout
scenario contentLines barLeft barRight =
  let totalLines = length contentLines
      padded = contentLines ++ replicate (max 0 (termH - 1 - totalLines)) [s (T.replicate termW " ")]
      allSpans = concatMap (\l -> padLine l ++ [nl]) (init padded) ++ padLine (last padded)
  in withStatusBar (spans allSpans) (statusBar barLeft barRight)

-- | Prompt helper
prompt :: Text -> [Span]
prompt path = [c blue path, s " ", c green ">", s " "]

defaultPrompt :: [Span]
defaultPrompt = prompt "~/projects/webapp"

-- | Rounded bordered overlay with title
overlayBox :: Text -> Text -> Int -> Int -> [[Span]] -> Layout
overlayBox title_ hint boxW boxH contentLines =
  let inner = boxW - 4  -- 2 for border, 2 for padding spaces
      titleGap = max 0 (inner - T.length title_ - T.length hint)
      titleLine = [b blue title_, s (T.replicate titleGap " "), d dim hint]
      paddedContent = map (padInner inner) contentLines
      -- total rows inside box: title(1) + sep(1) + content + sep(1) + input(1) = content + 4
      contentRows = boxH - 6  -- top border, title, sep, ..., sep, input, bottom border
      filledContent = take contentRows (paddedContent ++ repeat [s (T.replicate inner " ")])
      inputLine = [padInner inner [d dim "> _"]]
      allInner = [titleLine] ++ [sepLine inner] ++ filledContent ++ [sepLine inner] ++ inputLine
      allSpans = concatMap (\l -> l ++ [nl]) (init allInner) ++ last allInner
  in Styled defaultStyle
       { sBorder = Just (Border Rounded blue)
       , sTitle = Nothing
       }
       (spans allSpans)

-- | Pad inner content of a box to given width
padInner :: Int -> [Span] -> [Span]
padInner w ss =
  let len = sum [T.length t | Span t _ <- ss]
      gap = max 0 (w - len)
  in ss ++ [s (T.replicate gap " ")]

-- | Separator line for box interior
sepLine :: Int -> [Span]
sepLine _w = []  -- the border system handles horizontal lines via sep

-- Wait, the Python uses box_sep which draws ├───┤ lines. In the eDSL we can't
-- easily do that inside content. Let me reconsider the approach.
-- Actually, looking at the Python more carefully, each overlay is built manually
-- with box_top, box_mid, box_sep, box_bot. In our eDSL, we have bordered/roundBordered
-- which adds a border automatically. The separators (├───┤) inside the content
-- would need to be content that draws those characters.
--
-- For the concept images, let me build the overlays using the Styled/border approach
-- for the outer box, and use horizontal line characters for internal separators.

-- | Horizontal separator characters for inside a box
hline :: Int -> Text
hline w = T.replicate w "\x2500"  -- ─

-- | Interior separator: full-width line of ─
interiorSep :: Int -> [Span]
interiorSep w = [c blue (hline w)]

-- ============================================================
-- Scenario 01: Idle terminal
-- ============================================================

scenario01 :: Layout
scenario01 =
  let content =
        [ [s " "] ++ defaultPrompt ++ [s "git status"]
        , [s " ", c grey "On branch main"]
        , [s " ", c grey "Changes not staged for commit:"]
        , [s "   ", c red "modified:   src/App.tsx"]
        , [s "   ", c red "modified:   src/api/client.ts"]
        , [s " ", c grey "Untracked files:"]
        , [s "   ", c green "src/components/Dashboard.tsx"]
        , []
        , [s " "] ++ defaultPrompt ++ [s "npm test"]
        , [s " ", c grey "PASS  src/App.test.tsx"]
        , [s "   ", c green "ok renders without crashing (12ms)"]
        , [s "   ", c green "ok displays navigation (8ms)"]
        , [s " ", c red "FAIL  src/api/client.test.ts"]
        , [s "   ", c red "x  handles timeout errors (15ms)"]
        , [s " ", c grey "Tests: 1 failed, 2 passed, 3 total"]
        , []
        , [s " "] ++ defaultPrompt ++ [s "_"]
        ]
      barLeft = [s " ", b green "tank", s " ", d dim "|", s " ", c blue "0:bash", s " ", d dim "|", s " ", c grey "~/projects/webapp"]
      barRight = [d dim "Ctrl-B a: agent", s " ", d dim "|", s " ", c grey "idle"]
  in scenario content barLeft barRight

-- ============================================================
-- Scenario 02: Overlay (agent popup)
-- ============================================================

scenario02 :: Layout
scenario02 =
  let termContent =
        [ [s " "] ++ defaultPrompt ++ [s "npm test"]
        , [s " ", c grey "PASS  src/App.test.tsx"]
        , [s "   ", c green "ok renders without crashing (12ms)"]
        , [s " ", c red "FAIL  src/api/client.test.ts"]
        , [s "   ", c red "x  handles timeout errors (15ms)"]
        , [s " ", c grey "Tests: 1 failed, 2 passed, 3 total"]
        , []
        , [s " "] ++ defaultPrompt ++ [s "_"]
        ]

      overlayH = 17
      overlayW = termW
      inner = overlayW - 4  -- inside border + 1 space each side

      titleGap = T.replicate (max 0 (inner - T.length "operator" - T.length "Esc: close")) " "
      overlayContent =
        [ [b blue "operator", s titleGap, d dim "Esc: close"]
        , interiorSep inner
        , [d dim "you"]
        , [c fg "The timeout test is failing. Can you fix src/api/client.ts so it properly handles"]
        , [c fg "timeout errors?"]
        , []
        , [c blue "agent"]
        , [c fg "I'll take a look at the test and the client code."]
        , []
        , [c yellow "> read_file: src/api/client.test.ts"]
        , [c green "  -> 42 lines read"]
        , [c yellow "> read_file: src/api/client.ts"]
        , [c purple "  ~ reading..."]
        , interiorSep inner
        , [d dim "> _"]
        ]

      overlaySpans = concatMap (\l -> padInner inner l ++ [nl])
                               (init overlayContent)
                     ++ padInner inner (last overlayContent)

      overlayLayout = Styled defaultStyle
        { sBorder = Just (Border Rounded blue) }
        (spans overlaySpans)

      -- Terminal content lines (padded to fill above overlay)
      totalTermLines = termH - 1 - overlayH  -- -1 for status bar
      paddedTerm = termContent ++ replicate (max 0 (totalTermLines - length termContent)) []
      termSpans = concatMap (\l -> padLine l ++ [nl]) (init paddedTerm) ++ padLine (last paddedTerm)

      termLayout = spans termSpans

      combined = Layers
        (vsplit (fromIntegral (termH - 1) / fromIntegral termH) termLayout (spans []))
        [(Bottom, overlayLayout)]

      barLeft = [s " ", b green "tank", s " ", d dim "|", s " ", c blue "0:bash", s " ", d dim "|", s " ", c grey "~/projects/webapp"]
      barRight = [d dim "Esc: close overlay", s " ", d dim "|", s " ", c yellow "reading"]
  in withStatusBar combined (statusBar barLeft barRight)

-- ============================================================
-- Scenario 03: Tool Exec (full-screen agent overlay)
-- ============================================================

scenario03 :: Layout
scenario03 =
  let inner = termW - 4

      titleGap = T.replicate (max 0 (inner - T.length "operator" - T.length "Esc: close")) " "

      contentLines =
        [ [b blue "operator", s titleGap, d dim "Esc: close"]
        , interiorSep inner
        , [c yellow "> read_file: src/api/client.test.ts"]
        , [c green "  -> 42 lines read"]
        , []
        , [c yellow "> read_file: src/api/client.ts"]
        , [c green "  -> 87 lines read"]
        , []
        , [c blue "agent"]
        , [c fg "The issue is in `fetchWithRetry`. The catch block doesn't distinguish timeout errors"]
        , [c fg "from network errors. I'll add an AbortController timeout check."]
        , []
        , [c yellow "> write_file: src/api/client.ts"]
        , [c green "  -> written (91 lines)"]
        , []
        , [c yellow "> execute: npm test"]
        , [c green "  -> Tests: 3 passed, 3 total"]
        , []
        , [c blue "agent"]
        , [c fg "Fixed! Added `AbortError` handling in the catch block. All 3 tests pass now."]
        ]

      -- pad to fill, leave room for sep+input+bottom = 3 lines inside border
      availRows = termH - 1 - 2 - 3  -- -1 status, -2 top+title border area, -3 bottom area
      paddedContent = take availRows (contentLines ++ repeat [])

      bottomLines =
        [ interiorSep inner
        , [d dim "> _"]
        ]

      allLines = paddedContent ++ bottomLines
      overlaySpans = concatMap (\l -> padInner inner l ++ [nl]) (init allLines)
                     ++ padInner inner (last allLines)

      overlayLayout = Styled defaultStyle
        { sBorder = Just (Border Rounded blue) }
        (spans overlaySpans)

      barLeft = [s " ", b green "tank", s " ", d dim "|", s " ", c blue "0:bash", s " ", d dim "|", s " ", c grey "~/projects/webapp"]
      barRight = [d dim "|", s " ", c green "done"]
  in withStatusBar overlayLayout (statusBar barLeft barRight)

-- ============================================================
-- Scenario 04: Multi-Pane (horizontal split: editor + tests)
-- ============================================================

scenario04 :: Layout
scenario04 =
  let half = termW `div` 2
      leftW = half - 1  -- account for divider

      leftLines =
        [ [s " ", d dim "src/api/client.ts"]
        , [s " ", d dim " 1", s "  ", c purple "import", s " { TimeoutError } ", c purple "from", s " ", c green "'./errors'"]
        , [s " ", d dim " 2"]
        , [s " ", d dim " 3", s "  ", c purple "export async function", s " ", c blue "fetchWithRetry", s "("]
        , [s " ", d dim " 4", s "    url: ", c green "string", s ","]
        , [s " ", d dim " 5", s "    retries = ", c orange "3", s ","]
        , [s " ", d dim " 6", s "    timeout = ", c orange "5000"]
        , [s " ", d dim " 7", s "  ) {"]
        , [s " ", d dim " 8", s "    ", c purple "const", s " ctrl = ", c purple "new", s " ", c blue "AbortController", s "()"]
        , [s " ", d dim " 9", s "    ", c purple "const", s " id = setTimeout("]
        , [s " ", d dim "10", s "      () => ctrl.abort(), timeout"]
        , [s " ", d dim "11", s "    )"]
        , [s " ", d dim "12", s "    ", c purple "try", s " {"]
        , [s " ", d dim "13", s "      ", c purple "return await", s " ", c blue "fetch", s "(url, {"]
        , [s " ", d dim "14", s "        signal: ctrl.signal"]
        , [s " ", d dim "15", s "      })"]
        , [s " ", d dim "16", s "    } ", c purple "catch", s " (e) {"]
        , [s " ", d dim "17", s "      ", c purple "if", s " (e.name === ", c green "'AbortError'", s ")"]
        , [s " ", d dim "18", s "        ", c purple "throw new", s " ", c blue "TimeoutError", s "(url)"]
        ]

      rightLines =
        [ [s " "] ++ defaultPrompt
        , [s " npm test -- --watch"]
        , [s " ", c grey "PASS  src/App.test.tsx"]
        , [s "   ", c green "ok renders without crashing (12ms)"]
        , [s "   ", c green "ok displays navigation (8ms)"]
        , [s " ", c grey "PASS  src/api/client.test.ts"]
        , [s "   ", c green "ok fetches data successfully (5ms)"]
        , [s "   ", c green "ok retries on failure (23ms)"]
        , [s "   ", c green "ok handles timeout errors (11ms)"]
        , []
        , [s " ", b green "Tests: 5 passed, 5 total"]
        , [s " ", c grey "Ran all test suites."]
        , []
        , [s " ", d dim "Watching for changes..."]
        ]

      totalRows = termH - 1
      paddedLeft = take totalRows (leftLines ++ repeat [])
      paddedRight = take totalRows (rightLines ++ repeat [])

      leftSpans = concatMap (\l -> padTo leftW l ++ [nl]) (init paddedLeft) ++ padTo leftW (last paddedLeft)
      rightSpans = concatMap (\l -> padTo half l ++ [nl]) (init paddedRight) ++ padTo half (last paddedRight)

      -- Divider column
      dividerSpans = concat $ replicate (totalRows - 1) [c green "\x2502", nl] ++ [[c green "\x2502"]]

      leftPane = spans leftSpans
      divider = spans dividerSpans
      rightPane = spans rightSpans

      mainContent = hsplit (fromIntegral leftW / fromIntegral termW)
                      leftPane
                      (hsplit (1.0 / fromIntegral (termW - leftW))
                        divider
                        rightPane)

      barLeft = [s " ", b green "tank", s " ", d dim "|", s " ", c blue "0:edit", s " ", c grey "1:test", s " ", d dim "|", s " ", c grey "2 panes"]
      barRight = [d dim "Ctrl-B a: agent", s " ", d dim "|", s " ", c grey "idle"]
  in withStatusBar mainContent (statusBar barLeft barRight)

-- ============================================================
-- Scenario 05: Multi-Agent
-- ============================================================

scenario05 :: Layout
scenario05 =
  let half = termW `div` 2
      lw = half - 1  -- left pane width (59)
      rw = half      -- right pane width (60)
      li = lw - 4    -- left inner (55)
      ri = rw - 4    -- right inner (56)

      -- Terminal content above overlays
      leftTermLines =
        [ [s " "] ++ defaultPrompt ++ [s "npm test -- --watch"]
        , [s " ", c grey "PASS  src/App.test.tsx"]
        , [s "   ", c green "ok renders without crashing"]
        , [s " ", c grey "PASS  src/api/client.test.ts"]
        , [s "   ", c green "ok fetches data successfully"]
        , [s "   ", c green "ok retries on failure"]
        , [s "   ", c red "x  handles concurrent requests"]
        , [s " ", c red "Tests: 1 failed, 3 passed"]
        , [s " ", d dim "Watching for changes..."]
        ]

      rightTermLines =
        [ [s " "] ++ defaultPrompt ++ [s "git log --oneline -3"]
        , [s " ", c grey "a1b2c3d fix: handle timeout errors"]
        , [s " ", c grey "e4f5g6h feat: add retry logic"]
        , [s " ", c grey "f7g8h9i refactor: split client"]
        , []
        , [s " "] ++ defaultPrompt ++ [s "_"]
        ]

      overlayH = 16
      termRows = termH - 1 - overlayH  -- rows for terminal content

      -- Left overlay content
      lgap = T.replicate (max 0 (li - T.length "operator" - T.length "Esc")) " "
      leftOverlayContent =
        [ [b blue "operator", s lgap, d dim "Esc"]
        , interiorSep li
        , [s " ", d dim "you"]
        , [s " ", c fg "Concurrent requests test"]
        , [s " ", c fg "failing. Investigate?"]
        , []
        , [s " ", c yellow "> read_file: client.test.ts"]
        , [s " ", c green "  -> 58 lines"]
        , []
        , [s " ", c blue "agent"]
        , [s " ", c fg "AbortController is shared."]
        , [s " ", c fg "Each call needs its own."]
        ]

      -- Right overlay content
      rgap = T.replicate (max 0 (ri - T.length "operator" - T.length "Esc")) " "
      rightOverlayContent =
        [ [b blue "operator", s rgap, d dim "Esc"]
        , interiorSep ri
        , [s " ", d dim "you"]
        , [s " ", c fg "Review error handling in"]
        , [s " ", c fg "the API client module."]
        , []
        , [s " ", c yellow "> read_file: client.ts"]
        , [s " ", c green "  -> 93 lines"]
        , []
        , [s " ", c blue "agent"]
        , [s " ", c fg "Retry logic looks solid."]
        , [s " ", c fg "Adding exponential backoff."]
        ]

      -- Build left overlay (10 content rows + title + sep + sep + input = 14 inside)
      contentRows = overlayH - 6  -- top, title, sep, ..., sep, input, bottom = 6 border rows
      leftOvPadded = take contentRows (leftOverlayContent ++ repeat [])
      leftOvBottom = [interiorSep li, [s " ", d dim "> _"]]
      leftOvAll = leftOvPadded ++ leftOvBottom
      leftOvSpans = concatMap (\l -> padInner li l ++ [nl]) (init leftOvAll) ++ padInner li (last leftOvAll)
      leftOverlay = Styled defaultStyle { sBorder = Just (Border Rounded blue) } (spans leftOvSpans)

      rightOvPadded = take contentRows (rightOverlayContent ++ repeat [])
      rightOvBottom = [interiorSep ri, [s " ", d dim "> _"]]
      rightOvAll = rightOvPadded ++ rightOvBottom
      rightOvSpans = concatMap (\l -> padInner ri l ++ [nl]) (init rightOvAll) ++ padInner ri (last rightOvAll)
      rightOverlay = Styled defaultStyle { sBorder = Just (Border Rounded blue) } (spans rightOvSpans)

      -- Build each pane as terminal + overlay
      paddedLeftTerm = take termRows (leftTermLines ++ repeat [])
      leftTermSpans = concatMap (\l -> padTo lw l ++ [nl]) (init paddedLeftTerm) ++ padTo lw (last paddedLeftTerm)
      leftPane = Layers (spans leftTermSpans) [(Bottom, leftOverlay)]

      paddedRightTerm = take termRows (rightTermLines ++ repeat [])
      rightTermSpans = concatMap (\l -> padTo rw l ++ [nl]) (init paddedRightTerm) ++ padTo rw (last paddedRightTerm)
      rightPane = Layers (spans rightTermSpans) [(Bottom, rightOverlay)]

      -- Divider between panes
      totalRows = termH - 1
      dividerSpans = concat $ replicate (totalRows - 1) [d dim "\x2502", nl] ++ [[d dim "\x2502"]]

      mainContent = hsplit (fromIntegral lw / fromIntegral termW)
                      leftPane
                      (hsplit (1.0 / fromIntegral (termW - lw))
                        (spans dividerSpans)
                        rightPane)

      barLeft = [s " ", b green "tank", s " ", d dim "|", s " ", c grey "0:test", s " ", c blue "1:shell", s " ", d dim "|", s " ", c grey "2 panes"]
      barRight = [d dim "Esc: close overlay", s " ", d dim "|", s " ", c yellow "writing", s " ", c green "done"]
  in withStatusBar mainContent (statusBar barLeft barRight)

-- ============================================================
-- Scenario 06: Windows (command palette)
-- ============================================================

scenario06 :: Layout
scenario06 =
  let termContent =
        [ [s " "] ++ defaultPrompt ++ [s "docker compose logs -f api"]
        , [s " ", c grey "api  | 2026-03-06 14:22:01 INFO  Server started on :8080"]
        , [s " ", c grey "api  | 2026-03-06 14:22:03 INFO  Connected to postgres"]
        , [s " ", c green "api  | 2026-03-06 14:22:15 INFO  GET /api/users 200 12ms"]
        , [s " ", c green "api  | 2026-03-06 14:22:16 INFO  GET /api/tasks 200 8ms"]
        , [s " ", c yellow "api  | 2026-03-06 14:22:18 WARN  Slow query (245ms)"]
        , [s " ", c green "api  | 2026-03-06 14:22:20 INFO  POST /api/tasks 201 15ms"]
        , [s " ", c red "api  | 2026-03-06 14:22:22 ERROR Connection reset by peer"]
        , [s " ", c green "api  | 2026-03-06 14:22:24 INFO  Reconnected to postgres"]
        ]

      -- Command palette overlay
      paletteW = 70
      paletteInner = paletteW - 4

      paletteContent =
        [ [b yellow "Ctrl-B commands (prefix mode)"]
        , interiorSep paletteInner
        , [s " ", c blue "c", s "       new window          ", c blue "o", s "       cycle panes"]
        , [s " ", c blue "n / p", s "   next / prev window  ", c blue "[", s "       copy mode (scroll)"]
        , [s " ", c blue "0-9", s "     switch to window N  ", b green "a", s "       ", c green "agent overlay"]
        , [s " ", c blue "%", s "       vertical split      ", c blue "d", s "       detach session"]
        , [s " ", c blue "\"", s "       horizontal split    ", c blue "x", s "       close pane"]
        ]

      paletteSpans = concatMap (\l -> padInner paletteInner l ++ [nl]) (init paletteContent)
                     ++ padInner paletteInner (last paletteContent)

      paletteOverlay = Styled defaultStyle
        { sBorder = Just (Border Rounded blue) }
        (spans paletteSpans)

      totalRows = termH - 1
      paddedTerm = take totalRows (termContent ++ repeat [])
      termSpans = concatMap (\l -> padLine l ++ [nl]) (init paddedTerm) ++ padLine (last paddedTerm)

      mainContent = Layers (spans termSpans) [(Center, paletteOverlay)]

      -- Highlight active window tab with inverted colors
      barLeft = [s " ", b green "tank", s " ", d dim "|", s " ", c grey "0:edit", s " ", c grey "1:test", s " ", Span " 2:logs " (SpanStyle (Just (RGB 26 27 38)) True False), s " ", c grey "3:shell", s " ", d dim "|", s " ", c grey "session: webapp-dev"]
      barRight = [d dim "Ctrl-B ?: help"]
  in withStatusBar mainContent (statusBar barLeft barRight)

-- ============================================================
-- Scenario 07: Services
-- ============================================================

scenario07 :: Layout
scenario07 =
  let termContent =
        [ [s " "] ++ defaultPrompt ++ [s "npm start"]
        , [s " ", c grey "Server running on http://localhost:3000"]
        , [s " ", c grey "Compiled successfully in 1.2s"]
        , []
        , [s " "] ++ defaultPrompt ++ [s "_"]
        ]

      ow = termW - 8
      inner = ow - 4
      leftW = 35
      rightW = inner - leftW - 3  -- 3 for " | "

      svcRow :: [Span] -> [Span] -> [Span]
      svcRow left right =
        let paddedLeft = left ++ [s (T.replicate (max 0 (leftW - spanLen left)) " ")]
            paddedRight = right ++ [s (T.replicate (max 0 (rightW - spanLen right)) " ")]
        in paddedLeft ++ [s " ", d dim "\x2502", s " "] ++ paddedRight

      titleText = "services  Procfile: ~/projects/webapp/Procfile"
      titleGap = T.replicate (max 0 (inner - T.length titleText - T.length "Esc: close")) " "

      overlayContent =
        [ [b cyan "services", s "  ", d dim "Procfile: ~/projects/webapp/Procfile", s titleGap, d dim "Esc: close"]
        , interiorSep inner
        -- Headers
        , svcRow [s " ", b blue "Services"] [s " ", b blue "Procfile Definition"]
        , svcRow [s " ", d dim (T.replicate 33 "\x2500")] [s " ", d dim (T.replicate (rightW - 1) "\x2500")]
        -- Service entries
        , svcRow [s " ", c green "\x25CF", s " ", b fg "api", s "          ", c green "running", s " ", d dim ":8080"]
                 [s " ", d dim "# API server"]
        , svcRow [s "   ", d dim "pid 42381 | 2m uptime"]
                 [s " ", c purple "api:", s " node dist/server.js"]
        , svcRow [s " ", c green "\x25CF", s " ", c fg "worker", s "       ", c green "running"]
                 []
        , svcRow [s "   ", d dim "pid 42382 | 2m uptime"]
                 [s " ", d dim "# Background job worker"]
        , svcRow [s " ", c red "\x25CF", s " ", c fg "db", s "           ", c red "crashed"]
                 [s " ", c purple "worker:", s " node dist/worker.js"]
        , svcRow [s "   ", c red "exit 1 | restarting..."]
                 []
        , svcRow [s " ", c green "\x25CF", s " ", c fg "redis", s "        ", c green "running", s " ", d dim ":6379"]
                 [s " ", d dim "# Database"]
        , svcRow [s "   ", d dim "pid 42384 | 2m uptime"]
                 [s " ", c purple "db:", s " postgres -D data/"]
        , svcRow [s " ", c yellow "\x25CF", s " ", c fg "proxy", s "        ", c yellow "starting", s " ", d dim ":443"]
                 []
        , svcRow [s "   ", d dim "pid 42385 | 0s uptime"]
                 [s " ", d dim "# Redis cache"]
        , svcRow [] [s " ", c purple "redis:", s " redis-server"]
        , svcRow [s " ", d dim "5 services | 3 running"] []
        , svcRow [s " ", d dim "1 crashed | 1 starting"]
                 [s " ", d dim "# Reverse proxy"]
        , svcRow [] [s " ", c purple "proxy:", s " caddy run"]
        , interiorSep inner
        , [s " ", d dim "r: restart  s: stop  l: logs  Enter: connect to service  q: quit"]
        ]

      overlaySpans = concatMap (\l -> padInner inner l ++ [nl]) (init overlayContent)
                     ++ padInner inner (last overlayContent)

      overlayLayout = Styled defaultStyle
        { sBorder = Just (Border Rounded blue) }
        (spans overlaySpans)

      totalRows = termH - 1
      paddedTerm = take totalRows (termContent ++ repeat [])
      termSpans = concatMap (\l -> padLine l ++ [nl]) (init paddedTerm) ++ padLine (last paddedTerm)

      mainContent = Layers (spans termSpans) [(Center, overlayLayout)]

      barLeft = [s " ", b green "tank", s " ", d dim "|", s " ", c blue "0:bash", s " ", d dim "|", s " ", c grey "~/projects/webapp"]
      barRight = [d dim "Ctrl-B s: services", s " ", d dim "|", s " ", c red "1 crashed"]
  in withStatusBar mainContent (statusBar barLeft barRight)

-- ============================================================
-- Scenario 08: Services Logs
-- ============================================================

scenario08 :: Layout
scenario08 =
  let termContent =
        [ [s " "] ++ defaultPrompt ++ [s "npm start"]
        , [s " ", c grey "Server running on http://localhost:3000"]
        , [s " ", c grey "Compiled successfully in 1.2s"]
        , []
        , [s " "] ++ defaultPrompt ++ [s "_"]
        ]

      ow = termW - 8
      inner = ow - 4
      rightCol = 32
      leftCol = inner - rightCol - 3  -- 3 for " | "

      svcRow :: [Span] -> [Span] -> [Span]
      svcRow left right =
        let paddedLeft = left ++ [s (T.replicate (max 0 (leftCol - spanLen left)) " ")]
            paddedRight = right ++ [s (T.replicate (max 0 (rightCol - spanLen right)) " ")]
        in paddedLeft ++ [s " ", d dim "\x2502", s " "] ++ paddedRight

      logHdiv :: [Span] -> [Span]
      logHdiv [] = [d dim (T.replicate leftCol "\x2500"), s " ", d dim "\x2502", s " ", s (T.replicate rightCol " ")]
      logHdiv label =
        let labelLen = spanLen label
            dashes = max 0 (leftCol - labelLen - 2)
        in [s " "] ++ label ++ [s " ", d dim (T.replicate dashes "\x2500"), s " ", d dim "\x2502", s " ", s (T.replicate rightCol " ")]

      titleGap = T.replicate (max 0 (inner - T.length "services  logs view" - T.length "Tab: tree  Esc: close")) " "

      overlayContent =
        [ [b cyan "services", s "  ", d dim "logs view", s titleGap, d dim "Tab: tree  Esc: close"]
        , interiorSep inner
        -- Header + logs
        , svcRow [s " ", b cyan "api", s " ", d dim ":8080"]
                 [s " ", b blue "Services"]
        , svcRow [s " ", c grey "14:22:15 GET /api/users 200 12ms"]
                 [s " ", d dim (T.replicate 30 "\x2500")]
        , svcRow [s " ", c grey "14:22:16 GET /api/tasks 200 8ms"]
                 [s " ", c green "\x25CF", s " ", b fg "api", s "      ", c green "running", s " ", d dim ":8080"]
        , svcRow [s " ", c yellow "14:22:18 WARN Slow query (245ms)"]
                 [s " ", c green "\x25CF", s " ", c fg "worker", s "   ", c green "running"]
        , svcRow [s " ", c grey "14:22:20 POST /api/tasks 201"]
                 [s " ", c red "\x25CF", s " ", c fg "db", s "       ", c red "crashed"]
        , svcRow [s " ", c grey "14:22:22 GET /api/health 200 1ms"]
                 [s " ", c green "\x25CF", s " ", c fg "redis", s "    ", c green "running", s " ", d dim ":6379"]
        , logHdiv [c cyan "worker"]
        , svcRow [s " ", c green "14:22:10 Job #4481 started"]
                 [s " ", c yellow "\x25CF", s " ", c fg "proxy", s "    ", c yellow "starting", s " ", d dim ":443"]
        , svcRow [s " ", c green "14:22:14 Job #4481 done (3.2s)"]
                 []
        , svcRow [s " ", c grey "14:22:20 Polling queue..."]
                 [s " ", d dim "5 services | 3 running"]
        , svcRow [s " ", c green "14:22:25 Job #4482 started"]
                 [s " ", d dim "1 crashed | 1 starting"]
        , logHdiv [c cyan "db", s " ", c red "crashed"]
        , svcRow [s " ", c yellow "14:22:15 WARN checkpoints frequent"]
                 []
        , svcRow [s " ", c red "14:22:18 FATAL data dir corrupted"]
                 []
        , svcRow [s " ", c red "14:22:18 server process exit 1"]
                 []
        , svcRow [s " ", c red "14:22:19 shutting down"]
                 []
        , svcRow [s " ", c yellow "14:22:20 restarting in 5s..."]
                 []
        , logHdiv [c cyan "redis", s " ", d dim ":6379"]
        , svcRow [s " ", c grey "14:22:15 # DB 0: 847 keys"]
                 []
        , svcRow [s " ", c grey "14:22:20 # Background saving OK"]
                 []
        , svcRow [s " ", c grey "14:22:25 # DB 0: 851 keys"]
                 []
        , svcRow [s " ", c grey "14:22:30 # 11 clients connected"]
                 []
        , interiorSep inner
        , [s " ", d dim "r: restart  s: stop  Tab: tree view  j/k: scroll  Enter: attach  q: quit"]
        ]

      overlaySpans = concatMap (\l -> padInner inner l ++ [nl]) (init overlayContent)
                     ++ padInner inner (last overlayContent)

      overlayLayout = Styled defaultStyle
        { sBorder = Just (Border Rounded blue) }
        (spans overlaySpans)

      totalRows = termH - 1
      paddedTerm = take totalRows (termContent ++ repeat [])
      termSpans = concatMap (\l -> padLine l ++ [nl]) (init paddedTerm) ++ padLine (last paddedTerm)

      mainContent = Layers (spans termSpans) [(Center, overlayLayout)]

      barLeft = [s " ", b green "tank", s " ", d dim "|", s " ", c blue "0:bash", s " ", d dim "|", s " ", c grey "~/projects/webapp"]
      barRight = [d dim "Ctrl-B s: services", s " ", d dim "|", s " ", c red "1 crashed"]
  in withStatusBar mainContent (statusBar barLeft barRight)

-- ============================================================
-- Scenario 09: Detach/Reattach (three stacked frames)
-- ============================================================

-- Frame 1: Active session
scenario09a :: Int -> Layout
scenario09a h =
  let content =
        [ [s " "] ++ defaultPrompt ++ [s "docker compose logs -f api"]
        , [s " ", c green "api  | 2026-03-06 14:23:05 INFO  Deploy v2.3.1 complete"]
        , [s " ", c grey "api  | 2026-03-06 14:23:10 INFO  GET /api/health 200 1ms"]
        , [s " ", c green "api  | 2026-03-06 14:23:12 INFO  GET /api/users 200 5ms"]
        , [s " ", c grey "api  | 2026-03-06 14:23:15 INFO  POST /api/tasks 201 12ms"]
        ]
      totalRows = h - 1
      paddedContent = take totalRows (content ++ repeat [])
      allSpans = concatMap (\l -> padLine l ++ [nl]) (init paddedContent) ++ padLine (last paddedContent)
      barLeft = [s " ", b green "tank", s " ", d dim "|", s " ", c grey "0:edit", s " ", c grey "1:test", s " ", Span " 2:logs " (SpanStyle (Just (RGB 26 27 38)) True False), s " ", c grey "3:shell", s " ", d dim "|", s " ", c grey "webapp-dev"]
      barRight = [d dim "|", s " ", c grey "idle"]
  in withStatusBar (spans allSpans) (statusBar barLeft barRight)

-- Frame 2: Shell after detach
scenario09b :: Int -> Layout
scenario09b h =
  let detachFg = RGB 26 27 38
      content =
        [ [Span " [detached (from session webapp-dev)]" (SpanStyle (Just detachFg) True False)]
        -- Note: the detach bar has yellow bg. We'll fake this as colored text for now.
        , []
        , [s " ", c (RGB 200 200 200) "$", s " ", c fg "tank list-sessions"]
        , [s " ", c green "webapp-dev", s ": 4 windows (attached: 0) ", c grey "[created 2h ago]"]
        , [s " ", c grey "backend", s ":    2 windows (attached: 0) ", c grey "[created 5h ago]"]
        , []
        , [s " ", c (RGB 200 200 200) "$", s " ", c fg "tank attach webapp-dev"]
        ]
      totalRows = h
      paddedContent = take totalRows (content ++ repeat [])
      allSpans = concatMap (\l -> padLine l ++ [nl]) (init paddedContent) ++ padLine (last paddedContent)
  in spans allSpans

-- Frame 3: Reattached session
scenario09c :: Int -> Layout
scenario09c h =
  let reattachFg = RGB 26 27 38
      content =
        [ [Span " [reattached to session webapp-dev -- 4 windows, all intact]" (SpanStyle (Just reattachFg) True False)]
        , []
        , [s " ", c grey "api  | ...2 hours of logs continued while detached..."]
        , [s " ", c green "api  | 2026-03-06 16:45:12 INFO  GET /api/users 200 3ms"]
        , [s " ", c green "api  | 2026-03-06 16:45:15 INFO  GET /api/tasks 200 4ms"]
        , [s " ", c grey "api  | 2026-03-06 16:45:20 INFO  GET /api/health 200 1ms"]
        ]
      totalRows = h - 1
      paddedContent = take totalRows (content ++ repeat [])
      allSpans = concatMap (\l -> padLine l ++ [nl]) (init paddedContent) ++ padLine (last paddedContent)
      barLeft = [s " ", b green "tank", s " ", d dim "|", s " ", c grey "0:edit", s " ", c grey "1:test", s " ", Span " 2:logs " (SpanStyle (Just (RGB 26 27 38)) True False), s " ", c grey "3:shell", s " ", d dim "|", s " ", c grey "webapp-dev"]
      barRight = [d dim "|", s " ", c grey "idle"]
  in withStatusBar (spans allSpans) (statusBar barLeft barRight)

-- ============================================================
-- Utility
-- ============================================================

-- | Total character length of spans
spanLen :: [Span] -> Int
spanLen = sum . map (\(Span t _) -> T.length t)

-- | Pad spans to exactly w characters
padTo :: Int -> [Span] -> [Span]
padTo w ss =
  let len = spanLen ss
      gap = max 0 (w - len)
  in ss ++ [s (T.replicate gap " ")]

-- ============================================================
-- Scenario table
-- ============================================================

data Scenario = Scenario
  { scenarioName  :: String
  , scenarioTitle :: String
  , scenarioDesc  :: String
  , scenarioRender :: PNGConfig -> IO ()
  }

renderSingle :: Layout -> String -> PNGConfig -> String -> IO ()
renderSingle layout path config title_ = do
  let grid = renderLayout termW termH layout
      cfg = config { pngWindowTitle = title_ }
  png <- renderPNG cfg grid
  LBS.writeFile path png

renderDetach :: String -> PNGConfig -> IO ()
renderDetach path config = do
  let h1 = 12
      h2 = 10
      h3 = 12
      grid1 = renderLayout termW h1 (scenario09a h1)
      grid2 = renderLayout termW h2 (scenario09b h2)
      grid3 = renderLayout termW h3 (scenario09c h3)
      gapGrid = mkGrid termW 2
      combined = stackGrids [grid1, gapGrid, grid2, gapGrid, grid3]
      tallConfig = config
        { pngWindowTitle = "tank \x2014 detach/reattach"
        , pngTitleBar = True
        }
  tallPng <- renderPNG tallConfig combined
  LBS.writeFile path tallPng

-- | Stack multiple grids vertically into one grid
stackGrids :: [CellGrid] -> CellGrid
stackGrids [] = mkGrid 0 0
stackGrids gs = CellGrid $ foldl1 (\a b_ -> a <> b_) (map gridRows gs)

scenarios :: String -> [Scenario]
scenarios outdir =
  [ Scenario "01-idle" "tank \x2014 bash" "Single pane -- idle terminal"
      (\cfg -> renderSingle scenario01 (outdir </> "01-idle.png") cfg "tank \x2014 bash")
  , Scenario "02-overlay" "tank \x2014 bash" "Agent overlay open"
      (\cfg -> renderSingle scenario02 (outdir </> "02-overlay.png") cfg "tank \x2014 bash")
  , Scenario "03-tool-exec" "tank \x2014 bash" "Agent executes tools"
      (\cfg -> renderSingle scenario03 (outdir </> "03-tool-exec.png") cfg "tank \x2014 bash")
  , Scenario "04-multi-pane" "tank \x2014 editor + tests" "Multi-pane layout"
      (\cfg -> renderSingle scenario04 (outdir </> "04-multi-pane.png") cfg "tank \x2014 editor + tests")
  , Scenario "05-multi-agent" "tank \x2014 tests + shell" "Multi-pane with agents"
      (\cfg -> renderSingle scenario05 (outdir </> "05-multi-agent.png") cfg "tank \x2014 tests + shell")
  , Scenario "06-windows" "tank \x2014 docker logs" "Window switching + help"
      (\cfg -> renderSingle scenario06 (outdir </> "06-windows.png") cfg "tank \x2014 docker logs")
  , Scenario "07-services" "tank \x2014 bash" "Per-project services overlay"
      (\cfg -> renderSingle scenario07 (outdir </> "07-services.png") cfg "tank \x2014 bash")
  , Scenario "08-services-logs" "tank \x2014 logs" "Services daemon logs"
      (\cfg -> renderSingle scenario08 (outdir </> "08-services-logs.png") cfg "tank \x2014 logs")
  , Scenario "09-detach" "tank \x2014 webapp-dev" "Detach/reattach"
      (\cfg -> renderDetach (outdir </> "09-detach.png") cfg)
  ]

-- ============================================================
-- Main
-- ============================================================

main :: IO ()
main = do
  args <- getArgs
  case parseArgs args of
    Left err -> do
      putStrLn $ "Error: " ++ err
      putStrLn usage
    Right (cmd, fontPath, outdir) -> do
      createDirectoryIfMissing True outdir
      let config = defaultPNGConfig { pngFontPath = fontPath }
          allScenarios = scenarios outdir
      case cmd of
        "list" -> mapM_ (\sc -> putStrLn $ "  " ++ scenarioName sc ++ ": " ++ scenarioDesc sc) allScenarios
        "all" -> do
          putStrLn $ "Using font: " ++ fontPath
          putStrLn $ "Output dir: " ++ outdir
          mapM_ (\sc -> do
            putStrLn $ "  rendering " ++ scenarioName sc ++ "..."
            scenarioRender sc config
            putStrLn $ "  ok " ++ scenarioName sc
            ) allScenarios
          putStrLn "\nDone!"
        name -> case filter (\sc -> scenarioName sc == name) allScenarios of
          [sc] -> do
            putStrLn $ "Using font: " ++ fontPath
            scenarioRender sc config
            putStrLn $ "  ok " ++ scenarioName sc
          _ -> do
            -- Try matching by number
            let byNum = filter (\sc -> take 2 (scenarioName sc) == name) allScenarios
            case byNum of
              [sc] -> do
                putStrLn $ "Using font: " ++ fontPath
                scenarioRender sc config
                putStrLn $ "  ok " ++ scenarioName sc
              _ -> do
                putStrLn $ "Unknown scenario: " ++ name
                putStrLn "Available scenarios:"
                mapM_ (\sc -> putStrLn $ "  " ++ scenarioName sc) allScenarios

parseArgs :: [String] -> Either String (String, FilePath, FilePath)
parseArgs args = go args Nothing Nothing Nothing
  where
    go [] _ _ Nothing = Left "No command specified. Use 'list', 'all', or a scenario name."
    go [] (Just font) (Just outdir) (Just cmd) = Right (cmd, font, outdir)
    go [] (Just font) Nothing (Just cmd) = Right (cmd, font, ".")
    go [] Nothing _ (Just _) = Left "No font specified. Use --font PATH."
    go ("--font":path:rest) _ outdir cmd = go rest (Just path) outdir cmd
    go ("--outdir":path:rest) font _ cmd = go rest font (Just path) cmd
    go (x:rest) font outdir Nothing
      | x == "--font" = Left "--font requires a PATH argument"
      | x == "--outdir" = Left "--outdir requires a PATH argument"
      | otherwise = go rest font outdir (Just x)
    go (x:_) _ _ (Just _) = Left $ "Unexpected argument: " ++ x

usage :: String
usage = unlines
  [ "Usage: tank-render-concepts [--font PATH] [--outdir PATH] <command>"
  , ""
  , "Commands:"
  , "  list              List all scenarios"
  , "  all               Render all scenarios"
  , "  <name>            Render one scenario by name or number"
  , ""
  , "Options:"
  , "  --font PATH       Path to monospace TTF font"
  , "  --outdir PATH     Output directory (default: .)"
  ]
