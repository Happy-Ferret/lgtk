{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
module GUI.Gtk.Structures.IO
    ( runWidget
    , gtkContext
    ) where

import Control.Category
import Control.Monad
import Control.Monad.Writer
import Control.Concurrent
import Data.Maybe
import Prelude hiding ((.), id)

import Graphics.UI.Gtk hiding (Widget)
import qualified Graphics.UI.Gtk as Gtk

import Control.Monad.Restricted (Morph)
import Control.Monad.Register (Command (..))
import GUI.Gtk.Structures

gtkContext :: (Morph IO IO -> IO SWidget) -> IO ()
gtkContext m = do
    _ <- unsafeInitGUIForThreadedRTS
    tid <- myThreadId
    let post :: Morph IO IO
        post e = do
            tid' <- myThreadId
            if tid' == tid then e else postGUISync e
    c <- m post
    window <- windowNew
    set window [ containerBorderWidth := 10, containerChild := snd c ]
    _ <- window `on` deleteEvent $ liftIO mainQuit >> return False
    widgetShowAll window
    mainGUI

type SWidget = (IO (), Gtk.Widget)

-- | Run an @IO@ parametrized interface description with Gtk backend
runWidget
    :: forall n m . (MonadIO m, MonadIO n)
    => Morph n IO
    -> (IO () -> IO ())
    -> Morph IO IO
    -> Widget n m
    -> m SWidget
runWidget nio post' post = toWidget
 where
    liftIO' :: MonadIO k => IO a -> k a
    liftIO' = liftIO . post

    reg :: Receive n m a -> Receive IO m a
    reg s f = liftM (nio .) $ s $ liftM (fmap liftIO) . liftIO' . f . (nio .)

    ger :: (Command -> IO ()) -> Send n m a -> Send IO m a
    ger hd s f = s $ \a -> liftIO' $ do
        hd Block
        f a
        hd Unblock

    nhd :: Command -> IO ()
    nhd = const $ return ()

    toWidget :: Widget n m -> m SWidget
    toWidget i = case i of

        Action m -> m >>= toWidget
        Label s -> do
            w <- liftIO' $ labelNew Nothing
            ger nhd s $ labelSetLabel w
            return' w
        Button s sens col m -> do
            w <- liftIO' buttonNew
            hd <- reg m $ \re -> on' w buttonActivated $ re ()
            ger hd s $ buttonSetLabel w
            ger hd sens $ widgetSetSensitive w
            ger hd col $ \c -> do
                widgetModifyBg w StateNormal c
                widgetModifyBg w StatePrelight c
            return' w
        Entry (r, s) -> do
            w <- liftIO' entryNew
            hd <- reg s $ \re -> on' w entryActivate $ entryGetText w >>= re
            hd' <- reg s $ \re -> on' w focusOutEvent $ lift $ entryGetText w >>= re >> return False
            ger (\x -> hd x >> hd' x) r $ entrySetText w
            return' w
        Checkbox (r, s) -> do
            w <- liftIO' checkButtonNew
            hd <- reg s $ \re -> on' w toggled $ toggleButtonGetActive w >>= re
            ger hd r $ toggleButtonSetActive w
            return' w
        Combobox ss (r, s) -> do
            w <- liftIO' comboBoxNewText
            liftIO' $ flip mapM_ ss $ comboBoxAppendText w
            hd <- reg s $ \re -> on' w changed $ fmap (max 0) (comboBoxGetActive w) >>= re
            ger hd r $ comboBoxSetActive w
            return' w
        List o xs -> do
            ws <- mapM toWidget xs
            w <- liftIO' $ case o of
                Vertical -> fmap castToBox $ vBoxNew False 1
                Horizontal -> fmap castToBox $ hBoxNew False 1
            shs <- forM ws $ liftIO' . containerAdd'' w . snd
            liftM (mapFst (sequence_ shs >>)) $ return'' ws w
        Notebook' s xs -> do
            ws <- mapM (toWidget . snd) xs
            w <- liftIO' notebookNew
            forM_ (zip ws xs) $ \(ww, (s, _)) -> do
                liftIO' . flip (notebookAppendPage w) s $ snd $ ww
            _ <- reg s $ \re -> on' w switchPage $ re
            return'' ws w
        Cell onCh f -> do
            let b = False
            w <- liftIO' $ case b of
                True -> fmap castToContainer $ hBoxNew False 1
                False -> fmap castToContainer $ alignmentNew 0 0 1 1
            sh <- liftIO $ newMVar $ return ()
            onCh $ \bv -> do
                mx <- f toWidget bv
                return $ mx >>= \(x, y) -> liftIO' $ do 
                    _ <- swapMVar sh x
                    containerForeach w $ if b then widgetHideAll else containerRemove w 
                    post' $ post $ do
                        ch <- containerGetChildren w
                        when (y `notElem` ch) $ containerAdd w y
                        x
            liftM (mapFst (join (readMVar sh) >>)) $ return'' [] w

on' :: GObjectClass x => x -> Signal x c -> c -> IO (Command -> IO ())
on' o s c = liftM (flip f) $ on o s c where
    f Kill = signalDisconnect
    f Block = signalBlock
    f Unblock = signalUnblock

return' :: Monad m => WidgetClass x => x -> m SWidget
return' w = return (widgetShowAll w, castToWidget w)

return'' :: Monad m => WidgetClass x => [SWidget] -> x -> m SWidget
return'' ws w = return (mapM_ fst ws >> widgetShow w, castToWidget w)

mapFst f (a, b) = (f a, b)

containerAdd'' w x = do
    a <- alignmentNew 0 0 0 0
    containerAdd a x
    containerAdd w a
    set w [ boxChildPacking a := PackNatural ]
    return $ widgetShow a


