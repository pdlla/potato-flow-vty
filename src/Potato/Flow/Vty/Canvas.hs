{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE RecursiveDo     #-}

module Potato.Flow.Vty.Canvas (
  CanvasWidgetConfig(..)
  , CanvasWidget(..)
  , holdCanvasWidget
) where


import           Relude

import           Potato.Flow
import           Potato.Flow.Controller
import           Potato.Flow.Controller.Handler
import           Potato.Flow.Math
import           Potato.Flow.Vty.Input
import           Potato.Flow.Vty.PFWidgetCtx
import           Potato.Reflex.Vty.Helpers
import           Potato.Reflex.Vty.Widget
import           Reflex.Potato.Helpers

import           Control.Lens
import qualified Data.IntMap.Strict             as IM
import           Data.These

import qualified Graphics.Vty                   as V
import           Reflex
import           Reflex.Vty

-- TODO this needs to come from Potato.Flow
defaultCanvasLBox :: LBox
defaultCanvasLBox = LBox (V2 0 0) (V2 100 50)

dynLBox_to_dynRegion :: (Reflex t) => Dynamic t LBox -> DynRegion t
dynLBox_to_dynRegion dlb = r where
  x' = flip fmap dlb $ \(LBox (V2 x _) _) -> x
  y' = flip fmap dlb $ \(LBox (V2 _ y) _) -> y
  w' = flip fmap dlb $ \(LBox _ (V2 w _)) -> w
  h' = flip fmap dlb $ \(LBox _ (V2 _ h)) -> h
  r = DynRegion x' y' w' h'

translate_dynRegion :: (Reflex t) => Dynamic t XY -> DynRegion t -> DynRegion t
translate_dynRegion pos dr = dr {
    _dynRegion_left = liftA2 (+) (_dynRegion_left dr) (fmap getx pos)
    , _dynRegion_top = liftA2 (+) (_dynRegion_top dr) (fmap gety pos)
  } where
    getx (V2 x _) = x
    gety (V2 _ y) = y

pan_lBox :: XY -> LBox -> LBox
pan_lBox pan (LBox p s) = LBox (p+pan) s

data CanvasWidgetConfig t = CanvasWidgetConfig {
  _canvasWidgetConfig_pfctx        :: PFWidgetCtx t
  , _canvasWidgetConfig_pan        :: Dynamic t XY
  , _canvasWidgetConfig_broadPhase :: Dynamic t BroadPhaseState
  , _canvasWidgetConfig_canvas     :: Dynamic t SCanvas
  , _canvasWidgetConfig_handles    :: Dynamic t HandlerRenderOutput
}

data CanvasWidget t = CanvasWidget {
  _canvasWidget_mouse :: Event t LMouseData
}

holdCanvasWidget :: forall t m. (MonadWidget t m)
  => CanvasWidgetConfig t
  -> VtyWidget t m (CanvasWidget t)
holdCanvasWidget CanvasWidgetConfig {..} = mdo
  let
    PFWidgetCtx {..} = _canvasWidgetConfig_pfctx
    renderfn (BroadPhaseState boxes bpt cslmap) rc = case boxes of
      [] -> return rc
      (b:bs) -> case intersect_lBox (renderedCanvas_box rc) (foldl' union_lBox b bs) of
        Nothing -> return rc
        Just aabb -> do
          -- TODO don't use _pFWidgetCtx_pFState since it updates even if directory didn't change
          slmap <- sample . current . fmap _pFState_directory $ _pFWidgetCtx_pFState
          let
            rids = broadPhase_cull aabb bpt
            seltls = flip fmap rids $ \rid -> case IM.lookup rid cslmap of
              Nothing -> case IM.lookup rid slmap of
                Nothing -> error "this should never happen, because broadPhase_cull should only give existing seltls"
                Just seltl -> seltl
              Just mseltl -> case mseltl of
                Nothing -> error "this should never happen, because deleted seltl would have been culled in broadPhase_cull"
                Just seltl -> seltl
            -- TODO need to order seltls by layer position oops
            newrc = render aabb (map _sEltLabel_sElt seltls) rc
          return $ newrc
    --foldCanvasFn :: (These ([LBox], BPTree, REltIdMap (Maybe SEltLabel)) LBox) -> RenderedCanvas -> PushM t RenderedCanvas
    foldCanvasFn (This x) rc = renderfn x rc
    foldCanvasFn (That lbx) _ = do
      BroadPhaseState _ bpt _ <- sample . current $ _canvasWidgetConfig_broadPhase
      -- TODO only redo what's needed
      let renderBoxes = [lbx]
      renderfn (BroadPhaseState renderBoxes bpt IM.empty) (emptyRenderedCanvas lbx)
    foldCanvasFn (These _ _) _ = error "resize and change events should never occur simultaneously"


  -- initialization stuff, wow super annoying ;__;
  let
    -- TODO call renderWithBroadPhase instead
    initialDir = _pFState_directory _pFWidgetCtx_initialPFState
    initialselts = fmap (\(SEltLabel _ selt) -> selt) $ toList initialDir
    initialCanvasBox = _sCanvas_box $ _pFState_canvas _pFWidgetCtx_initialPFState
    -- TODO render entire screen area rather than just canvas portion
    initialRenderedCanvas =  render initialCanvasBox initialselts (emptyRenderedCanvas initialCanvasBox)

  -- ::prepare rendered canvas ::
  renderedCanvas <- foldDynM foldCanvasFn initialRenderedCanvas
    -- TODO don't use _pFWidgetCtx_pFState since it updates even if canvas didn't actually change
    $ alignEventWithMaybe Just (updated _canvasWidgetConfig_broadPhase) (fmap _sCanvas_box . updated $ _canvasWidgetConfig_canvas)

  -- ::draw the canvas::
  let
    canvasRegion' = ffor2 _canvasWidgetConfig_pan renderedCanvas $ \pan rc -> pan_lBox pan (renderedCanvas_box rc)
    canvasRegion = dynLBox_to_dynRegion canvasRegion'
    --canvasRegion = translate_dynRegion _canvasWidgetConfig_pan $ dynLBox_to_dynRegion (fmap renderedCanvas_box renderedCanvas)
  fill '░'
  pane canvasRegion (constDyn True) $ do
    text $ current (fmap renderedCanvasToText renderedCanvas)
  tellImages $ ffor3 (current _canvasWidgetConfig_handles) (current _pFWidgetCtx_attr_manipulator) (current canvasRegion')
    $ \(HandlerRenderOutput hs) attr (LBox (V2 px py) _)-> fmap (\(LBox (V2 x y) (V2 w h)) -> V.translate (x+px) (y+py) $ V.charFill attr 'X' w h) hs

  inp <- makeLMouseDataInputEv 0 False
  return $ CanvasWidget inp