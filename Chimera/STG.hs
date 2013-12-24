{-# LANGUAGE TypeSynonymInstances, FlexibleInstances, FlexibleContexts, Rank2Types #-}
module Chimera.STG (
  update, draw, loadStage

  , module M
  ) where

import Graphics.UI.FreeGame
import Control.Lens
import Control.Arrow ((***))
import Control.Monad.State.Strict
import qualified Data.Sequence as S
import qualified Data.Foldable as F
import Control.Monad.Trans.Class (lift)

import Chimera.STG.World as M
import Chimera.STG.Util
import Chimera.STG.Load as M
import Chimera.STG.UI as M

import Chimera.Scripts
import Chimera.Scripts.Stage1

import Debug.Trace as T

stage2 :: Stage ()
stage2 = do
  res <- getResource
  keeper $ initEnemy (V2 260 40) 2 res & runAuto .~ debug

loadStage :: Field -> Field
loadStage f = f
  & stage .~ stage1
  & resource .~ load1

class GUIClass c where
  update :: State c ()
  draw :: Resource -> StateT c Game ()

instance GUIClass Player where
  update = do
    s <- use speed
    k <- use keys
    counter %= (+1)
    pos %= clamp . (+ (bool id (0.5*^) (k^.shift>0) $ s *^ dir k))

    where
      dir :: Keys -> Vec
      dir key = let addTup b p q = bool q (fromPair p+q) b in
        addTup (key ^. up    > 0) (0,-1) $
        addTup (key ^. down  > 0) (0,1) $
        addTup (key ^. right > 0) (1,0) $
        addTup (key ^. left  > 0) (-1,0) $
        fromPair (0,0)

  draw res = do
    p <- get
    translate (p ^. pos) $ fromBitmap (picture res p)

clamp :: Vec -> Vec
clamp = fromPair . (edgeX *** edgeY) . toPair
  where
    edgeX = (\p -> bool p areaLeft (p < areaLeft)) .
            (\p -> bool p areaRight (p > areaRight))
    
    edgeY = (\p -> bool p areaLeft (p < areaLeft)) .
            (\p -> bool p areaBottom (p > areaBottom))

instance GUIClass Enemy where
  update = do
    sp <- use spXY
    pos %= (+sp)
    counter %= (+1)
    h <- use hp
    when (h <= 0) $ stateChara .= Dead
    effectEnemy %= 
      S.filter (\e -> e^.stateEffect /= Inactive) . fmap (\e -> update `execState` e)
  
  draw res = do
    e <- get
    mapM_' (\e -> lift $ draw res `execStateT` e) (e^.effectEnemy)
    translate (e^.pos) $ fromBitmap (picture res e)

instance GUIClass Bullet where
  update = do
    r <- use speed
    t <- use angle
    pos %= (+ fromPolar (r,t))
    p <- use pos
    when (isInside p == False) $ stateBullet .= Outside

  draw res = do
    b <- get
    translate (b^.pos) $ rotateR (b^.angle + pi/2) $ fromBitmap (picture res b)

instance GUIClass Effect where
  update = do
    run <- use runAuto
    effectObject %= execState run
  
  draw res = do
    b <- get
    translate (b^.pos) $ rotateR (b^.angle) $ scale (b^.size) $ 
      fromBitmap (b^.img $ res)

instance GUIClass Field where
  update = do
    res <- use resource
  
    -- collision
    collideObj
    
    -- effect
    es <- use enemy
    effects ><= (fmap (\e -> effEnemyDead res (e^.pos)) $ S.filter (\e -> e^.stateChara == Dead) es)
    
    -- append
    f <- get
    let (s', LookAt me _) = runStage (f^.stage) `runState` (LookAt Nothing f)
    stage .= s'
    counterF %= (+1)
    enemy %= maybe id (S.<|) me
    addBullet
    
    -- run
    runAutonomie enemy
    runAutonomie bullets
    
    -- update
    bullets %= S.filter (\b -> b^.stateBullet /= Outside) . fmap (execState update)
    enemy %= fmap (execState update) . S.filter (\e -> e^.stateChara /= Dead)
    player %= execState update
    effects %= S.filter (\e -> e^.stateEffect /= Inactive) . fmap (execState update)
      
  draw _ = do
    f <- get
    res <- use resource
    mapM_' (\p -> lift $ draw res `execStateT` p) (f^.bullets)
    lift $ draw res `execStateT` (f^.player)
    mapM_' (\e -> lift $ draw res `execStateT` e) (f^.enemy)
    mapM_' (\e -> lift $ draw res `execStateT` e) (f^.effects)

    when (f^.isDebug) $ do
      mapM_' (\b -> colored blue . polygon $ boxVertexRotated (b^.pos) (b^.size) (b^.angle)) (f ^. bullets)
      (\p -> colored yellow . polygon $ boxVertex (p^.pos) (p^.size)) $ f^.player
      mapM_' (\e -> colored green . polygon $ boxVertex (e^.pos) (e^.size)) (f ^. enemy)
    
    translate (V2 320 240) $ fromBitmap (f^.resource^.board)

runAutonomie :: (Autonomic a (Danmaku b) b) => Lens' Field (S.Seq a) -> State Field ()
runAutonomie member = do
  f <- get
  let (s', fs) = scanSeq (f^.member) f
  member .= s'
  f <- get
  put $ F.foldl (\f u -> u `execState` f) f fs
  
  where
    scanSeq :: (Autonomic a (Danmaku b) b) => 
                S.Seq a -> Field -> (S.Seq a, S.Seq (State Field ()))
    scanSeq es f = let pairs = fmap go es in 
      (fmap fst pairs, (F.foldl (S.><) S.empty $ fmap snd pairs))
      where
        go :: (Autonomic a (Danmaku b) b) => a -> (a, S.Seq (State Field ()))
        go e = 
          let LookAt eo' (_, fs) = 
                (runDanmaku $ e^.runAuto) `execState` LookAt (e^.auto) (f, S.empty) in
          (e & auto .~ eo', fs)

addBullet :: State Field ()
addBullet = do
  p <- use player
  when (p^.keys^.zKey > 0 && p^.counter `mod` 10 == 0) $ do
    res <- use resource
    bullets ><= (S.fromList
      [def' res & pos .~ (p^.pos) + V2 5 0,
       def' res & pos .~ (p^.pos) + V2 15 0,
       def' res & pos .~ (p^.pos) - V2 5 0,
       def' res & pos .~ (p^.pos) - V2 15 0])
  
  when (p^.keys^.xKey > 0 && p^.counter `mod` 20 == 0) $ do
    res <- use resource
    bullets ><= (S.singleton $ chaosBomb res (p^.pos))
  
  where
    def' :: Resource -> Bullet
    def' res = 
      speed .~ 15 $
      angle .~ pi/2 $ 
      kind .~ Diamond $
      color .~ Red $
      stateBullet .~ PlayerB $
      def

collideObj :: State Field ()
collideObj = do
  p <- use player
  es <- use enemy
  bs <- use bullets
  
  res <- use resource
  let run' = run (createEffect res)
  
  let (n, bs') = runPair PlayerB p bs
  player %= (hp -~ n)
  when (n>0) $ effects %= (effPlayerDead res (p^.pos) S.<|)
  
  let (es', bs'', effs) = run' EnemyB es bs'
  enemy .= es'
  bullets .= bs''
  -- effects %= (effEnemyDamaged ...)

  where
    runPair :: (HasChara c, HasObject c) => 
               StateBullet -> c -> S.Seq Bullet -> (Int, S.Seq Bullet)
    runPair s c bs = 
      let bs' = S.filter (\b -> s /= b^.stateBullet && collide c b) bs in
      (S.length bs', S.filter (\b -> (Nothing ==) $ b `S.elemIndexL` bs') bs)
    
    run :: (HasChara c, HasObject c) => 
           (StateBullet -> c -> Effect) -> StateBullet -> S.Seq c -> S.Seq Bullet -> 
           (S.Seq c, S.Seq Bullet, S.Seq Effect)
    run eff s es bs = go s (S.viewl es) bs where
      go _ S.EmptyL bs = (S.empty, bs, S.empty)
      go s (e S.:< es) bs = 
        let (n, bs') = runPair s e bs; (es', bs'', ps) = run eff s es bs' in
        ((e & hp -~ n) S.<| es, bs'', bool id ((eff s e) S.<|) (n>0) $ ps)
    
    createEffect :: (HasChara c, HasObject c) => 
                    Resource -> StateBullet -> c -> Effect
    createEffect res PlayerB e = effPlayerDead res (e^.pos)
    createEffect res EnemyB e = effPlayerDead res (e^.pos)

collide :: (HasChara c, HasObject c) => c -> Bullet -> Bool
collide c b = case b^.speed > b^.size^._x of
  True -> detect (b & size +~ fromPolar (b^.speed, b^.angle)) c
  False -> detect b c
  where
    detect :: (HasObject c, HasObject c') => c -> c' -> Bool
    detect a b = 
      let V2 w' h' = a^.size
          r = rot2D (a^.angle) in
      or $ [(a^.pos + r !* (V2   w'    h' )) `isIn` b,
            (a^.pos + r !* (V2 (-w')   h' )) `isIn` b,
            (a^.pos + r !* (V2   w'  (-h'))) `isIn` b,
            (a^.pos + r !* (V2 (-w') (-h'))) `isIn` b]
    
    isIn :: (HasObject c) => Vec -> c -> Bool
    isIn p box = isInCentoredBox (p-box^.pos) where
      isInCentoredBox :: Vec -> Bool
      isInCentoredBox p' = 
        let V2 px' py' = rot2D (-box^.angle) !* p' in
        abs px' < (box^.size^._x)/2 && abs py' < (box^.size^._y)/2


