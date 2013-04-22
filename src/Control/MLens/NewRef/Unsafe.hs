{-# LANGUAGE RankNTypes #-}
-- | This module export only the @NewRef@ instance for @IO@ which does not fulfil the @NewRef@ laws in a multi-threaded environment.
module Control.MLens.NewRef.Unsafe
    () where

import Data.IORef

import Data.MLens.Ref
import Control.MLens.NewRef

-- | Note that this instance does not fulfil the @NewRef@ laws in a multi-threaded environment.
instance NewRef IO where
    newRef x = do
        r <- newIORef x
        return $ mkRef (readIORef r) (writeIORef r)


