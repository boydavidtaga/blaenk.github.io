module Site.PandocCompiler (myPandocCompiler) where

import Hakyll.Web.Pandoc

import Text.Pandoc

import qualified Data.Set as S
import Hakyll.Core.Compiler
import Hakyll.Core.Item
import System.IO.Unsafe
import System.Process
import System.IO (hClose, hGetContents, hPutStr, hSetEncoding, localeEncoding)
import Control.Concurrent (forkIO)
import Data.List
import Text.Regex.TDFA
import Text.Regex.TDFA.String

myPandocCompiler :: Compiler (Item String)
myPandocCompiler = pandocCompilerWithTransform readerOptions writerOptions pygmentsTransformer

--tableOfContents :: Block -> Block
--tableOfContents ()

pygmentsTransformer :: Pandoc -> Pandoc
pygmentsTransformer = bottomUp pygments

pygments :: Block -> Block
pygments (CodeBlock (_, _, namevals) contents) =
  let lang = case lookup "lang" namevals of
               Just lang_ -> lang_
               Nothing -> "text"
      text = case lookup "text" namevals of
               Just text_ -> text_
               Nothing -> ""
      colored = pygmentize lang contents
      code = numberedCode colored lang
      caption = if text /= ""
                  then "<figcaption><span>" ++ text ++ "</span></figcaption>"
                  else ""
      composed = "<figure class=\"code\">\n" ++ code ++ caption ++ "</figure>"
  in RawBlock "html" composed
pygments x = x

numberedCode :: String -> String -> String
numberedCode code lang =
  let codeLines = lines $ extractCode code
      wrappedCode = unlines $ wrapCodeLines codeLines
      numbers = unlines $ numberLines codeLines
  in "<div class='highlight'><table><tr><td class='gutter'><pre class='line-numbers'>" ++
     numbers ++ "</pre></td><td class='code'><pre><code class='" ++ lang ++ "'>" ++ wrappedCode ++
     "</code></pre></td></tr></table></div>"
  where wrapCodeLines codeLines = map wrapCodeLine codeLines
          where wrapCodeLine line = "<span class='line'>" ++ line ++ "</span>"
        numberLines codeLines =
          let (_, res) = mapAccumL numberLine 1 codeLines
          in res
            where numberLine :: Integer -> String -> (Integer, String)
                  numberLine num _ = (num + 1, "<span class='line-number'>" ++ show num ++ "</span>")

extractCode :: String -> String
extractCode pygmentsResult =
  let (Right pat) = compile blankCompOpt defaultExecOpt "<pre>(.+)</pre>"
      (Right (Just (_, _, _, matched:_))) = regexec pat pygmentsResult
  in matched

pygmentize :: String -> String -> String
pygmentize lang contents = unsafePerformIO $ do
  let process = (shell ("pygmentize -f html -l " ++ lang ++ " -P encoding=utf-8")) {std_in = CreatePipe, std_out = CreatePipe, close_fds = True}
      writer handle input = do
        hSetEncoding handle localeEncoding
        hPutStr handle input
      reader handle = do
        hSetEncoding handle localeEncoding
        hGetContents handle

  (Just stdin, Just stdout, _, _) <- createProcess process

  _ <- forkIO $ do
    writer stdin contents
    hClose stdin

  reader stdout

readerOptions :: ReaderOptions
readerOptions = def {
  readerSmart = True
  }

writerOptions :: WriterOptions
writerOptions = 
  let extensions = S.fromList [
        Ext_literate_haskell,
        Ext_tex_math_dollars
        ]
  in def {
    writerTableOfContents = True,
    writerHTMLMathMethod = MathJax "",
    writerExtensions = S.union extensions (writerExtensions def)
    }
