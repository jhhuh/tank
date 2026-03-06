module Tank.Layout.Backend.PNG
  ( renderPNG
  , renderMultiPNG
  , PNGConfig(..)
  , defaultPNGConfig
  ) where

import Graphics.Rendering.Cairo
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Vector as V
import Data.Word (Word8)
import System.IO (openTempFile, hClose)
import System.Directory (removeFile)
import Tank.Layout.Cell

-- | Configuration for PNG rendering.
data PNGConfig = PNGConfig
  { pngFontFamily  :: !String   -- ^ Font family name (e.g., "DejaVu Sans Mono")
  , pngFontSize    :: !Int      -- ^ Font size in pixels (default 14)
  , pngTitleBar    :: !Bool     -- ^ Draw window chrome (title bar, traffic lights)
  , pngWindowTitle :: !String   -- ^ Window title text
  , pngPadding     :: !Int      -- ^ Outer padding around the window (default 20)
  } deriving (Show)

defaultPNGConfig :: PNGConfig
defaultPNGConfig = PNGConfig
  { pngFontFamily  = "DejaVu Sans Mono"
  , pngFontSize    = 14
  , pngTitleBar    = True
  , pngWindowTitle = "tank"
  , pngPadding     = 20
  }

-- Tokyo Night palette
type RGB = (Double, Double, Double)

bgRGB, fgRGB :: RGB
bgRGB      = hexRGB 0x1a 0x1b 0x26
fgRGB      = hexRGB 0xc0 0xca 0xf5

titleBarRGB, borderRGB, bodyRGB, titleTextRGB :: RGB
titleBarRGB  = hexRGB 0x24 0x28 0x3b
borderRGB    = hexRGB 0x3b 0x42 0x61
bodyRGB      = hexRGB 0x13 0x14 0x1c
titleTextRGB = hexRGB 0x56 0x5f 0x89

trafficRedRGB, trafficYellowRGB, trafficGreenRGB :: RGB
trafficRedRGB    = hexRGB 0xff 0x5f 0x56
trafficYellowRGB = hexRGB 0xff 0xbd 0x2e
trafficGreenRGB  = hexRGB 0x27 0xc9 0x3f

hexRGB :: Word8 -> Word8 -> Word8 -> RGB
hexRGB r g b = (fromIntegral r / 255, fromIntegral g / 255, fromIntegral b / 255)

titleBarHeight :: Int
titleBarHeight = 38

frameRadius :: Double
frameRadius = 10

-- Inner padding between window frame and terminal content (pixels)
innerPadX, innerPadTop, innerPadBottom :: Int
innerPadX      = 10
innerPadTop    = 6
innerPadBottom = 6

setRGB :: RGB -> Render ()
setRGB (r, g, b) = setSourceRGB r g b

colorToRGB :: Color -> RGB -> RGB
colorToRGB Default     def = def
colorToRGB (RGB r g b) _   = hexRGB r g b

-- | Render a single CellGrid to a PNG image.
renderPNG :: PNGConfig -> CellGrid -> IO LBS.ByteString
renderPNG config grid = renderMultiPNG config [(pngWindowTitle config, grid)]

-- | Render multiple grids as stacked window frames in a single PNG.
-- Each frame gets its own window chrome (title bar, traffic lights, border).
renderMultiPNG :: PNGConfig -> [(String, CellGrid)] -> IO LBS.ByteString
renderMultiPNG config frames = do
  let fontSize = fromIntegral (pngFontSize config) :: Double

  -- Get font metrics using a temporary surface
  (cellW, cellH, asc) <- withImageSurface FormatARGB32 1 1 $ \tmpSurf ->
    renderWith tmpSurf $ do
      selectFontFace (pngFontFamily config) FontSlantNormal FontWeightNormal
      setFontSize fontSize
      fe <- fontExtents
      te <- textExtents "M"
      let cw  = max 1 (ceiling (textExtentsXadvance te) :: Int)
          a   = fontExtentsAscent fe
          d   = fontExtentsDescent fe
          ch  = max 1 (ceiling (a + d) :: Int)
      pure (cw, ch, a)

  let chrome = if pngTitleBar config then titleBarHeight else 0
      pad = pngPadding config
      gapBetween = 16 :: Int  -- pixels between frames

      -- Per-frame window dimensions
      winDims = map (\(_, g) ->
        let tw = gridWidth g * cellW
            th = gridHeight g * cellH
        in ( tw + 2 * innerPadX
           , th + chrome + innerPadTop + innerPadBottom
           )) frames

      maxWinW = case winDims of
        [] -> 100
        _  -> maximum (map fst winDims)
      totalFrameH = sum (map snd winDims)
      totalGapH = gapBetween * max 0 (length frames - 1)

      imgW = maxWinW + 2 * pad
      imgH = totalFrameH + totalGapH + 2 * pad

  withImageSurface FormatARGB32 imgW imgH $ \surface -> do
    renderWith surface $ do
      -- Body background
      setRGB bodyRGB
      paint

      -- Draw each frame
      let go _ [] = pure ()
          go yOff ((title_, grid):rest) = do
            let wx = fromIntegral pad
                wy = fromIntegral yOff
            drawFrame config fontSize cellW cellH asc wx wy grid title_
            let winH = gridHeight grid * cellH + chrome + innerPadTop + innerPadBottom
            go (yOff + winH + gapBetween) rest
      go pad frames

    -- Write PNG to temp file and read back
    (tmpPath, h) <- openTempFile "/tmp" "tank-png-.png"
    hClose h
    surfaceWriteToPNG surface tmpPath
    bs <- LBS.readFile tmpPath
    removeFile tmpPath
    pure bs

-- | Draw a single window frame (border, chrome, grid content) at the given position.
drawFrame :: PNGConfig -> Double -> Int -> Int -> Double -> Double -> Double -> CellGrid -> String -> Render ()
drawFrame config fontSize cellW_ cellH_ asc wx wy grid title_ = do
  let cols = gridWidth grid
      rows_ = gridHeight grid
      tw = cols * cellW_
      th = rows_ * cellH_
      chrome = if pngTitleBar config then titleBarHeight else 0
      ww = fromIntegral (tw + 2 * innerPadX) :: Double
      wh = fromIntegral (th + chrome + innerPadTop + innerPadBottom) :: Double

  -- Window border
  setRGB borderRGB
  setLineWidth 1
  roundedRect (wx - 1) (wy - 1) (ww + 2) (wh + 2) (frameRadius + 1)
  stroke

  -- Window background
  setRGB bgRGB
  roundedRect wx wy ww wh frameRadius
  fill

  -- Title bar
  when (pngTitleBar config) $ do
    let tbH = fromIntegral chrome

    -- Title bar background (top rounded, bottom square)
    setRGB titleBarRGB
    roundedRect wx wy ww tbH frameRadius
    fill
    -- Square off the bottom of title bar
    rectangle wx (wy + tbH - frameRadius) ww frameRadius
    fill

    -- Traffic lights
    let btnCY = wy + tbH / 2
    filledCircle (wx + 18) btnCY 7 trafficRedRGB
    filledCircle (wx + 38) btnCY 7 trafficYellowRGB
    filledCircle (wx + 58) btnCY 7 trafficGreenRGB

    -- Title text (centered)
    selectFontFace (pngFontFamily config) FontSlantNormal FontWeightNormal
    setFontSize (fontSize - 2)
    fe <- fontExtents
    te <- textExtents title_
    let ttlW = textExtentsXadvance te
        ttlAsc = fontExtentsAscent fe
        ttlDesc = fontExtentsDescent fe
    setRGB titleTextRGB
    moveTo (wx + ww / 2 - ttlW / 2) (wy + tbH / 2 + (ttlAsc - ttlDesc) / 2)
    showText title_

  -- Terminal content
  let cx = wx + fromIntegral innerPadX
      cy = wy + fromIntegral chrome + fromIntegral innerPadTop
      cw = fromIntegral cellW_
      ch = fromIntegral cellH_

  selectFontFace (pngFontFamily config) FontSlantNormal FontWeightNormal
  setFontSize fontSize

  V.iforM_ (gridRows grid) $ \rowIdx row ->
    V.iforM_ row $ \colIdx cell -> do
      let x = cx + fromIntegral colIdx * cw
          y = cy + fromIntegral rowIdx * ch

      -- Background
      let (br, bg', bb) = colorToRGB (cellBg cell) bgRGB
      setSourceRGB br bg' bb
      rectangle x y cw ch
      fill

      -- Foreground character
      when (cellChar cell /= ' ') $ do
        let (fr, fg', fb) = colorToRGB (cellFg cell) fgRGB
        setSourceRGB fr fg' fb
        moveTo x (y + asc)
        showText [cellChar cell]

-- | Conditional rendering.
when :: Bool -> Render () -> Render ()
when True  act = act
when False _   = pure ()

-- Drawing helpers

roundedRect :: Double -> Double -> Double -> Double -> Double -> Render ()
roundedRect x y w h r = do
  newPath
  arc (x + w - r) (y + r)     r (-pi/2) 0
  arc (x + w - r) (y + h - r) r 0        (pi/2)
  arc (x + r)     (y + h - r) r (pi/2)   pi
  arc (x + r)     (y + r)     r pi        (3*pi/2)
  closePath

filledCircle :: Double -> Double -> Double -> RGB -> Render ()
filledCircle cx cy r color = do
  setRGB color
  newPath
  arc cx cy r 0 (2 * pi)
  fill
