{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Workflow.Waiting where

import Data.OrgMode.Parse
import qualified Data.Text as T
import Data.Time.Clock
import Data.Time.LocalTime
import Data.Tuple
import Import
import Workflow.OptParse
import Workflow.Utils

waiting :: Path Abs Dir -> ShouldPrint -> Settings -> IO ()
waiting workDir shouldPrint settings = do
    (waitingHeadings, errMess) <- getWaitingHeadings workDir settings
    string <- headingsToString waitingHeadings
    printErrMess errMess shouldPrint
    putStr string

headingsToString :: [(Heading, Path Rel File)] -> IO String
headingsToString waitingHeadings = do
    currentTime <- zonedTimeToLocalTime <$> getZonedTime
    timezone <- getCurrentTimeZone
    pure $ waitingHeadingsToString timezone currentTime waitingHeadings

getWaitingHeadings :: Path Abs Dir
                   -> Settings
                   -> IO ([(Heading, Path Rel File)], [String])
getWaitingHeadings workDir sett = do
    (headings, errMess) <- getHeadingsFromDir workDir sett
    pure (filter (isWaiting . fst) headings, errMess)

waitingHeadingsToString :: TimeZone
                        -> LocalTime
                        -> [(Heading, Path Rel File)]
                        -> String
waitingHeadingsToString timezone currentTime waitingHeadings =
    let tasks =
            sortBy ordenWaitingTasks $
            catMaybes $ fmap toWaitingTask waitingHeadings
    in formatStringAsTable $
       fmap (waitingTaskToStrings timezone currentTime) tasks

ordenWaitingTasks :: WaitingTask -> WaitingTask -> Ordering
ordenWaitingTasks task1 task2 =
    let maybeDate1 = date task1
        maybeDate2 = date task2
    in case (maybeDate1, maybeDate2) of
           (Nothing, Nothing) -> EQ
           (Just _, Nothing) -> LT
           (Nothing, Just _) -> GT
           (Just date1, Just date2) -> compare date1 date2

isWaiting :: Heading -> Bool
isWaiting Heading {..} =
    keyword == Just StateKeyword {unStateKeyword = "WAITING"}

waitingTaskToStrings :: TimeZone -> LocalTime -> WaitingTask -> [String]
waitingTaskToStrings timezone currentTime WaitingTask {..} =
    let file = fromRelFile orgFile
    in case date of
           Nothing -> [file, "WAITING " ++ description, ""]
           Just realDate ->
               let nOfDays = getDaysDifference timezone currentTime realDate
               in [file, "WAITING " ++ description, show nOfDays ++ " days"]

getDaysDifference :: TimeZone -> LocalTime -> LocalTime -> Int
getDaysDifference timezone time1 time2 =
    let utcTime1 = localTimeToUTC timezone time1
        utcTime2 = localTimeToUTC timezone time2
    in floor $ diffUTCTime utcTime1 utcTime2 / nominalDay

data WaitingTask = WaitingTask
    { date :: Maybe LocalTime
    , orgFile :: Path Rel File
    , description :: String
    } deriving (Show, Eq)

toWaitingTask :: (Heading, Path Rel File) -> Maybe WaitingTask
toWaitingTask (heading@Heading {..}, filePath) =
    if isWaiting heading
        then let date = getDate heading
             in Just $ WaitingTask date filePath (T.unpack title)
        else Nothing
