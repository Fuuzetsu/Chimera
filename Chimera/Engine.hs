module Chimera.Engine ( module M ) where

import Graphics.UI.FreeGame
import Control.Lens
import Control.Monad.State.Strict (get, lift, execStateT, execState, State)
import qualified Data.Sequence as S

import Chimera.Core.Load as M
import Chimera.Core.World as M
import Chimera.Scripts as M

instance GUIClass Field where
  update = do
    res <- use resource
    counterF %= (+1)
  
    -- collision
    collideObj
    
    -- effect
    es <- use enemy
    effects ><= (fmap (\e -> effEnemyDead res (e^.pos)) $ S.filter (\e -> e^.stateChara == Dead) es)
    
    -- append
    f <- get
    when_ ((Shooting ==) `fmap` use stateField) $ do
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
    
    let drawEffs z = mapM_' (\e -> lift $ draw res `execStateT` e) $ S.filter (\r -> (r^.zIndex) == z) (f^.effects)
    
    drawEffs Background
    mapM_' (\p -> lift $ draw res `execStateT` p) (f^.bullets)
    lift $ draw res `execStateT` (f^.player)
    mapM_' (\e -> lift $ draw res `execStateT` e) (f^.enemy)
    drawEffs OnObject

    when (f^.isDebug) $ do
      mapM_' (\b -> colored blue . polygon $ boxVertexRotated (b^.pos) (b^.size) (b^.angle)) (f ^. bullets)
      (\p -> colored yellow . polygon $ boxVertex (p^.pos) (p^.size)) $ f^.player
      mapM_' (\e -> colored green . polygon $ boxVertex (e^.pos) (e^.size)) (f ^. enemy)
    
    translate (V2 320 240) $ fromBitmap (f^.resource^.board)
    drawEffs Foreground
    
collideObj :: State Field ()
collideObj = do
  p <- use player
  es <- use enemy
  bs <- use bullets
  
  res <- use resource
  let run' = run (createEffect res)
  
  let (n, bs') = runPair PlayerB p bs
  player %= (hp -~ n)
  when (n>0) $ effects %= (S.|> effPlayerDead res (p^.pos))
  
  let (es', bs'', _) = run' EnemyB es bs'
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
        (es' S.|> (e & hp -~ n), bs'', bool id (S.|> (eff s e)) (n>0) $ ps)
    
    createEffect :: (HasChara c, HasObject c) => 
                    Resource -> StateBullet -> c -> Effect
    createEffect res PlayerB e = effPlayerDead res (e^.pos)
    createEffect res EnemyB e = effPlayerDead res (e^.pos)
    createEffect _ _ _ = undefined
      
addBullet :: State Field ()
addBullet = do
  p <- use player
  when (p^.keys^.zKey > 0 && p^.counter `mod` 10 == 0) $ do
    bullets ><= (S.fromList
      [def' & pos .~ (p^.pos) + V2 5 0,
       def' & pos .~ (p^.pos) + V2 15 0,
       def' & pos .~ (p^.pos) - V2 5 0,
       def' & pos .~ (p^.pos) - V2 15 0])
  
  when (p^.keys^.xKey > 0 && p^.counter `mod` 20 == 0) $ do
    res <- use resource
    bullets ><= (S.singleton $ chaosBomb res (p^.pos))
  
  where
    def' :: Bullet
    def' = 
      makeBullet $
      speed .~ 15 $
      angle .~ pi/2 $ 
      kind .~ Diamond $
      color .~ Red $
      stateBullet .~ PlayerB $
      def