{-# LANGUAGE DeriveDataTypeable #-}
module Main

where

import System.IO
import System.Random (randomRIO)
import qualified System.Console.ANSI as ANSI
import Control.Monad (forever)
import Control.Concurrent (threadDelay)
import Control.Distributed.Process
import Data.Typeable
import Data.Binary

import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Control.Distributed.Process.Node

-- Blue Message ---------------------------------
data BlueMessage = BlueMessage {
    blueMsgNodeNumber :: NodeId
  , blueMsgProcessNumber :: ProcessId
  , blueMsgNumber :: Integer
  } deriving (Show, Typeable)

instance Binary BlueMessage where
  put (BlueMessage nId pId n) = put nId >> put pId >> put n
  get = do
        nId <- get
        pId <- get
        n <- get
        return $ BlueMessage nId pId n

printBlueMessage :: BlueMessage -> IO ()
printBlueMessage (BlueMessage nId pId n)
  = do
    hFlush stdout
    ANSI.setSGR $ [ANSI.SetColor ANSI.Foreground ANSI.Dull ANSI.Blue]
    putStrLn $ (show nId) ++ " " ++ (show pId) ++ " " ++ (show n)
    ANSI.setSGR []


-- Red Message ---------------------------------
data RedMessage = RedMessage {
    redMsgNodeNumber :: NodeId
  , redMsgProcessNumber :: ProcessId
  , redMsgNumber :: Integer
  } deriving (Show, Typeable)

instance Binary RedMessage where
  put (RedMessage nId pId n) = put nId >> put pId >> put n
  get = do
        nId <- get
        pId <- get
        n <- get
        return $ RedMessage nId pId n

printRedMessage :: RedMessage -> IO ()
printRedMessage (RedMessage nId pId n)
  = do
    hFlush stdout
    ANSI.setSGR $ [ANSI.SetColor ANSI.Foreground ANSI.Dull ANSI.Red]
    putStrLn $ (show nId) ++ " " ++ (show pId) ++ " " ++ (show n)
    ANSI.setSGR []

produceBlue :: ProcessId -> Process ()
produceBlue consumerId
  = do
    liftIO $ putStrLn "start producing blue messages"
    nId <- getSelfNode
    pId <- getSelfPid
    forever $ do
      t <- liftIO $ randomRIO (1,10)
      liftIO $ threadDelay $ t * 500000
      n <- liftIO $ randomRIO (0,100000)
      let myMsg = BlueMessage nId pId n
      send consumerId myMsg

produceRed :: ProcessId -> Process ()
produceRed consumerId
  = do
    liftIO $ putStrLn "start producing red messages"
    nId <- getSelfNode
    pId <- getSelfPid
    forever $ do
      t <- liftIO $ randomRIO (1,10)
      liftIO $ threadDelay $ t * 500000
      n <- liftIO $ randomRIO (0,100000)
      let myMsg = RedMessage nId pId n
      send consumerId myMsg


produceBogusMessages :: ProcessId -> Process ()
produceBogusMessages consumerId
  = do
    liftIO $ putStrLn "start producing red messages"
    nId <- getSelfNode
    pId <- getSelfPid
    forever $ do
      t <- liftIO $ randomRIO (1,10)
      liftIO $ threadDelay $ t * 500000
      send consumerId "Just a nice string message"

consumeRedOnly :: Process ()
consumeRedOnly
  = do
    liftIO $ putStrLn "start consuming red"
    forever $ do
      myMsg <- expect
      liftIO $ printRedMessage myMsg


consumeBoth :: Process ()
consumeBoth
  = do
    liftIO $ putStrLn "start consuming both colors"
    forever $ do
      receiveWait
        [ 
          match $ \msg -> liftIO $ printBlueMessage msg
        , match $ \msg -> liftIO $ printRedMessage msg
        , matchUnknown $ liftIO $ putStrLn "unkown message"
        ]



mainProcess :: Process ()
mainProcess
  = do
    -- consumerId <- spawnLocal consumeRedOnly
    consumerId <- spawnLocal consumeBoth
    _ <- spawnLocal $ produceBlue consumerId
    _ <- spawnLocal $ produceRed consumerId
    _ <- spawnLocal $ produceBogusMessages consumerId
    return ()

startLocalNode :: String -> String -> Process () -> IO ()
startLocalNode host port initialProcess
  = do
    mbTransport <- createTransport host port defaultTCPParameters
    case mbTransport of
      (Left e) -> error $ show e
      (Right transport) -> do
        localnode <- newLocalNode transport initRemoteTable
        runProcess localnode initialProcess

main :: IO ()
main
  = do
    putStrLn "start"
    startLocalNode "localhost" "9000" mainProcess
    _ <- getLine
    putStrLn "end"
