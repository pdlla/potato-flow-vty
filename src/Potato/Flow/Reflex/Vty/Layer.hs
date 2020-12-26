
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE RecursiveDo     #-}

module Potato.Flow.Reflex.Vty.Layer (
  LayerWidgetConfig(..)
  , LayerWidget(..)
  , holdLayerWidget
) where

import           Relude

import           Potato.Flow
import           Potato.Flow.Controller
import           Potato.Flow.Reflex.Vty.Attrs
import           Potato.Flow.Reflex.Vty.PFWidgetCtx
import           Potato.Reflex.Vty.Helpers
import           Potato.Reflex.Vty.Widget


import           Control.Monad.Fix
import           Data.Align
import           Data.Dependent.Sum                 (DSum ((:=>)))
import qualified Data.IntMap.Strict                 as IM
import qualified Data.List                          as L
import qualified Data.Sequence                      as Seq
import qualified Data.Text                          as T
import           Data.Text.Zipper
import qualified Data.Text.Zipper                   as TZ
import           Data.These

import qualified Graphics.Vty                       as V
import           Reflex
import           Reflex.Network
import           Reflex.Potato.Helpers
import           Reflex.Vty

--moveChar :: Char
--moveChar = '≡'
hiddenChar :: Char
hiddenChar = '-'
visibleChar :: Char
visibleChar = 'e'
lockedChar :: Char
lockedChar = '@'
unlockedChar :: Char
unlockedChar = 'a'
expandChar :: Char
expandChar = '»'
closeChar :: Char
closeChar = '«'

{-# INLINE if' #-}
if' :: Bool -> a -> a -> a
if' True  x _ = x
if' False _ y = y



data LayerWidgetConfig t = LayerWidgetConfig {
  _layerWidgetConfig_pfctx       :: PFWidgetCtx t
  , _layerWidgetConfig_layers    :: Dynamic t LayerEntries
  , _layerWidgetConfig_selection :: Dynamic t Selection
}

data LayerWidget t = LayerWidget {
  _layerWidget_select              :: Event t (Bool, LayerPos)
  , _layerWidget_changeName        :: Event t ControllersWithId
  -- TODO expand to support multi-move
  , _layerWidget_move              ::Event t (LayerPos, LayerPos)
  , _layerWidget_consumingKeyboard :: Behavior t Bool

  -- TODO
  --, _layerWidget_layerWidgetTestOutput :: LayerWidgetTestOutput t
}

holdLayerWidget :: forall t m. (Adjustable t m, PostBuild t m, NotReady t m,  MonadHold t m, MonadFix m, MonadNodeId m)
  => LayerWidgetConfig t
  -> VtyWidget t m (LayerWidget t)
holdLayerWidget LayerWidgetConfig {..} = do

  regionWidthDyn <- displayWidth
  regionHeightDyn <- displayHeight
  let
    padTop = 0
    padBottom = 0
    regionDyn = ffor2 regionWidthDyn regionHeightDyn (,)

  -- ::actually draw images::
  let

    makeLayerImage :: Int -> LayerEntry -> V.Image
    makeLayerImage width lentry@LayerEntry {..} = r where
      ident = _layerEntry_depth
      (rid,_,SEltLabel label _) = _layerEntry_superSEltLabel
      -- TODO selected state
      attr = if False then lg_layer_selected else lg_default

      r = V.text' attr . T.pack . L.take width
        $ replicate ident ' '
        -- <> [moveChar]
        <> if' (layerEntry_isFolderStart lentry) (if' _layerEntry_isCollapsed [expandChar] [closeChar]) []
        <> if' (lockHiddenStateToBool _layerEntry_hideState) [hiddenChar] [visibleChar]
        <> if' (lockHiddenStateToBool _layerEntry_lockState) [lockedChar] [unlockedChar]
        <> " "
        <> show rid
        <> " "
        <> T.unpack label
    layerImages :: Behavior t [V.Image]
    layerImages = current $ fmap ((:[]) . V.vertCat)
      $ ffor2 regionDyn _layerWidgetConfig_layers $ \(w,h) lentries ->
        map (makeLayerImage w) . L.take (max 0 (h - padBottom)) $ toList lentries
  tellImages layerImages

  return $ LayerWidget never never never (constant False)
