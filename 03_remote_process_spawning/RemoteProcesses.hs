{-# LANGUAGE OverloadedStrings, TemplateHaskell, DeriveDataTypeable #-}
module Main

where

import System.Exit
import System.Environment (getArgs)
import System.IO
import System.Random (randomRIO)
import qualified System.Console.ANSI as ANSI
import Control.Monad (forever)
import Control.Concurrent (threadDelay)
import Control.Distributed.Process
import Data.Typeable
import Data.Binary
import qualified Data.ByteString.Char8 as BS

import Network.Transport (EndPointAddress(..))
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Control.Distributed.Process.Internal.Types (NodeId(..))
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node

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
    nId <- getSelfNode
    pId <- getSelfPid
    forever $ do
      t <- liftIO $ randomRIO (1,10)
      liftIO $ threadDelay $ t * 500000
      n <- liftIO $ randomRIO (0,100000)
      let myMsg = MyMessage nId pId n c
      liftIO $ printSendingNotification c
      send consumerId myMsg

linkingProducer :: (ProcessId, MyColor) -> Process ()
linkingProducer (consumerId, c)
  = catch
      (do
        link consumerId
        producer (consumerId,c)
      )
      (\e -> do liftIO $ putStrLn $ show (e::ProcessLinkException))

remotable ['producer,'linkingProducer]

consumer :: Process ()
consumer
  = do
    liftIO $ putStrLn "start consuming"
    forever $ do
      myMsg <- expect
      liftIO $ printMessage myMsg

masterProcess :: [(String, String)] -> Process ()
masterProcess clients
  = do
    consumerId <- spawnLocal consumer
    let clientNodeIds = map (\(h,p) -> makeNodeId h p) clients
        clientNodeId1 = clientNodeIds !! 0
        clientNodeId2 = clientNodeIds !! 1
    _ <- spawn clientNodeId1 ($(mkClosure 'producer) (consumerId, Red))
    _ <- spawn clientNodeId1 ($(mkClosure 'producer) (consumerId, Blue))
    _ <- spawn clientNodeId2 ($(mkClosure 'linkingProducer) (consumerId, Yellow))
    _ <- spawn clientNodeId2 ($(mkClosure 'linkingProducer) (consumerId, Cyan))
    return ()

slaveProcess :: Process ()
slaveProcess
  = do
    myNodeId <- getSelfNode
    liftIO $ putStrLn $ show myNodeId

startLocalNode :: String -> String -> RemoteTable -> Process () -> IO ()
startLocalNode host port remoteTable initialProcess
  = do
    mbTransport <- createTransport host port defaultTCPParameters
    case mbTransport of
      (Left e) -> error $ show e
      (Right transport) -> do
        localnode <- newLocalNode transport remoteTable
        runProcess localnode initialProcess

-- | Make a NodeId from "host" and "port".
makeNodeId :: String -> String -> NodeId
makeNodeId host port = NodeId . EndPointAddress . BS.pack $ host ++ ":" ++ port ++ ":0"

serverRemoteTable :: RemoteTable
serverRemoteTable = initRemoteTable

clientRemoteTable :: RemoteTable
clientRemoteTable = __remoteTable initRemoteTable

printUsage :: IO ()
printUsage = putStrLn "usage: (master|slave1|slave2)"

main :: IO ()
main
  = do
    args <- getArgs
    case args of
        ["master"] -> do
          startLocalNode "127.0.0.1" "9000" clientRemoteTable $ masterProcess 
            [("127.0.0.1","9001"),("127.0.0.1","9002")]
        ["slave1"] -> do
          startLocalNode "127.0.0.1" "9001" clientRemoteTable slaveProcess
        ["slave2"] -> do
          startLocalNode "127.0.0.1" "9002" clientRemoteTable slaveProcess
        _ -> do
          printUsage
          exitFailure
    putStrLn "start"
    _ <- getLine
    putStrLn "end"
