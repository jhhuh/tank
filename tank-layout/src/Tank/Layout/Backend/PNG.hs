module Tank.Layout.Backend.PNG
  ( renderPNG
  , PNGConfig(..)
  , defaultPNGConfig
  ) where

import Codec.Picture (PixelRGBA8(..), Image, encodePng)
import Graphics.Rasterific
import Graphics.Rasterific.Texture (uniformTexture)
import Graphics.Text.TrueType (loadFontFile, Font, stringBoundingBox, _xMax, _yMax)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Vector as V
import Tank.Layout.Cell

-- | Configuration for PNG rendering.
data PNGConfig = PNGConfig
  { pngFontPath    :: !FilePath   -- ^ Path to a monospace TTF font
  , pngFontSize    :: !Int        -- ^ Font size in pixels (default 14)
  , pngTitleBar    :: !Bool       -- ^ Draw window chrome (title bar, traffic lights)
  , pngWindowTitle :: !String     -- ^ Window title text
  , pngPadding     :: !Int        -- ^ Outer padding around the window (default 20)
  } deriving (Show)

defaultPNGConfig :: PNGConfig
defaultPNGConfig = PNGConfig
  { pngFontPath    = ""
  , pngFontSize    = 14
  , pngTitleBar    = True
  , pngWindowTitle = "tank"
  , pngPadding     = 20
  }

-- | Render a CellGrid to a PNG image as lazy ByteString.
renderPNG :: PNGConfig -> CellGrid -> IO LBS.ByteString
renderPNG config grid = do
  fontResult <- loadFontFile (pngFontPath config)
  case fontResult of
    Left err -> error $ "Failed to load font: " ++ err
    Right font -> pure $ encodePng $ renderImage config font grid

-- Tokyo Night palette
bgColor, fgColor :: PixelRGBA8
bgColor     = PixelRGBA8 0x1a 0x1b 0x26 255   -- #1a1b26
fgColor     = PixelRGBA8 0xc0 0xca 0xf5 255   -- #c0caf5

titleBarColor, borderColor, bodyColor, titleTextColor :: PixelRGBA8
titleBarColor  = PixelRGBA8 0x24 0x28 0x3b 255  -- #24283b
borderColor    = PixelRGBA8 0x3b 0x42 0x61 255  -- #3b4261
bodyColor      = PixelRGBA8 0x13 0x14 0x1c 255  -- #13141c
titleTextColor = PixelRGBA8 0x56 0x5f 0x89 255  -- #565f89

titleBarHeight :: Int
titleBarHeight = 38

frameRadius :: Float
frameRadius = 10

-- Traffic light button colors
trafficRed, trafficYellow, trafficGreen :: PixelRGBA8
trafficRed    = PixelRGBA8 0xff 0x5f 0x56 255
trafficYellow = PixelRGBA8 0xff 0xbd 0x2e 255
trafficGreen  = PixelRGBA8 0x27 0xc9 0x3f 255

-- | Compute monospace cell dimensions from font metrics.
cellDimensions :: Font -> Int -> (Int, Int)
cellDimensions font fontSize =
  let dpi = 96
      ptSize = pixelSizeInPointAtDpi (fromIntegral fontSize) dpi
      bbox = stringBoundingBox font dpi ptSize "M"
      cellW = max 1 (ceiling (_xMax bbox))
      cellH = max 1 (ceiling (_yMax bbox))
  in (cellW, cellH)

-- | Convert pixel size to PointSize at a given DPI.
pixelSizeInPointAtDpi :: Float -> Int -> PointSize
pixelSizeInPointAtDpi px dpi = PointSize (px * 72.0 / fromIntegral dpi)

-- | Render the full image.
renderImage :: PNGConfig -> Font -> CellGrid -> Image PixelRGBA8
renderImage config font grid =
  let fontSize  = pngFontSize config
      (cellW, cellH) = cellDimensions font fontSize
      cols      = gridWidth grid
      rows      = gridHeight grid
      termW     = cols * cellW
      termH     = rows * cellH
      chrome    = if pngTitleBar config then titleBarHeight else 0
      pad       = pngPadding config
      imgW      = termW + 2 * pad
      imgH      = termH + chrome + 2 * pad
      dpi       = 96
      ptSize    = pixelSizeInPointAtDpi (fromIntegral fontSize) dpi
  in renderDrawing imgW imgH bodyColor $ do
       let winX = fromIntegral pad
           winY = fromIntegral pad
           winW = fromIntegral termW
           winH = fromIntegral (termH + chrome)

       -- Window border (rounded rectangle outline)
       drawBorderRect (winX - 1) (winY - 1) (winW + 2) (winH + 2) (frameRadius + 1) borderColor

       -- Window background
       drawFilledRoundedRect winX winY winW winH frameRadius bgColor

       -- Title bar
       when (pngTitleBar config) $ do
         let tbH = fromIntegral chrome
         -- Title bar background (top rounded, bottom square)
         drawFilledRoundedRect winX winY winW tbH frameRadius titleBarColor
         -- Square off the bottom of title bar
         drawFilledRect winX (winY + tbH - frameRadius) winW frameRadius titleBarColor

         -- Traffic lights
         let btnCY = winY + tbH / 2
         drawCircleFilled (winX + 18) btnCY 7 trafficRed
         drawCircleFilled (winX + 38) btnCY 7 trafficYellow
         drawCircleFilled (winX + 58) btnCY 7 trafficGreen

         -- Title text (centered)
         withTexture (uniformTexture titleTextColor) $
           printTextAt font (toPointSize (fromIntegral fontSize - 2) dpi) (V2 (winX + winW / 2 - estimateTextWidth font (fromIntegral fontSize - 2) (pngWindowTitle config) / 2) (winY + 11)) (pngWindowTitle config)

       -- Terminal content
       let contentY = winY + fromIntegral chrome
       drawCells config font grid winX contentY cellW cellH ptSize

-- | Draw all cells from the grid.
drawCells :: PNGConfig -> Font -> CellGrid -> Float -> Float -> Int -> Int -> PointSize -> Drawing PixelRGBA8 ()
drawCells _config font grid originX originY cellW cellH ptSize = do
  let rows = gridRows grid
      cw = fromIntegral cellW
      ch = fromIntegral cellH
  V.iforM_ rows $ \rowIdx row ->
    V.iforM_ row $ \colIdx cell -> do
      let x = originX + fromIntegral colIdx * cw
          y = originY + fromIntegral rowIdx * ch

      -- Background
      let bg = cellBgPixel (cellBg cell)
      drawFilledRect x y cw ch bg

      -- Foreground character
      when (cellChar cell /= ' ') $ do
        let fg = cellFgPixel (cellFg cell)
        withTexture (uniformTexture fg) $
          printTextAt font ptSize (V2 x y) [cellChar cell]

-- | Convert a Cell Color to PixelRGBA8 for foreground.
cellFgPixel :: Color -> PixelRGBA8
cellFgPixel Default       = fgColor
cellFgPixel (RGB r g b)   = PixelRGBA8 r g b 255

-- | Convert a Cell Color to PixelRGBA8 for background.
cellBgPixel :: Color -> PixelRGBA8
cellBgPixel Default       = bgColor
cellBgPixel (RGB r g b)   = PixelRGBA8 r g b 255

-- Drawing helpers

drawFilledRect :: Float -> Float -> Float -> Float -> PixelRGBA8 -> Drawing PixelRGBA8 ()
drawFilledRect x y w h color =
  withTexture (uniformTexture color) $
    fill $ rectangle (V2 x y) w h

drawFilledRoundedRect :: Float -> Float -> Float -> Float -> Float -> PixelRGBA8 -> Drawing PixelRGBA8 ()
drawFilledRoundedRect x y w h r color =
  withTexture (uniformTexture color) $
    fill $ roundedRectangle (V2 x y) w h r r

drawBorderRect :: Float -> Float -> Float -> Float -> Float -> PixelRGBA8 -> Drawing PixelRGBA8 ()
drawBorderRect x y w h r color =
  withTexture (uniformTexture color) $
    stroke 1 JoinRound (CapRound, CapRound) $
      roundedRectangle (V2 x y) w h r r

drawCircleFilled :: Float -> Float -> Float -> PixelRGBA8 -> Drawing PixelRGBA8 ()
drawCircleFilled cx cy r color =
  withTexture (uniformTexture color) $
    fill $ circle (V2 cx cy) r

-- | Convert pixel size to PointSize for Rasterific.
toPointSize :: Float -> Int -> PointSize
toPointSize px dpi = PointSize (px * 72.0 / fromIntegral dpi)

-- | Rough estimate of text width for centering.
estimateTextWidth :: Font -> Float -> String -> Float
estimateTextWidth font fontSize str =
  let dpi = 96
      ptSize = pixelSizeInPointAtDpi fontSize dpi
      bbox = stringBoundingBox font dpi ptSize str
  in _xMax bbox

-- | Conditional drawing.
when :: Bool -> Drawing px () -> Drawing px ()
when True  act = act
when False _   = pure ()
