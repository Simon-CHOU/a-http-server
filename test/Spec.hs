{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Hspec
import Server (serveStatic, withLogging)
import Network.Wai hiding (Response, ResponseReceived)
import Network.Wai.Internal (Response(..), ResponseReceived(..))
import Network.HTTP.Types
import System.Directory (createDirectoryIfMissing, removeFile, removeDirectoryRecursive)
import System.FilePath ((</>))
import Control.Concurrent.MVar
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString as BS

main :: IO ()
main = hspec spec

-- | Call a WAI Application synchronously and return the Response
runApp :: Application -> Request -> IO Response
runApp app req = do
    mv <- newEmptyMVar
    _ <- app req $ \r -> putMVar mv r >> return ResponseReceived
    takeMVar mv

-- | Build a minimal GET request for a given path
mkGet :: BS.ByteString -> Request
mkGet path = defaultRequest
    { requestMethod = methodGet
    , rawPathInfo = path
    , pathInfo = decodePathSegments path
    }

mkPost :: BS.ByteString -> Request
mkPost path = defaultRequest
    { requestMethod = methodPost
    , rawPathInfo = path
    , pathInfo = decodePathSegments path
    }

mkHead :: BS.ByteString -> Request
mkHead path = defaultRequest
    { requestMethod = methodHead
    , rawPathInfo = path
    , pathInfo = decodePathSegments path
    }

mkPut :: BS.ByteString -> Request
mkPut path = defaultRequest
    { requestMethod = "PUT"
    , rawPathInfo = path
    , pathInfo = decodePathSegments path
    }

mkDelete :: BS.ByteString -> Request
mkDelete path = defaultRequest
    { requestMethod = "DELETE"
    , rawPathInfo = path
    , pathInfo = decodePathSegments path
    }

mkConnect :: BS.ByteString -> Request
mkConnect path = defaultRequest
    { requestMethod = "CONNECT"
    , rawPathInfo = path
    , pathInfo = decodePathSegments path
    }

mkOptions :: BS.ByteString -> Request
mkOptions path = defaultRequest
    { requestMethod = "OPTIONS"
    , rawPathInfo = path
    , pathInfo = decodePathSegments path
    }

-- | Response body as strict ByteString
responseBodyBS :: Response -> IO BS.ByteString
responseBodyBS (ResponseBuilder _ _ b) =
    pure $ BL.toStrict $ BB.toLazyByteString b
responseBodyBS (ResponseRaw _ _) = error "unexpected ResponseRaw"
responseBodyBS (ResponseFile _ _ _ _) = error "unexpected ResponseFile"
responseBodyBS (ResponseStream _ _ _) = error "unexpected ResponseStream"

-- Use beforeAll / after pattern
spec :: Spec
spec = before mkTestRoot $ after cleanupTestRoot $ do
    describe "mini-httpd" $ do
        it "serves index.html for GET /" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/")
            responseStatus resp `shouldBe` status200

        it "serves index.html for GET /index.html" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/index.html")
            responseStatus resp `shouldBe` status200

        it "returns 404 for missing file" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/nonexistent.html")
            responseStatus resp `shouldBe` status404

        it "sets Content-Type: text/html for .html files" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/")
            let hs = responseHeaders resp
            lookup "Content-Type" hs `shouldSatisfy`
                maybe False ("text/html" `BS.isInfixOf`)

        it "returns 200 for HEAD /" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkHead "/")
            responseStatus resp `shouldBe` status200

        it "HEAD response has empty body" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkHead "/")
            body <- responseBodyBS resp
            body `shouldBe` BS.empty

        it "HEAD 404 response has empty body" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkHead "/nonexistent.html")
            responseStatus resp `shouldBe` status404
            body <- responseBodyBS resp
            body `shouldBe` BS.empty

        it "rejects POST with 405" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkPost "/")
            responseStatus resp `shouldBe` status405

        it "405 response includes Allow header" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkPost "/")
            responseStatus resp `shouldBe` status405
            let hs = responseHeaders resp
            lookup "Allow" hs `shouldBe` Just "GET, HEAD"

        it "rejects PUT with 405" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkPut "/")
            responseStatus resp `shouldBe` status405

        it "rejects DELETE with 405" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkDelete "/")
            responseStatus resp `shouldBe` status405

        it "blocks path traversal via .." $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/../../../etc/passwd")
            responseStatus resp `shouldSatisfy` (`elem` [status404, status403])

        it "blocks %-encoded path traversal" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/..%2F..%2F..%2Fetc%2Fpasswd")
            responseStatus resp `shouldSatisfy` (`elem` [status404, status400])

        it "serves files from a subdirectory" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/subdir/page.html")
            responseStatus resp `shouldBe` status200

        it "sets X-Content-Type-Options: nosniff" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/")
            let hs = responseHeaders resp
            lookup "X-Content-Type-Options" hs `shouldBe` Just "nosniff"

        it "sets X-Frame-Options: DENY" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/")
            let hs = responseHeaders resp
            lookup "X-Frame-Options" hs `shouldBe` Just "DENY"

        it "includes Date header in response" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/")
            let hs = responseHeaders resp
            lookup "Date" hs `shouldSatisfy` (/= Nothing)

        it "logging middleware passes through all responses unchanged" $ \root -> do
            let app = withLogging $ serveStatic root
            resp <- runApp app (mkGet "/")
            responseStatus resp `shouldBe` status200
            resp2 <- runApp app (mkHead "/")
            responseStatus resp2 `shouldBe` status200

    describe "security hardening" $ do
        it "rejects CONNECT method with 405" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkConnect "/")
            responseStatus resp `shouldBe` status405

        it "rejects OPTIONS method with 405" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkOptions "/")
            responseStatus resp `shouldBe` status405

        it "handles path with dot segment /. gracefully" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/./index.html")
            responseStatus resp `shouldBe` status200

        it "handles path with double slash // gracefully" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "//index.html")
            responseStatus resp `shouldSatisfy` (`elem` [status200, status404])

        it "blocked path traversal returns 404 not 403 (no info leak)" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/../secret")
            responseStatus resp `shouldBe` status404

        it "returns Content-Type for .txt files" $ \root -> do
            let app = serveStatic root
            resp <- runApp app (mkGet "/test.txt")
            responseStatus resp `shouldBe` status200
            let hs = responseHeaders resp
            lookup "Content-Type" hs `shouldBe` Just "text/plain"

        it "empty path segments are handled" $ \root -> do
            let app = serveStatic root
            resp <- runApp app defaultRequest
            responseStatus resp `shouldBe` status200

        it "Very long path does not crash" $ \root -> do
            let app = serveStatic root
                longPath = BS.cons 47 (BS.replicate 500 97)
            resp <- runApp app (mkGet longPath)
            responseStatus resp `shouldSatisfy` (`elem` [status404, status200])

mkTestRoot :: IO FilePath
mkTestRoot = do
    -- Create a persistent temp directory
    let root = "/tmp/mini-httpd-test"
    createDirectoryIfMissing True root
    BL.writeFile (root </> "index.html") "<html><body>Hello</body></html>"
    let subdir = root </> "subdir"
    createDirectoryIfMissing True subdir
    BL.writeFile (subdir </> "page.html") "<html><body>Subpage</body></html>"
    BL.writeFile (root </> "test.txt") "plain text content\n"
    pure root

cleanupTestRoot :: FilePath -> IO ()
cleanupTestRoot root = do
    removeFile (root </> "index.html")
    removeFile (root </> "test.txt")
    removeFile (root </> "subdir/page.html")
    removeDirectoryRecursive (root </> "subdir")
    removeDirectoryRecursive root
