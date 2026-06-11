{-# LANGUAGE OverloadedStrings #-}

module Server (serveStatic, withLogging) where

import Network.Wai
import Network.HTTP.Types
import System.FilePath ((</>), takeDirectory, takeFileName, takeExtension)
import System.Directory (canonicalizePath, makeAbsolute, doesFileExist, doesDirectoryExist)
import Control.Exception (try, IOException, throwIO)
import System.IO.Error (isDoesNotExistError)
import Data.List (isPrefixOf)
import Data.Text (Text, intercalate, unpack)
import qualified Data.Text as T
import Network.Mime (defaultMimeLookup)
import qualified Data.ByteString.Lazy as BL
import System.IO (hPutStrLn, stderr)

-- | Log each request: method path status after the response is sent.
withLogging :: Middleware
withLogging app req respond =
    app req $ \res -> do
        hPutStrLn stderr $ show (requestMethod req)
            ++ " " ++ show (rawPathInfo req)
            ++ " " ++ show (responseStatus res)
        respond res

-- | Create a WAI Application that serves static files from the given
-- document root. Only GET and HEAD are allowed. Path-traversal attacks
-- are prevented by canonicalizing paths and verifying they stay within
-- the document root.
serveStatic :: FilePath -> Application
serveStatic root req respond =
    case requestMethod req of
      m | m == methodGet  -> serveFile root False req respond
        | m == methodHead -> serveFile root True  req respond
      _ -> respond $ responseLBS status405
                        (secHeaders [(hContentType, "text/plain; charset=utf-8")])
                        "Method Not Allowed"

-- | Resolve the request path against the document root, apply security
-- checks, and serve the file if safe and it exists.
serveFile :: FilePath -> Bool -> Application
serveFile root isHead req respond = do
    let reqPath = pathToFile (pathInfo req)
    mSafe <- resolveSafe root reqPath
    case mSafe of
      Nothing ->
          respond $ responseLBS status404 (secHeaders []) "Not Found"
      Just filePath -> do
          exists <- doesFileExist filePath
          if exists
            then do
                let mimeExt = T.pack $ takeExtension filePath
                let mimeCt  = defaultMimeLookup mimeExt
                let headers = secHeaders [(hContentType, mimeCt)]
                if isHead
                  then respond $ responseLBS status200 headers BL.empty
                  else do
                    content <- BL.readFile filePath
                    respond $ responseLBS status200 headers content
            else respond $ responseLBS status404 (secHeaders []) "Not Found"

-- | Decode WAI's pathInfo (already %-decoded segments) back into a
-- relative file path. Returns "/index.html" for root.
pathToFile :: [Text] -> FilePath
pathToFile [] = "/index.html"
pathToFile segs = "/" ++ unpack (intercalate "/" segs)

-- | Add security-related response headers
secHeaders :: ResponseHeaders -> ResponseHeaders
secHeaders hs = hs ++
    [ ("X-Content-Type-Options", "nosniff")
    , ("X-Frame-Options", "DENY")
    ]

-- | Resolve reqPath (starting with /) against the document root.
-- Returns Nothing if the resolved path escapes the root (path traversal)
-- or if the document root no longer exists.
resolveSafe :: FilePath -> FilePath -> IO (Maybe FilePath)
resolveSafe root reqPath = do
    absRoot <- makeAbsolute root
    canRoot <- canonicalizePath absRoot
    -- Verify root still exists (TOCTOU mitigation)
    rootExists <- doesDirectoryExist canRoot
    if not rootExists
      then pure Nothing
      else do
        -- Ensure canRoot ends with '/' so prefix check doesn't match
        -- e.g. "/var/public" should NOT match "/var/public-extra/secret"
        let canRoot' = case canRoot of
              '/':_ | last canRoot /= '/' -> canRoot ++ "/"
              _                           -> canRoot
        if canRoot' == "/"
          then pure Nothing
          else do
            -- Drop leading '/' then join with root
            let relPath  = dropWhile (== '/') reqPath
            let fullPath = absRoot </> relPath
            absFull <- makeAbsolute fullPath
            -- Try canonicalizing the full path (works when file exists).
            -- If file doesn't exist, canonicalize the parent directory and
            -- reconstruct — still catching traversal via nonexistent paths.
            result <- try (canonicalizePath absFull) :: IO (Either IOException FilePath)
            case result of
              Right canPath
                  | canRoot' `isPrefixOf` canPath -> pure (Just canPath)
                  | otherwise                     -> pure Nothing
              Left e
                  | isDoesNotExistError e -> do
                      let parent = takeDirectory absFull
                          file   = takeFileName absFull
                      -- Guard: reject empty, ".", ".." filenames
                      if null file || file == "." || file == ".."
                        then pure Nothing
                        else do
                          resultParent <- try (canonicalizePath parent) :: IO (Either IOException FilePath)
                          case resultParent of
                            Right canParent -> do
                              let canRecon = canParent </> file
                              if canRoot' `isPrefixOf` canRecon
                                then pure (Just canRecon)
                                else pure Nothing
                            Left _ -> pure Nothing
                  | otherwise -> throwIO e
