# mini-httpd

A secure static-file HTTP server written in Haskell.

## Quick Start

```bash
cabal build
cabal run
curl http://localhost:8080/
```

The server starts on port 8080 and serves files from the `public/` directory.

## Usage

```
mini-httpd [--root <path>]
```

- `--root <path>` -- document root directory (default: `public/`).
- `PORT` environment variable -- override the listen port (default: `8080`).

Examples:

```bash
PORT=3000 cabal run                    # port 3000, default root
cabal run mini-httpd -- --root ./www   # custom root, default port
```

## Security Features

- **Method whitelist:** Only GET and HEAD are accepted; all other HTTP methods return 405.
- **Path traversal prevention:** Requested paths are canonicalized and verified to remain within the document root. Symlinks are resolved before the prefix check.
- **Security headers:** Responses include `X-Content-Type-Options: nosniff` and `X-Frame-Options: DENY`.
- **No directory listings:** The server never generates an index listing -- only explicitly present files are served.
- **Server header suppression:** The `Server` response header is set to `mini-httpd` via `setServerName` rather than leaking the warp version.

## Out of Scope

- Directory listings
- HTTPS / TLS
- File uploads / POST / PUT / DELETE
- Configuration files
- CGI / reverse proxy
- Range requests
- Caching headers
- Logging beyond stderr request logging

## Development

```bash
cabal test     # run the test suite
cabal build    # build all targets (check for warnings)
```

Requirements: GHC 9.4+, Cabal 3.10+, and a standard Haskell toolchain (GHCup recommended).

## License

MIT
