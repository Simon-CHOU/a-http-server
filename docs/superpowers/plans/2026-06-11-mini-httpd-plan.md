# mini-httpd Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a secure static-file HTTP server in Haskell that hosts `index.html` with path-traversal prevention.

**Architecture:** Two-module Cabal project: `Server.hs` (WAI application with security logic) and `Main.hs` (warp runner, CLI/env config). Tests use `hspec` to call the WAI Application directly.

**Tech Stack:** GHC, Cabal, warp, wai, http-types, mime-types, hspec (test only)

---

## File Map

| File | Responsibility |
|------|---------------|
| `mini-httpd.cabal` | Package metadata, dependencies, build targets |
| `src/Server.hs` | `serveStatic :: FilePath -> Application` — security checks + static file serving |
| `src/Main.hs` | CLI arg parsing, PORT env var, warp `run` |
| `public/index.html` | Default page to serve |
| `test/Spec.hs` | hspec tests: happy path, 405, path traversal, 404 |
| `cabal.project` | Optional, pins package set (may not need) |

---

### Task 1: Install Haskell Tooling

**Files:**
- None (system install)

- [ ] **Step 1: Install GHC and Cabal via GHCup**

```bash
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_INSTALL_NO_STACK=1 sh
```

Then add to PATH:

```bash
source ~/.ghcup/env
```

- [ ] **Step 2: Verify installation**

```bash
ghc --version
cabal --version
```

Expected: GHC >= 9.4, Cabal >= 3.10

- [ ] **Step 3: Update Cabal package list**

```bash
cabal update
```

---

### Task 2: Create Project Scaffold

**Files:**
- Create: `mini-httpd.cabal`
- Create: `src/Server.hs` (stub)
- Create: `src/Main.hs` (stub)
- Create: `test/Spec.hs` (stub)
- Create: `public/index.html` (placeholder)

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p src test public
```

- [ ] **Step 2: Write `mini-httpd.cabal`**

```cabal
cabal-version: 3.0
name:           mini-httpd
version:        0.1.0.0
synopsis:       A secure mini HTTP server for static files
license:        MIT
author:         simon
build-type:     Simple

common warnings
    ghc-options: -Wall -Wcompat -Widentities -Wincomplete-uni-patterns
                 -Wmissing-export-lists -Wpartial-fields -Wredundant-constraints

executable mini-httpd
    import:           warnings
    main-is:          Main.hs
    hs-source-dirs:   src
    other-modules:    Server
    build-depends:
        base        >=4.14 && <5,
        warp        >=3.3  && <4,
        wai         >=3.2  && <4,
        http-types  >=0.12 && <0.13,
        mime-types  >=0.1  && <0.2,
        directory   >=1.3  && <2,
        filepath    >=1.4  && <2,
        bytestring  >=0.10 && <0.13
    default-language: Haskell2010

test-suite mini-httpd-test
    import:           warnings
    type:             exitcode-stdio-1.0
    main-is:          Spec.hs
    hs-source-dirs:   test
    build-depends:
        base,
        mini-httpd,
        hspec        >=2.10 && <3,
        wai          >=3.2  && <4,
        wai-extra    >=3.1  && <4,
        http-types,
        bytestring,
        directory,
        filepath
    default-language: Haskell2010
```

- [ ] **Step 3: Write stub `src/Server.hs`**

```haskell
module Server (serveStatic) where

import Network.Wai

serveStatic :: FilePath -> Application
serveStatic _ _ respond = respond $ responseLBS status200 [] "stub"
```

- [ ] **Step 4: Write stub `src/Main.hs`**

```haskell
module Main where

main :: IO ()
main = putStrLn "mini-httpd — not yet implemented"
```

- [ ] **Step 5: Write placeholder `public/index.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>mini-httpd</title></head>
<body><h1>mini-httpd is running</h1></body>
</html>
```

- [ ] **Step 6: Verify the scaffold builds**

```bash
cabal build
```

Expected: Successful build (no-op stub).

---

### Task 3: Write Server Tests

**Files:**
- Create: `test/Spec.hs`

- [ ] **Step 1: Write the complete test file**

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Test.Hspec
import Server (serveStatic)
import Network.Wai
import Network.HTTP.Types
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.IO.Temp (withSystemTempDirectory)
import System.FilePath ((</>))
import Data.IORef
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString as BS

main :: IO ()
main = hspec spec

-- | Call a WAI Application synchronously and return the Response
runApp :: Application -> Request -> IO Response
runApp app req = do
    ref <- newIORef (error "Application did not respond")
    app req $ \r -> do
        writeIORef ref r
    readIORef ref

-- | Build a minimal GET request for a given path
mkGet :: BS.ByteString -> Request
mkGet path = defaultRequest
    { requestMethod = methodGet
    , rawPathInfo = path
    }

mkPost :: BS.ByteString -> Request
mkPost path = defaultRequest
    { requestMethod = methodPost
    , rawPathInfo = path
    }

mkHead :: BS.ByteString -> Request
mkHead path = defaultRequest
    { requestMethod = methodHead
    , rawPathInfo = path
    }

-- | Response body as strict ByteString
responseBodyBS :: Response -> IO BS.ByteString
responseBodyBS (ResponseBuilder _ _ b) =
    pure $ BL.toStrict $ BB.toLazyByteString b
responseBodyBS (ResponseRaw _ _) = error "unexpected ResponseRaw"
responseBodyBS (ResponseFile _ _ _ _) = error "unexpected ResponseFile"
responseBodyBS (ResponseStream _ _ _) = error "unexpected ResponseStream"

spec :: Spec
spec = around withTempDir $ \root -> do
    let app = serveStatic root

    describe "serveStatic — happy path" $ do
        it "serves index.html for GET /" $ do
            resp <- runApp app (mkGet "/")
            responseStatus resp `shouldBe` status200

        it "serves index.html for GET /index.html" $ do
            resp <- runApp app (mkGet "/index.html")
            responseStatus resp `shouldBe` status200

        it "returns 404 for missing file" $ do
            resp <- runApp app (mkGet "/nonexistent.html")
            responseStatus resp `shouldBe` status404

        it "sets Content-Type: text/html for .html files" $ do
            resp <- runApp app (mkGet "/")
            let hs = responseHeaders resp
            lookup "Content-Type" hs `shouldSatisfy`
                maybe False ("text/html" `BS.isInfixOf`)

    describe "serveStatic — HEAD requests" $ do
        it "returns 200 for HEAD /" $ do
            resp <- runApp app (mkHead "/")
            responseStatus resp `shouldBe` status200

        it "HEAD response has empty body" $ do
            resp <- runApp app (mkHead "/")
            body <- responseBodyBS resp
            body `shouldBe` BS.empty

    describe "serveStatic — security" $ do
        it "rejects POST with 405" $ do
            resp <- runApp app (mkPost "/")
            responseStatus resp `shouldBe` status405

        it "rejects PUT with 405" $ do
            resp <- runApp app (defaultRequest
                { requestMethod = "PUT"
                , rawPathInfo = "/"
                })
            responseStatus resp `shouldBe` status405

        it "rejects DELETE with 405" $ do
            resp <- runApp app (defaultRequest
                { requestMethod = "DELETE"
                , rawPathInfo = "/"
                })
            responseStatus resp `shouldBe` status405

        it "blocks path traversal via .." $ do
            resp <- runApp app (mkGet "/../../../etc/passwd")
            responseStatus resp `shouldSatisfy` (`elem` [status404])

        it "blocks symlink-escapes via resolved path" $ do
            resp <- runApp app (mkGet "/..%2F..%2F..%2Fetc%2Fpasswd")
            responseStatus resp `shouldSatisfy` (`elem` [status404, status400])

    describe "serveStatic — document root" $ do
        it "serves files from a subdirectory" $ do
            resp <- runApp app (mkGet "/subdir/page.html")
            -- This file doesn't exist in our temp dir, so 404
            responseStatus resp `shouldBe` status404

withTempDir :: (FilePath -> IO ()) -> IO ()
withTempDir action =
    withSystemTempDirectory "mini-httpd-test" $ \root -> do
        BL.writeFile (root </> "index.html") "<html><body>Hello</body></html>"
        let subdir = root </> "subdir"
        createDirectoryIfMissing True subdir
        BL.writeFile (subdir </> "page.html") "<html><body>Subpage</body></html>"
        action root
```

- [ ] **Step 2: Verify tests fail (Server.hs is still a stub)**

```bash
cabal test
```

Expected: Test failure — stub returns 200 for everything, so tests expecting 404/405 will fail.

---

### Task 4: Implement Server.hs

**Files:**
- Modify: `src/Server.hs`

- [ ] **Step 1: Write `src/Server.hs` with full security logic**

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Server (serveStatic) where

import Network.Wai
import Network.HTTP.Types
import Network.HTTP.Types.Header (hContentType)
import System.FilePath ((</>), takeDirectory, takeFileName)
import System.Directory (canonicalizePath, makeAbsolute, doesFileExist)
import Control.Exception (try, IOException)
import Data.List (isPrefixOf)
import Data.Text (Text, intercalate, unpack, null)
import Data.MimeTypes (mimeByExt, mimeTypeBS)
import qualified Data.ByteString.Lazy as BL

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
                        [(hContentType, "text/plain; charset=utf-8")]
                        "Method Not Allowed"

-- | Resolve the request path against the document root, apply security
-- checks, and serve the file if safe and it exists.
serveFile :: FilePath -> Bool -> Application
serveFile root isHead req respond = do
    let reqPath = decodePath (pathInfo req)
    mSafe <- resolveSafe root reqPath
    case mSafe of
      Nothing ->
          respond $ responseLBS status404 [] "Not Found"
      Just filePath -> do
          exists <- doesFileExist filePath
          if exists
            then do
                content <- BL.readFile filePath
                let ct     = mimeByExt filePath
                let headers = [(hContentType, mimeTypeBS ct)]
                let body   = if isHead then BL.empty else content
                respond $ responseLBS status200 headers body
            else respond $ responseLBS status404 [] "Not Found"

-- | Decode WAI's pathInfo (already %-decoded segments) back into a
-- relative file path. Returns "/" for root, "/index.html" if empty.
decodePath :: [Text] -> FilePath
decodePath [] = "/index.html"
decodePath segs = "/" ++ unpack (intercalate "/" segs)

-- | Resolve reqPath (starting with /) against the document root.
-- Returns Nothing if the resolved path escapes the root (path traversal).
resolveSafe :: FilePath -> FilePath -> IO (Maybe FilePath)
resolveSafe root reqPath = do
    absRoot <- makeAbsolute root
    canRoot <- canonicalizePath absRoot
    -- Ensure canRoot ends with '/' so prefix check doesn't match
    -- e.g. "/var/public" should NOT match "/var/public-extra/secret"
    let canRoot' = case canRoot of
          '/':_ | last canRoot /= '/' -> canRoot ++ "/"
          _                           -> canRoot
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
          | canRoot' `isPrefixOf` canPath -> pure (Just absFull)
          | otherwise                     -> pure Nothing
      Left _ -> do
          let parent = takeDirectory absFull
              file   = takeFileName absFull
          -- Guard: reject empty, ".", ".." filenames
          if null file || file == "." || file == ".."
            then pure Nothing
            else do
              canParent <- canonicalizePath parent
              let canRecon = canParent </> file
              if canRoot' `isPrefixOf` canRecon
                then pure (Just absFull)
                else pure Nothing
```

- [ ] **Step 2: Run tests after implementation**

```bash
cabal test
```

Expected: All tests pass.

---

### Task 5: Implement Main.hs

**Files:**
- Modify: `src/Main.hs`

- [ ] **Step 1: Write `src/Main.hs`**

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Network.Wai.Handler.Warp (run, setPort, defaultSettings)
import Server (serveStatic)
import System.Environment (lookupEnv, getArgs)
import System.Exit (die)
import Text.Read (readMaybe)

main :: IO ()
main = do
    args <- getArgs
    let root = parseRoot args
    port <- parsePort
    putStrLn $ "mini-httpd serving " <> root <> " on http://localhost:" <> show port
    run port (serveStatic root)

parseRoot :: [String] -> FilePath
parseRoot ("--root":r:_) = r
parseRoot _               = "public"

parsePort :: IO Int
parsePort = do
    mPort <- lookupEnv "PORT"
    case mPort >>= readMaybe of
      Just p | p > 0 && p <= 65535 -> pure p
      _                             -> pure 8080
```

- [ ] **Step 2: Verify the executable builds**

```bash
cabal build
```

Expected: Successful build of `mini-httpd` executable.

---

### Task 6: End-to-End Verification

**Files:**
- Verify: `public/index.html` (already created in Task 2)

- [ ] **Step 1: Start the server in the background**

```bash
cabal run mini-httpd &
SERVER_PID=$!
sleep 2
```

- [ ] **Step 2: Test GET / returns 200 with HTML**

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
```

Expected: `200`

- [ ] **Step 3: Test Content-Type is text/html**

```bash
curl -s -I http://localhost:8080/ | grep -i "content-type"
```

Expected: `content-type: text/html` (or `text/html; charset=...`)

- [ ] **Step 4: Test POST returns 405**

```bash
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/
```

Expected: `405`

- [ ] **Step 5: Test path traversal returns 404**

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/../../../etc/passwd
```

Expected: `404`

- [ ] **Step 6: Test HEAD returns 200 with no body**

```bash
curl -s -I http://localhost:8080/ | head -1
```

Expected: `HTTP/1.1 200 OK` and the full response has no body.

- [ ] **Step 7: Stop the server**

```bash
kill $SERVER_PID
```

---

### Task 7: Run Tests One Final Time

- [ ] **Step 1: Run full test suite**

```bash
cabal test
```

Expected: All tests pass, clean exit.

- [ ] **Step 2: Check GHC warnings are clean**

```bash
cabal build 2>&1 | grep -i "warning"
```

Expected: No output (no warnings).
