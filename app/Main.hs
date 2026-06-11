{-# LANGUAGE OverloadedStrings #-}

module Main where

import Network.Wai.Handler.Warp (defaultSettings, runSettings, setPort, setServerName)
import Server (serveStatic, withLogging)
import System.Directory (doesDirectoryExist)
import System.Environment (lookupEnv, getArgs)
import System.Exit (die)
import Text.Read (readMaybe)

main :: IO ()
main = do
    args <- getArgs
    let root = parseRoot args
    port <- parsePort
    -- Validate document root
    rootExists <- doesDirectoryExist root
    if not rootExists
      then die $ "Error: document root does not exist: " <> root
      else pure ()
    -- Reject "/" for security
    if root == "/"
      then die "Error: serving from / is forbidden for security reasons"
      else pure ()
    putStrLn $ "mini-httpd serving " <> root <> " on http://localhost:" <> show port
    let settings = setServerName "mini-httpd" $ setPort port defaultSettings
    runSettings settings (withLogging $ serveStatic root)

parseRoot :: [String] -> FilePath
parseRoot ("--root":r:_) = r
parseRoot _               = "public"

parsePort :: IO Int
parsePort = do
    mPort <- lookupEnv "PORT"
    case mPort >>= readMaybe of
      Just p | p > 0 && p <= 65535 -> pure p
      _                             -> pure 8080
