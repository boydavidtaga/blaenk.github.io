{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module Site.Fields (
  defaultCtx,
  postCtx,
  archiveCtx,
) where

import Hakyll
import Data.Monoid (mconcat)
import System.Process
import System.FilePath

-- for groupByYear
import Data.List (sortBy, groupBy)
import Data.Ord (comparing)
import Control.Monad (liftM)
import System.Locale (defaultTimeLocale)
import Data.Time.Clock
import Data.Time.Calendar

defaultCtx :: Context String
defaultCtx = mconcat
  [ bodyField "body"
  , metadataField
  , niceUrlField "url"
  , pathField "path"
  , gitTag "git"
  , constField "title" "Blaenk Denum"
  , constField "commentsJS" ""
  , missingField
  ]

postCtx :: Context String
postCtx = mconcat
  [ dateField "datePost" "%B %e, %Y"
  , dateField "dateArchive" "%b %e"
  , commentsTag "comments"
  , commentsJS "commentsJS"
  , defaultCtx
  ]

--[ field "posts" (\_ -> archivesList recentFirst)
archiveCtx :: Context String
archiveCtx = mconcat
  [ field "archives" (\_ -> yearArchives) :: Context String
  , constField "title" "Archives"
  , constField "commentsJS" ""
  , defaultCtx
  ]

-- url field without /index.html
niceUrlField :: String -> Context a
niceUrlField key = field key $
  fmap (maybe "" (removeIndexStr . toUrl)) . getRoute . itemIdentifier
  where removeIndexStr url = case splitFileName url of
          (dir, "index.html") -> dir
          _ -> url

commentsOn :: (MonadMetadata m) => Item a -> m Bool
commentsOn item = do
  commentsMeta <- getMetadataField (itemIdentifier item) "comments"
  return $ case commentsMeta of
    Just "false" -> False
    Just "off" -> False
    _ -> True

-- gets passed the key and the item apparently
commentsTag :: String -> Context String
commentsTag key = field key $ \item -> do
    comments <- commentsOn item
    if comments
      then unsafeCompiler $ readFile "templates/comments.html"
      else return ""

commentsJS :: String -> Context String
commentsJS key = field key $ \item -> do
    comments <- commentsOn item
    if comments
      then unsafeCompiler $ readFile "templates/comments-js.html"
      else return ""

gitTag :: String -> Context String
gitTag key = field key $ \_ -> do
  unsafeCompiler $ do
    sha <- readProcess "git" ["log", "-1", "HEAD", "--pretty=format:%H"] []
    message <- readProcess "git" ["log", "-1", "HEAD", "--pretty=format:%s"] []
    return ("<a href=\"https://github.com/blaenk/hakyll/commit/" ++ sha ++
           "\" title=\"" ++ message ++ "\">" ++ (take 8 sha) ++ "</a>")

archivesList :: ([Item String] -> Compiler [Item String]) -> Compiler String
archivesList sortFilter = do
    posts   <- sortFilter =<< loadAll "posts/*"
    itemTpl <- loadBody "templates/index-post.html"
    list    <- applyTemplateList itemTpl postCtx posts
    return list

yearArchives :: Compiler String
yearArchives = do
    thisYear <- unsafeCompiler . fmap yearFromUTC $ getCurrentTime
    posts    <- groupByYear =<< loadAll "posts/*"    :: Compiler [(Integer, [Item String])]
    itemTpl  <- loadBody "templates/index-post.html" :: Compiler Template
    archiveTpl <- loadBody "templates/archive.html" :: Compiler Template
    list     <- mapM (genArchives itemTpl archiveTpl thisYear) posts :: Compiler [String]
    return $ concat list :: Compiler String
    where genArchives :: Template -> Template -> Integer -> (Integer, [Item String]) -> Compiler String
          genArchives itemTpl archiveTpl curYear (year, posts) = do
            templatedPosts <- applyTemplateList itemTpl postCtx posts :: Compiler String
            let yearCtx :: Context String
                yearCtx = if curYear == year
                          then constField "year" ""
                          else constField "year" ("<h2>" ++ show year ++ "</h2>")
                ctx' :: Context String
                ctx' = mconcat [ yearCtx
                               , constField "posts" templatedPosts
                               , archiveCtx
                               , missingField
                               ]
            itm <- makeItem "" :: Compiler (Item String)
            gend <- applyTemplate archiveTpl ctx' itm :: Compiler (Item String)
            return $ itemBody gend

groupByYear :: (MonadMetadata m, Functor m) => [Item a] -> m [(Integer, [Item a])]
groupByYear items =
    groupByYearM . fmap reverse . sortByM (getItemUTC defaultTimeLocale . itemIdentifier) $ items
  where
    sortByM :: (Monad m) => (a -> m UTCTime) -> [a] -> m [(Integer, a)]
    sortByM f xs = -- sort the list comparing the UTCTime
                   liftM (map (\(utc, post) -> (yearFromUTC utc, post)) . sortBy (comparing fst)) $
                   -- get them in a tuple of Item [(UTCTime, Item a)]
                   mapM (\x -> liftM (,x) (f x)) xs

    groupByYearM :: (Monad m) => m [(Integer, a)] -> m [(Integer, [a])]
    groupByYearM xs = liftM (map mapper . groupBy f) xs
      where f a b = (fst a) == (fst b)
            mapper [] = error "what"
            mapper posts@((year, _):_) = (year, (map snd posts))

yearFromUTC :: UTCTime -> Integer
yearFromUTC utcTime = let (year, _, _) = toGregorian $ utctDay utcTime in year

