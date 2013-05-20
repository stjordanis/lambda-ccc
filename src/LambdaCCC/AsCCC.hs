{-# LANGUAGE TypeOperators, GADTs, KindSignatures, PatternGuards #-}
{-# OPTIONS_GHC -Wall #-}

-- DataKinds

-- {-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP
-- {-# OPTIONS_GHC -fno-warn-unused-binds   #-} -- TEMP

----------------------------------------------------------------------
-- |
-- Module      :  LambdaCCC.AsCCC
-- Copyright   :  (c) 2013 Tabula, Inc.
-- 
-- Maintainer  :  conal@tabula.com
-- Stability   :  experimental
-- 
-- Convert lambda expressions to CCC combinators
----------------------------------------------------------------------

module LambdaCCC.AsCCC 
  ( (:->)(..), (***), (&&&), konst, first, second
  , Name, E(..), Pat(..)
  , toCCC
  ) where

-- TODO: explicit exports

import Data.Functor ((<$>))
import Control.Monad (mplus)
import Data.Maybe (fromMaybe)

import Data.IsTy
import Data.Proof.EQ

import LambdaCCC.Misc
import LambdaCCC.Type

{--------------------------------------------------------------------
    CCC combinator form
--------------------------------------------------------------------}

infix 0 :->

-- | CCC combinator expressions
data (:->) :: * -> * -> * where
  Id       :: a :-> a
  (:.)     :: (b :-> c) -> (a :-> b) -> (a :-> c)
  Terminal :: a :-> Unit
  UKonst   :: b -> (Unit :-> b)
  Fst      :: a :* b :-> a
  Snd      :: a :* b :-> b
  Dup      :: a :-> a :* a
  (:***)   :: (a :-> c) -> (b :-> d) -> (a :* b :-> c :* d)
  Apply    :: ((a :=> b) :* a) :-> b
  Curry    :: (a :* b :-> c) -> (a :-> (b -> c))
  Uncurry  :: (a :-> (b -> c)) -> (a :* b :-> c)
  Add      :: Num a => (a :* a) :-> a
  -- and more primitives ...

infixr 3 &&&, ***

(***) :: (a :-> c) -> (b :-> d) -> (a :* b :-> c :* d)
(***) = (:***)

(&&&) :: (a :-> c) -> (a :-> d) -> (a :-> c :* d)
f &&& g = (f *** g) :. Dup

konst :: b -> (a :-> b)
konst b = UKonst b :. Terminal

first :: (a :-> c) -> (a :* b :-> c :* b)
first f = f *** Id

second :: (b :-> d) -> (a :* b :-> a :* d)
second g = Id *** g

{--------------------------------------------------------------------
    Lambda expressions
--------------------------------------------------------------------}

type Name = String

data E :: * -> * where
  Var :: Name -> Ty a -> E a
  Const :: a -> E a
  App :: E (a :=> b) -> E a -> E b
  Lam :: Pat a -> E b -> E (a :=> b)

data Pat :: * -> * where
  UnitP :: Pat Unit
  VarP  :: Name -> Ty a -> Pat a
  PairP :: Pat a -> Pat b -> Pat (a :* b)

type Context = Pat

toCCC :: E a -> (Unit :-> a)
toCCC = convert UnitP

-- | Convert @\ p -> e@ to CCC combinators
convert :: Pat a -> E b -> (a :-> b)
convert _ (Const c) = konst c
convert k (Var n t) = fromMaybe (error $ "unbound variable: " ++ n) $
                      convertVar k n t
convert k (App u v) = Apply :. (convert k u &&& convert k v)
convert k (Lam p e) = Curry (convert (PairP k p) e)

convertVar :: Context q -> Name -> Ty a -> Maybe (q :-> a)
convertVar (VarP x q) n a | x == n, Just Refl <- q `tyEq` a = Just Id
                          | otherwise = Nothing
convertVar UnitP _ _ = Nothing
convertVar (PairP q r) n a = 
  ((:. Fst) <$> convertVar q n a) `mplus` ((:. Snd) <$> convertVar r n a)