{-# LANGUAGE TemplateHaskell, TypeSynonymInstances, FlexibleInstances #-}
module Chimera.Load (
  loadResource
  , charaImg, bulletImg, effectImg, board
  , BKind(..), BColor(..)
  ) where

import FreeGame
import Control.Lens
import qualified Data.Vector as V
import qualified Data.Map as M

import Chimera.Core.Util
import Chimera.Core.Types

loadResource :: Game Resource
loadResource = do
  r1 <- readBitmap "data/img/player_lufe.png"
  r2 <- readBitmap "data/img/dot_yousei.png"
  r3 <- readBitmap "data/img/shot.png"
  b <- readBitmap "data/img/board.png"
  e1 <- readBitmap "data/img/lightring.png"
  e2 <- readBitmap "data/img/lightbomb.png"
  e3 <- readBitmap "data/img/eff1.png"
  e4 <- readBitmap "data/img/eff2.png"
  p1_0 <- readBitmap "data/img/pat1_0.png"
  p1_1 <- readBitmap "data/img/pat1_1.png"
  p1_2 <- readBitmap "data/img/pat1_2.png"
  la <- readBitmap "data/img/layer_200_w.png"
  f <- loadFont "data/font/VL-PGothic-Regular.ttf"
  c1 <- readBitmap "data/img/lufe_400.png"

  let ns = fmap (text f 20 . return) "0123456789"
  let ls = fmap (\x -> (x, text f 20 x))
        $ ["fps", "bullets", "effects", "enemies", "score", "hiscore", "hp"]
  
  return $ Resource {
    _charaImg = V.fromList [cropBitmap r1 (50,50) (0,0),
                            cropBitmap r2 (32,32) (0,0)],
    _bulletImg = splitBulletBitmaps r3,
    _effectImg = V.fromList $ [
      V.fromList $ cutIntoN 10 e1,
      V.fromList $ cutIntoN 10 e2,
      V.fromList $ cutIntoN 12 e3,
      V.fromList [p1_0, p1_1, p1_2],
      V.fromList $ cutIntoN 14 e4],
    _board = b,
    _font = f,
    _layerBoard = la,
    _portraits = V.fromList [c1],
    _numbers = V.fromList ns,
    _labels = M.fromList ls
  }

splitBulletBitmaps :: Bitmap -> V.Vector (V.Vector Bitmap)
splitBulletBitmaps pic = 
  V.fromList [
    V.fromList [
      clipBulletBitmap k c pic
    | c <- [Red .. Magenta]] 
  | k <- [BallLarge .. Needle]]

clipBulletBitmap :: BKind -> BColor -> Bitmap -> Bitmap
clipBulletBitmap bk bc
  | bk == BallLarge  = clip (60 * colorOffset bc) 0 60 60
  | bk == BallMedium = clip (30 * colorOffset bc) 60 30 30
  | bk == BallSmall  = clip (20 * colorOffset bc) 90 20 20
  | bk == Oval       = clip (160 + 10 * colorOffset bc) 90 10 20
  | bk == Diamond    = clip (240 + 10 * colorOffset bc) 90 10 20
  | bk == BallFrame  = clip (20 * colorOffset bc) 110 20 20
  | bk == Needle     = clip (5 * colorOffset bc) 130 5 100
  | bk == BallTiny   = clip (40 + 10 * colorOffset bc) 130 10 10
  | otherwise = error "otherwise case in clipBulletBitmap"
  where
    colorOffset :: BColor -> Int
    colorOffset = fromEnum

    clip :: Int -> Int -> Int -> Int -> Bitmap -> Bitmap
    clip a b c d bmp = cropBitmap bmp (c,d) (a,b)

