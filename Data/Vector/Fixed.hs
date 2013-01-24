{-# LANGUAGE EmptyDataDecls        #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE Rank2Types            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE ScopedTypeVariables   #-}
-- |
-- Generic API for vectors with fixed length.
--
-- For encoding of vector size library uses Peano naturals defined in
-- the library. At come point in the future it would make sense to
-- switch to new GHC type level numerals.
module Data.Vector.Fixed (
    -- * Vector type class
    -- ** Vector size
    Dim
  , Z
  , S
    -- ** Synonyms for small numerals
  , N1
  , N2
  , N3
  , N4
  , N5
  , N6
    -- ** Type class
  , Vector(..)
  , VectorN
  , Arity
  , Fun(..)
  , length
  , convertContinuation
    -- * Generic functions
    -- ** Literal vectors
  , New
  , vec
  , con
  , (|>)
    -- ** Construction
  , replicate
  , replicateM
  , basis
  , generate
  , generateM
    -- ** Element access
  , head
  , tail
  , tailWith
  , (!)
    -- ** Map
  , map
  , mapM
  , mapM_
  , imap
  , imapM
  , imapM_
  , sequence
  , sequence_
    -- ** Folding
  , foldl
  , foldl1
  , foldM
  , ifoldl
  , ifoldM
    -- *** Special folds
  , sum
  , maximum
  , minimum
    -- ** Zips
  , zipWith
  , izipWith
    -- ** Conversion
  , convert
  , toList
  , fromList
    -- * Special types
  , VecList(..)
  ) where

import Data.Vector.Fixed.Internal

import qualified Prelude as P
import Prelude hiding ( replicate,map,zipWith,maximum,minimum
                      , foldl,foldl1,length,sum
                      , head,tail,mapM,mapM_,sequence,sequence_
                      )



----------------------------------------------------------------
-- Generic functions
----------------------------------------------------------------

type N1 = S Z
type N2 = S N1
type N3 = S N2
type N4 = S N3
type N5 = S N4
type N6 = S N5

-- | Change continuation type.
convertContinuation :: forall n a r. (Arity n)
                    => (forall v. (Dim v ~ n, Vector v a) => v a -> r)
                    -> Fun n a r
{-# INLINE convertContinuation #-}
convertContinuation f = fmap f g
  where
    g = construct :: Fun n a (VecList n a)


-- TODO: does not fuse!
-- | Newtype wrapper for partially constructed vectors. /n/ is number
--   of uninitialized elements.
--
--   Example of use:
--
-- >>> vec $ con |> 1 |> 3 :: Complex Double
-- > 1 :+ 3
newtype New n v a = New (Fn n a (v a))

-- | Convert fully applied constructor to vector
vec :: New Z v a -> v a
{-# INLINE vec #-}
vec (New v) = v

-- | Seed constructor
con :: Vector v a => New (Dim v) v a
{-# INLINE con #-}
con = f2n construct

-- | Apply another element to vector
(|>) :: New (S n) v a -> a -> New n v a
{-# INLINE  (|>) #-}
New f |> a = New (f a)
infixl 1 |>

f2n :: Fun n a (v a) -> New n v a
{-# INLINE f2n #-}
f2n (Fun f) = New f


----------------------------------------------------------------

-- | Replicate value /n/ times.
replicate :: Vector v a => a -> v a
{-# INLINE replicate #-}
replicate x = create $ Cont
            $ replicateF x

data T_replicate n = T_replicate

replicateF :: forall n a b. Arity n => a -> Fun n a b -> b
replicateF x (Fun h)
  = apply (\T_replicate -> (x, T_replicate))
          (T_replicate :: T_replicate n)
          h

-- | Execute monadic action for every element of vector.
replicateM :: (Vector v a, Monad m) => m a -> m (v a)
{-# INLINE replicateM #-}
replicateM x = replicateFM x construct

replicateFM :: forall m n a b. (Monad m, Arity n) => m a -> Fun n a b -> m b
replicateFM act (Fun h)
  = applyM (\T_replicate -> do { a <- act; return (a, T_replicate) } )
           (T_replicate :: T_replicate n)
           h


----------------------------------------------------------------

-- | Unit vector along Nth axis,
basis :: forall v a. (Vector v a, Num a) => Int -> v a
{-# INLINE basis #-}
basis n = create $ Cont
        $ basisF n

newtype T_basis n = T_basis Int

basisF :: forall n a b. (Num a, Arity n) => Int -> Fun n a b -> b
basisF n0 (Fun f)
  = apply (\(T_basis n) -> ((if n == 0 then 1 else 0) :: a, T_basis (n - 1)))
          (T_basis n0 :: T_basis n)
          f


----------------------------------------------------------------

-- | Generate vector.
generate :: forall v a. (Vector v a) => (Int -> a) -> v a
{-# INLINE generate #-}
generate f = create $ Cont
           $ generateF f

newtype T_generate n = T_generate Int

generateF :: forall n a b. (Arity n) => (Int -> a) -> Fun n a b -> b
generateF g (Fun f)
  = apply (\(T_generate n) -> (g n, T_generate (n + 1)))
          (T_generate 0 :: T_generate n)
          f

-- | Monadic generation
generateM :: forall m v a. (Monad m, Vector v a) => (Int -> m a) -> m (v a)
{-# INLINE generateM #-}
generateM f = generateFM f construct

generateFM :: forall m n a b. (Monad m, Arity n) => (Int -> m a) -> Fun n a b -> m b
generateFM g (Fun f)
  = applyM (\(T_generate n) -> do { a <- g n; return (a, T_generate (n + 1)) } )
           (T_generate 0 :: T_generate n)
           f


----------------------------------------------------------------

-- | First element of vector.
head :: (Vector v a, Dim v ~ S n) => v a -> a
{-# INLINE head #-}
head v = inspectV v
       $ headF

data T_head a n = T_head (Maybe a)

headF :: forall n a. Arity (S n) => Fun (S n) a a
headF = Fun $ accum (\(T_head m) a -> T_head $ case m of { Nothing -> Just a; x -> x })
                    (\(T_head (Just x)) -> x)
                    (T_head Nothing :: T_head a (S n))


----------------------------------------------------------------

-- | Tail of vector.
tail :: (Vector v a, Vector w a, Dim v ~ S (Dim w))
     => v a -> w a
{-# INLINE tail #-}
tail v = create $ Cont
       $ inspectV v
       . tailF

tailF :: Arity n => Fun n a b -> Fun (S n) a b
{-# INLINE tailF #-}
tailF (Fun f) = Fun (\_ -> f)

-- | Continuation variant of tail. It should be used when tail of
--   vector is immediately deconstructed with polymorphic
--   function. For example @'sum' . 'tail'@ will fail with unhelpful
--   error message because return value of @tail@ is polymorphic. But
--   @'tailWith' 'sum'@ works just fine.
tailWith :: (Arity n, Vector v a, Dim v ~ S n)
         => (forall w. (Vector w a, Dim w ~ n) => w a -> r) -- ^ Continuation
         -> v a                                             -- ^ Vector
         -> r
{-# INLINE tailWith #-}
tailWith f v = inspectV v
             $ tailF
             $ convertContinuation f

----------------------------------------------------------------

-- | /O(n)/ Get vector's element at index i.
(!) :: (Vector v a) => v a -> Int -> a
{-# INLINE (!) #-}
v ! i = inspectV v
      $ elemF i

newtype T_Elem a n = T_Elem (Either Int a)

elemF :: forall n a. Arity n => Int -> Fun n a a
elemF n
  -- This is needed because of possible underflow during subtraction
  | n < 0     = error "Data.Vector.Fixed.!: index out of range"
  | otherwise = Fun $ accum
     (\(T_Elem x) a -> T_Elem $ case x of
                         Left  0 -> Right a
                         Left  i -> Left (i - 1)
                         r       -> r
     )
     (\(T_Elem x) -> case x of
                       Left  _ -> error "Data.Vector.Fixed.!: index out of range"
                       Right a -> a
     )
     ( T_Elem (Left n) :: T_Elem a n)


----------------------------------------------------------------

-- | Left fold over vector
foldl :: Vector v a => (b -> a -> b) -> b -> v a -> b
{-# INLINE foldl #-}
foldl f z v = inspectV v
            $ foldlF f z

-- | Monadic fold over vector.
foldM :: (Vector v a, Monad m) => (b -> a -> m b) -> b -> v a -> m b
{-# INLINE foldM #-}
foldM f x v = foldl go (return x) v
  where
    go m a = do b <- m
                f b a


newtype T_foldl b n = T_foldl b

foldlF :: forall n a b. Arity n => (b -> a -> b) -> b -> Fun n a b
{-# INLINE foldlF #-}
foldlF f b = Fun $ accum (\(T_foldl r) a -> T_foldl (f r a))
                         (\(T_foldl r) -> r)
                         (T_foldl b :: T_foldl b n)

-- | Left fold over vector
foldl1 :: (Vector v a, Dim v ~ S n) => (a -> a -> a) -> v a -> a
{-# INLINE foldl1 #-}
foldl1 f v = inspectV v
           $ foldl1F f


-- Implementation of foldl1F is particularly ugly. It could be
-- expressed in terms of foldlF:
--
-- > foldl1F f = Fun $ \a -> case foldlF f a :: Fun n a a of Fun g -> g
--
-- But it require constraint `Arity n` whereas foldl1 provide
-- Arity (S n). Latter imply former but GHC cannot infer it. So it
-- 'Arity n' begin to propagate through contexts. It's not acceptable.

newtype T_foldl1 a n = T_foldl1 (Maybe a)

foldl1F :: forall n a. (Arity (S n)) => (a -> a -> a) -> Fun (S n) a a
{-# INLINE foldl1F #-}
foldl1F f = Fun $ accum (\(T_foldl1 r) a -> T_foldl1 $ Just $ maybe a (flip f a) r)
                        (\(T_foldl1 (Just x)) -> x)
                        (T_foldl1 Nothing :: T_foldl1 a (S n))


-- | Left fold over vector. Function is applied to each element and
--   its index.
ifoldl :: Vector v a => (b -> Int -> a -> b) -> b -> v a -> b
{-# INLINE ifoldl #-}
ifoldl f z v = inspectV v
            $ ifoldlF f z

-- | Left monadic fold over vector. Function is applied to each element and
--   its index.
ifoldM :: (Vector v a, Monad m) => (b -> Int -> a -> m b) -> b -> v a -> m b
{-# INLINE ifoldM #-}
ifoldM f x v = ifoldl go (return x) v
  where
    go m i a = do { b <- m; f b i a }

data T_ifoldl b n = T_ifoldl {-# UNPACK #-} !Int b

ifoldlF :: forall n a b. Arity n => (b -> Int -> a -> b) -> b -> Fun n a b
{-# INLINE ifoldlF #-}
ifoldlF f b = Fun $
    accum (\(T_ifoldl i r) a -> T_ifoldl (i + 1) (f r i a))
          (\(T_ifoldl _ r) -> r)
          (T_ifoldl 0 b :: T_ifoldl b n)



----------------------------------------------------------------

-- | Sum all elements in the vector
sum :: (Vector v a, Num a) => v a -> a
{-# INLINE sum #-}
sum = foldl (+) 0

-- | Maximum element of vector
maximum :: (Vector v a, Dim v ~ S n, Ord a) => v a -> a
{-# INLINE maximum #-}
maximum = foldl1 max

-- | Minimum element of vector
minimum :: (Vector v a, Dim v ~ S n, Ord a) => v a -> a
{-# INLINE minimum #-}
minimum = foldl1 min



----------------------------------------------------------------

-- | Map over vector
map :: (Vector v a, Vector v b) => (a -> b) -> v a -> v b
{-# INLINE map #-}
map f v = create $ Cont
        $ inspectV v
        . mapF f

-- | Evaluate every action in the vector from left to right.
sequence :: (Vector v a, Vector v (m a), Monad m) => v (m a) -> m (v a)
{-# INLINE sequence #-}
sequence = mapM id

-- | Evaluate every action in the vector from left to right and ignore result
sequence_ :: (Vector v (m a), Monad m) => v (m a) -> m ()
{-# INLINE sequence_ #-}
sequence_ = mapM_ id


-- | Monadic map over vector.
mapM :: (Vector v a, Vector v b, Monad m) => (a -> m b) -> v a -> m (v b)
{-# INLINE mapM #-}
mapM f v = inspectV v
         $ mapFM f
         $ construct

-- | Apply monadic action to each element of vector and ignore result.
mapM_ :: (Vector v a, Monad m) => (a -> m b) -> v a -> m ()
{-# INLINE mapM_ #-}
mapM_ f = foldl (\m a -> m >> f a >> return ()) (return ())

newtype T_map b c n = T_map (Fn n b c)

mapF :: forall n a b c. Arity n => (a -> b) -> Fun n b c -> Fun n a c
mapF f (Fun h) = Fun $ accum (\(T_map g) a -> T_map (g (f a)))
                             (\(T_map g)   -> g)
                             (T_map h :: T_map b c n)

mapFM :: forall m n a b c. (Arity n, Monad m) => (a -> m b) -> Fun n b c -> Fun n a (m c)
mapFM f (Fun h) = Fun $ accumM (\(T_map g) a -> do { b <- f a; return (T_map (g b)) })
                               (\(T_map g) -> return g)
                               (return $ T_map h :: m (T_map b c n))



imap :: (Vector v a, Vector v b, Monad m) =>
    (Int -> a -> b) -> v a -> v b
{-# INLINE imap #-}
imap f v = inspectV v
         $ imapF f
         $ construct

imapM :: (Vector v a, Vector v b, Monad m) =>
    (Int -> a -> m b) -> v a -> m (v b)
{-# INLINE imapM #-}
imapM f v = inspectV v
         $ imapFM f
         $ construct

imapM_ :: (Vector v a, Monad m) => (Int -> a -> m b) -> v a -> m ()
{-# INLINE imapM_ #-}
imapM_ f = ifoldl (\m i a -> m >> f i a >> return ()) (return ())


data T_imap b c n = T_imap {-# UNPACK #-} !Int (Fn n b c)

imapF :: forall n a b c. Arity n
      => (Int -> a -> b) -> Fun n b c -> Fun n a c
imapF f (Fun h) = Fun $
  accum (\(T_imap i g) a -> T_imap (i + 1) (g (f i a)))
        (\(T_imap _ g)    -> g)
        (T_imap 0 h :: T_imap b c n)

imapFM :: forall m n a b c. (Arity n, Monad m) =>
    (Int -> a -> m b) -> Fun n b c -> Fun n a (m c)
imapFM f (Fun h) = Fun $
  accumM (\(T_imap i g) a -> do b <- f i a
                                return (T_imap (i + 1) (g b)))
         (\(T_imap _ g) -> return g)
         (return $ T_imap 0 h :: m (T_imap b c n))



----------------------------------------------------------------

-- | Zip two vector together.
zipWith :: (Vector v a, Vector v b, Vector v c)
        => (a -> b -> c) -> v a -> v b -> v c
{-# INLINE zipWith #-}
zipWith f v u = create $ Cont
              $ inspectV u
              . inspectV v
              . zipWithF f

data T_zip a c r n = T_zip (VecList n a) (Fn n c r)

zipWithF :: forall n a b c d. Arity n
         => (a -> b -> c) -> Fun n c d -> Fun n a (Fun n b d)
zipWithF f (Fun g0) =
  fmap (\v -> Fun $ accum
              (\(T_zip (VecList (a:as)) g) b -> T_zip (VecList as) (g (f a b)))
              (\(T_zip _ x) -> x)
              (T_zip v g0 :: T_zip a c d n)
       ) construct


-- | Zip two vector together.
izipWith :: (Vector v a, Vector v b, Vector v c)
         => (Int -> a -> b -> c) -> v a -> v b -> v c
{-# INLINE izipWith #-}
izipWith f v u = create $ Cont
               $ inspectV u
               . inspectV v
               . izipWithF f

data T_izip a c r n = T_izip Int (VecList n a) (Fn n c r)

izipWithF :: forall n a b c d. Arity n
          => (Int -> a -> b -> c) -> Fun n c d -> Fun n a (Fun n b d)
izipWithF f (Fun g0) =
  fmap (\v -> Fun $ accum
              (\(T_izip i (VecList (a:as)) g) b -> T_izip (i+1) (VecList as) (g (f i a b)))
              (\(T_izip _ _ x) -> x)
              (T_izip 0 v g0 :: T_izip a c d n)
       ) construct


----------------------------------------------------------------

-- | Convert between different vector types
convert :: (Vector v a, Vector w a, Dim v ~ Dim w) => v a -> w a
{-# INLINE convert #-}
convert v = inspectV v construct
-- FIXME: check for fusion rules!

-- | Convert vector to the list
toList :: (Vector v a) => v a -> [a]
toList v
  = case inspectV v construct of VecList xs -> xs

-- | Create vector form list. List must have same length as the
--   vector.
fromList :: forall v a. (Vector v a) => [a] -> v a
{-# INLINE fromList #-}
fromList xs
  | length r == P.length xs = convert r
  | otherwise               = error "Data.Vector.Fixed.fromList: bad list length"
  where
   r = VecList xs :: VecList (Dim v) a


----------------------------------------------------------------
-- Data types
----------------------------------------------------------------

-- | Vector based on the lists. Not very useful by itself but is
--   necessary for implementation.
newtype VecList n a = VecList [a]
                      deriving (Show,Eq)

type instance Dim (VecList n) = n

newtype Flip f a n = Flip (f n a)

newtype T_list a n = T_list ([a] -> [a])

-- It's vital to avoid 'reverse' and build list using [a]->[a]
-- functions. Reverse is recursive and interferes with inlining.
instance Arity n => Vector (VecList n) a where
  construct = Fun $ accum
    (\(T_list xs) x -> T_list (xs . (x:)))
    (\(T_list xs) -> VecList (xs []) :: VecList n a)
    (T_list id :: T_list a n)
  inspect v (Fun f) = apply
    (\(Flip (VecList (x:xs))) -> (x, Flip (VecList xs)))
    (Flip v)
    f
  {-# INLINE construct #-}
  {-# INLINE inspect   #-}
instance Arity n => VectorN VecList n a
