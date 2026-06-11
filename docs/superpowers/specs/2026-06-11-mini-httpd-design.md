# mini-httpd -- Design Spec

**Date:** 2026-06-11
**Status:** Approved

## Overview

A single-package Haskell (Cabal) project: a secure static file HTTP server. Serves a single `index.html` from a `public/` directory, with basic web security: path-traversal prevention, method whitelisting, and safe defaults via warp.

## Architecture

```
mini-httpd/
  public/
    index.html          # Default served file
  app/
    Main.hs             # Entry point: config, warp setup
  src/
    Server.hs           # WAI application + security logic
  mini-httpd.cabal
```

Two modules.

## Security Model

| Concern            | Mechanism                                                      |
| ------------------ | -------------------------------------------------------------- |
| Path traversal     | Canonicalize resolved path; verify it starts with serve-root   |
| Symlink escapes    | `canonicalizePath` resolves symlinks before prefix check        |
| Request method     | Only GET and HEAD allowed; 405 for all others                  |
| Document root guard| `doesDirectoryExist` check at startup; root `/` is rejected    |
| Resource limits    | Warp default settings (slowloris protection, timeouts, header limits) |
| Info disclosure    | No directory listings; traversal and missing-file both return 404 |
| Content sniffing   | Content-Type set from file extension via `mime-types`          |
| Server header      | `setServerName "mini-httpd"` suppresses warp version leak      |
| Security headers   | `X-Content-Type-Options: nosniff` and `X-Frame-Options: DENY`  |

## Data Flow

```
Client -> Warp (HTTP/TCP) -> WAI Application (Server.hs)
  |- Method check -> GET/HEAD only, else 405
  |- Path decode + canonicalize -> bad path -> 404 (no info leak)
  |- Prefix check -> outside root? -> 404 (don't leak existence)
  |- Read file -> success -> 200 + Content-Type + security headers
  |            +-> not found -> 404
  |- Request logging printed to stderr after response sent
  |- IOException discrimination: does-not-exist vs. real I/O errors
```

## Key Design Decisions

1. **warp + wai** rather than hand-rolled HTTP -- eliminates HTTP-parsing attack surface
2. **Custom static serving** rather than `wai-middleware-static` -- the middleware adds directory listings and index-file redirects we don't want; our version is tighter
3. **404 for out-of-root paths** -- don't distinguish "doesn't exist" from "not allowed" (no info leak)
4. **No directory listings** -- security by default
5. **Server header suppression** -- `setServerName` sets a custom server name instead of leaking the warp version string

## Dependencies

| Package            | Purpose                         |
| ------------------ | ------------------------------- |
| `warp`             | HTTP server (WAI)               |
| `wai`              | Application interface           |
| `http-types`       | Status codes, method constants  |
| `mime-types`       | Content-Type from extension     |
| `directory`        | `canonicalizePath` (bundled)    |
| `filepath`         | Path manipulation (bundled)     |

## Out of Scope

- Directory listings
- HTTPS / TLS
- File uploads / POST
- Config files
- CGI / reverse proxy
- Range requests
- Caching headers

## Interface

```
PORT=8080 mini-httpd          # env var, default 8080
mini-httpd --root ./public    # CLI flag, default ./public
```

Both optional -- zero-config for the happy path.
