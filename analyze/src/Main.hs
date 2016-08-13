{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE UnicodeSyntax #-}

module Main where

import           Control.Arrow.Unicode
import           Control.Monad
import           Data.Aeson               (ToJSON)
import           Data.Aeson.Encode.Pretty (encodePretty)
import qualified Data.ByteString.Lazy     as B
import           Data.List                (isPrefixOf, nub, sort)
import           Data.String.Utils        (replace, strip)
import           Data.Time                (Day, fromGregorian)
import           GHC.Generics
import           GHC.IO.Exception
import           Prelude.Unicode
import           System.Environment       (getArgs)
import           System.Process           (readProcessWithExitCode)
import           Text.HandsomeSoup
import           Text.Regex.TDFA
import           Text.XML.HXT.Core        (getText, hread, runLA, (//>), (>>>))


type SectionNumber = String

data Chamber = House | Senate
  deriving (Show, Generic)

data Amendment =
  Amendment {
      summary       ∷ String,
      citations     ∷ [SectionNumber],
      year          ∷ Integer,
      chapter       ∷ Integer,
      chamber       ∷ Chamber,
      bill          ∷ Integer,
      effectiveDate ∷ Day
    } deriving (Show, Generic)


instance ToJSON Amendment
instance ToJSON Chamber


main ∷ IO ()
main = do
  args ← getArgs
  when (length args /= 1) $
    fail "Usage: analyze [filename]"

  let pdfFilename = head args
  (errCode, rawHTML, stderr') ← runTika pdfFilename
  when (errCode /= ExitSuccess) $
    fail stderr'

  rawHTML
    |> htmlToJson
    |> B.putStr


runTika ∷ String → IO (ExitCode, String, String)
runTika pdfFilename =
  readProcessWithExitCode "java" ["-jar", "/Users/robb/lib/tika-app.jar", "--html", pdfFilename] ""


htmlToJson ∷ String → B.ByteString
htmlToJson = makeAmendment ⋙ encodePretty


makeAmendment ∷ String → Amendment
makeAmendment html =
  let phrases = html |> paragraphs
  in Amendment {
    summary   = phrases |> findSummary,
    citations = phrases |> findSectionNumbers,
    chamber   = House,
    bill      = 4014,
    year      = 2016,
    chapter   = 24,
    effectiveDate = fromGregorian 2016 5 5
  }


paragraphs ∷ String → [String]
paragraphs html =
  -- TODO: Switch to TagSoup for the HTML parsing
  let allParagraphs = runLA (hread >>> css "p" //> getText) html
  in filter (not ∘ isPdfMetadata) allParagraphs


findSummary ∷ [String] → String
findSummary phrases =
  case filter isSummary phrases of
    [aSummary] → cleanUp aSummary
    _          → "(Summary is not available)"


findSectionNumbers ∷ [String] → [SectionNumber]
findSectionNumbers phrases =
  phrases
    |> fmap sectionNumbers
    |> concat
    |> nub
    |> sort


sectionNumbers ∷ String → [String]
sectionNumbers phrase =
  -- Match ORS section numbers like 40.230 and 743A.144.
  getAllTextMatches (phrase =~ "[0-9]{1,3}[A-C]?\\.[0-9]{3}")


isSummary ∷ String → Bool
isSummary sentence =
  "Relating to" `isPrefixOf` sentence


isPdfMetadata ∷ String → Bool
isPdfMetadata text =
  "<<\n" `isPrefixOf` text


cleanUp ∷ String → String
cleanUp = strip ⋙ fixWhitespace ⋙ fixHyphenation


fixWhitespace  = replace "\n" " "
fixHyphenation = replace "- " ""


--
-- The Railway operator
--
(|>) x f = f x
