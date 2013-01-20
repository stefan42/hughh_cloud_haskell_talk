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


instance Binary ANSI.Color where
  put c = put $ fromEnum c
  get = get >>= \n -> return $ toEnum n

data MyMessage = MyMessage {
    myMsgNodeNumber :: NodeId
  , myMsgProcessNumber :: ProcessId
  , myMsgNumber :: Integer
  , myMsgColor :: ANSI.Color
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
    ANSI.setSGR $ [ANSI.SetColor ANSI.Foreground ANSI.Dull c]
    putStrLn $ (show nId) ++ " " ++ (show pId) ++ " " ++ (show n)
    ANSI.setSGR []

producer :: ProcessId -> ANSI.Color -> Process ()
producer consumerId c
  = do
    liftIO $ putStrLn "start producing"
    nId <- getSelfNode
    pId <- getSelfPid
    forever $ do
      t <- liftIO $ randomRIO (1,10)
      liftIO $ threadDelay $ t * 500000
      n <- liftIO $ randomRIO (0,100000)
      let myMsg = MyMessage nId pId n c
      send consumerId myMsg

consumer :: Process ()
consumer
  = do
    liftIO $ putStrLn "start consuming"
    forever $ do
      myMsg <- expect
      liftIO $ printMessage myMsg

mainProcess :: Process ()
mainProcess
  = do
    consumerId <- spawnLocal consumer
    _ <- spawnLocal $ producer consumerId ANSI.Red
    _ <- spawnLocal $ producer consumerId ANSI.Magenta
    _ <- spawnLocal $ producer consumerId ANSI.Yellow
    _ <- spawnLocal $ producer consumerId ANSI.Cyan
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
