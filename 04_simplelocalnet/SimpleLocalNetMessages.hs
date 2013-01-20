{-# LANGUAGE OverloadedStrings, TemplateHaskell, DeriveDataTypeable #-}
module Main

where

import System.Exit
import System.Environment (getArgs)
import System.IO
import System.Random (randomRIO)
import qualified System.Console.ANSI as ANSI
import Control.Monad (forever,forM_)
import Control.Concurrent (threadDelay)
import Data.Typeable
import Data.Binary
import qualified Data.ByteString.Char8 as BS

import Control.Distributed.Process
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import Control.Distributed.Process.Backend.SimpleLocalnet

data MyColor = Red | Blue | Yellow | Cyan
  deriving (Show, Enum, Typeable)

instance Binary MyColor where
  put c = put $ fromEnum c
  get = get >>= \n -> return $ toEnum n

toAnsiColor :: MyColor -> ANSI.Color
toAnsiColor Red = ANSI.Red
toAnsiColor Blue = ANSI.Blue
toAnsiColor Yellow = ANSI.Yellow
toAnsiColor Cyan = ANSI.Cyan

allColors :: [MyColor]
allColors = enumFrom $ toEnum 0

data MyMessage = MyMessage {
    myMsgNodeNumber :: NodeId
  , myMsgProcessNumber :: ProcessId
  , myMsgNumber :: Integer
  , myMsgColor :: MyColor
  } deriving (Show, Typeable)

instance Binary MyMessage where
  put (MyMessage nId pId n c) = put nId >> put pId >> put n >> put c
  get = do
        nId <- get
        pId <- get
        n <- get
        c <- get
        return $ MyMessage nId pId n c

printMessage :: MyMessage -> IO ()
printMessage (MyMessage nId pId n c)
  = do
    hFlush stdout
    ANSI.setSGR $ [ANSI.SetColor ANSI.Foreground ANSI.Dull (toAnsiColor c)]
    putStrLn $ (show nId) ++ " " ++ (show pId) ++ " " ++ (show n)
    ANSI.setSGR []

printSendingNotification :: MyColor -> IO ()
printSendingNotification c
  = do
    hFlush stdout
    ANSI.setSGR $ [ANSI.SetColor ANSI.Foreground ANSI.Dull (toAnsiColor c)]
    putStrLn $ "sending message..."
    ANSI.setSGR []

producer :: (ProcessId, MyColor) -> Process ()
producer (consumerId, c)
  = do
    liftIO $ putStrLn $ "start producing messages of color: " ++ (show c)
    link consumerId
    nId <- getSelfNode
    pId <- getSelfPid
    forever $ do
      t <- liftIO $ randomRIO (1,10)
      liftIO $ threadDelay $ t * 500000
      n <- liftIO $ randomRIO (0,100000)
      let myMsg = MyMessage nId pId n c
      liftIO $ printSendingNotification c
      send consumerId myMsg

remotable ['producer]

consumer :: Process ()
consumer
  = do
    liftIO $ putStrLn "start consuming"
    forever $ do
      myMsg <- expect
      liftIO $ printMessage myMsg

masterProcess :: [NodeId] -> Process ()
masterProcess nodes
  = do
    consumerId <- spawnLocal consumer
    let colorNodes = zip nodes (cycle $ allColors)
    forM_ colorNodes (\(nId,c) -> spawn nId ($(mkClosure 'producer) (consumerId, c)))
    _ <- liftIO $ getLine
    return ()
    

rtable :: RemoteTable
rtable = __remoteTable initRemoteTable

printUsage :: IO ()
printUsage = putStrLn "usage: (master|slave <port>)"

main :: IO ()
main
  = do
    args <- getArgs
    case args of
        ["master"] -> do
          backend <- initializeBackend "127.0.0.1" "9000" rtable
          startMaster backend masterProcess 
        ["slave",port] -> do
          backend <- initializeBackend "127.0.0.1" port rtable
          startSlave backend
        _ -> do
          printUsage
          exitFailure
