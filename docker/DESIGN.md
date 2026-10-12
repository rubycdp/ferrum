# Design

A small Go binary that runs as the entrypoint of a Docker container and gives each client its own Chrome over CDP.
It looks like browserless v2 (checked against v2.57.0) from the outside, but works differently inside. There's no Puppeteer, and nothing
touches the client's targets: bytes go through unchanged. It's self-hosted only (local machines, CI, your own
servers) and Docker only.

## Why

Most remote-Chrome bugs Ferrum and Cuprite users report come from browserless being too clever, not from CDP:

- Its own Puppeteer resets the viewport to 800x600 (ferrum#592, #492) and sets its own download folder (cuprite#279).
- It writes a raw `HTTP 408` onto a socket that is already a WebSocket when a limit is hit (ferrum#538).
- v2 kills sessions after 30s by default (ferrum#501).
- v2 reports `0.0.0.0` as the WebSocket host (ferrum#501) and leaves `User-Agent` out of `/json/version` (cuprite#300).
- `?token=` is lost on the way (ferrum#216, #439), and v2 needs a `/chrome` or `/chromium` path (ferrum#501).
- The startup window's context can't be addressed or disposed (ferrum#578, #540).
- `quit` doesn't end the session (ferrum#418), and orphaned Chrome trees pile up (ferrum#505).
- Zombie processes pile up when the main process is PID 1 (ferrum#364), and there's no native arm64 image (ferrum#270).

## Process model

- The container runs dumb-init as PID 1, then `driver`, then one Chrome per session. dumb-init reaps orphans,
  including crashpad's double-forked handler. That's why the driver isn't PID 1 itself: reaping everything there would race
  `exec.Cmd.Wait`.
- Each session gets its own Chrome with a fresh profile directory and `--remote-debugging-port=0`. The driver reads
  `DevTools listening on ws://…` from Chrome's stderr, so there are no port collisions and no startup polling.
- A session ends when the client's socket closes, which also covers `Browser.close`: Chrome exits, its socket
  closes, and the proxy sees EOF.
  - Both proxy directions are then torn down.
  - The whole process group gets TERM, then KILL after a grace period, and the profile directory is deleted.
  - Go's default TCP keepalive on accepted connections catches a client that vanished without closing.
- `CONCURRENT` limits running sessions and defaults to the number of CPUs. Up to `QUEUED` extra connections wait
  for a free slot. Beyond that they get `429` with `Retry-After`, as a plain HTTP response sent before the
  WebSocket upgrade, never bytes on a live socket. The names match browserless v2, so its compose files work
  unchanged.
- There's no session timeout by default; browserless v2 defaults to 30s. `TIMEOUT` (env) or `?timeout=` (query),
  both in milliseconds, set one. The driver logs why each session ended, so `docker logs` shows it.

## HTTP surface

The driver serves everything through `net/http`, and WebSocket upgrades go through `httputil.ReverseProxy`.

| Route | Behavior |
|---|---|
| `GET /json/version` | Starts the session's Chrome, proxies Chrome's real `/json/version`, and rewrites `webSocketDebuggerUrl` to `ws(s)://<Host>/devtools/browser/<id>?<original query>` |
| WS `/devtools/browser/<id>` | Attaches to the Chrome started by `/json/version`, `404` if there's none (as in v2) |
| WS `/`, `/chrome`, `/chromium` | Claims a pending Chrome started with the same query, or starts a new one. For `ws_url:` clients and browserless URLs |
| `GET /json/list`, `/json/new`, `/json/protocol`, `/devtools/*`, WS `/devtools/page/<id>` | Forwarded to the Chrome that owns the target, for the DevTools viewer (v2 has the same routes) |
| `GET /health` | Driver liveness. Never starts a Chrome |

Like v2, every route also accepts a trailing slash: `/chrome/` works like `/chrome`.

`/json/version` is answered on the fly, so the client gets real `Browser`, `User-Agent` and protocol data, with no
Chrome started at boot or just for discovery. This differs from v2 on purpose. v2 starts a throwaway Chrome once,
caches its metadata, and always returns its generic address (`EXTERNAL`, or `HOST:PORT`) with no path and no
query, so the client connects to `/`. Clients work against either. Details:

- **Unclaimed sessions.** A Chrome started by `/json/version` is pending until a WebSocket claims it. If none
  arrives within 30 seconds, for example from a stray `curl` or a misconfigured healthcheck, it's killed.
- **Reachable URL.** The URL is built from `Host` / `X-Forwarded-Host` / `X-Forwarded-Proto`, so it's always
  reachable from the client (no `0.0.0.0`), and the query string is kept. `EXTERNAL` (or `PROXY_URL`, as in v2)
  overrides the scheme and host when the driver sits behind a proxy that rewrites them.
- **Host header.** Requests forwarded to Chrome carry `Host: 127.0.0.1:<port>`, because Chrome rejects any other
  host on its HTTP endpoint.
- **DevTools URLs.** In the `devtoolsFrontendUrl` returned by `/json`, the `ws=` parameter is rewritten to the
  driver's host. Ferrum's `debug_url` and the browser's DevTools then give a live, clickable view of the session.
  That's our answer to browserless's debug viewer.

### Zero-copy tunnel (potential)

After the upgrade, `ReverseProxy` copies raw bytes between the two connections in userspace and never parses
frames. A possible optimization: `Hijack()` the client connection, dial Chrome, write the rewritten handshake,
then `io.Copy` between the two `*net.TCPConn`s. On Linux that uses `splice(2)`, so the bytes never enter
userspace. Bytes already buffered by `net/http` have to be flushed first, and both connections closed when either
copy ends. It's worth doing only if profiling shows the copy matters, since Chrome's JSON serialization dominates
CDP traffic.

## Launch options

The query string from `/json/version` or the WebSocket URL accepts the same parameters as browserless v2:

- `launch`: JSON or base64-encoded JSON, in v2's (Puppeteer launch) format. Supported keys:
  - `args`: extra Chrome flags, e.g. `--proxy-server=…` or `--lang=…`;
  - `headless`: `false` starts Chrome under Xvfb;
  - `defaultViewport` `{width, height}`: becomes `--window-size`;
  - `ignoreDefaultArgs`: `true`, or a list of default flags to drop.
- `timeout`: the session timeout in milliseconds.

Other parameters (`token`, `blockAds`, `blockAdsInclude`) and other `launch` keys are ignored, so existing
browserless URLs keep working.

Anyone who can connect can pass flags like `--renderer-cmd-prefix` and run commands in the container. There's no
authentication, so never publish the port beyond localhost or a private network.

Default flags:

- headless;
- `--no-startup-window`, so no implicit context;
- `--no-sandbox`, since the container is the boundary;
- `--disable-dev-shm-usage`;
- `--disable-features=site-per-process`, which makes ferrum#640 less likely.

Never added: `--disable-web-security`, `--disable-crashpad-for-testing` (the network service crash-loops), or
`NetworkServiceInProcess`.

## Files

There's no file API. Mount directories at the same absolute path on the host or app container and in the driver
container. Ferrum passes its own paths to `Browser.setDownloadBehavior` and `DOM.setFileInputFiles`, and Chrome
resolves them inside the container:

- uploads: the app source, e.g. `-v $PWD:$PWD`;
- downloads: e.g. `./tmp/downloads` mounted at the same path.

Screenshots and PDFs need no mount: they come back over CDP and Ruby writes the file.

The image works under `--user $(id -u):$(id -g)`: any uid, a world-writable `HOME` with the XDG directories
under it, which crashpad needs (ferrum#541, #544). Downloads then belong to the user, and Chrome can write into the mounted folder.

## Image

- `debian:trixie-slim`, never Alpine (Chromium on musl aborts at startup, ferrum#571). Not Ubuntu either, because
  Ubuntu's `chromium` package is a snap, which doesn't work in Docker.
- Two images, `ghcr.io/rubycdp/chrome` (Google's `.deb`) and `ghcr.io/rubycdp/chromium` (Debian's package), each
  for amd64 and arm64. Tags: `latest`, the browser's major version (`155`) and its full version (`155.0.8059.39`).
- The Go binary is cross-compiled in a build stage, so the image has no Node, Playwright or npm.
- `.github/workflows/docker.yml` builds each browser and architecture pair on a native runner, never through
  QEMU, which crashes Chrome (ferrum#270). It smoke-tests every image and merges the architectures into one
  multi-arch tag by digest.
- Fonts: Debian's font packages plus open substitutes for Microsoft fonts. Selawik replaces Segoe UI, Carlito
  replaces Calibri, Caladea replaces Cambria, and DejaVu replaces Tahoma.
- Later: the Ferrum suite run against each image before it's published.
- Env, with names matching browserless v2:
  - `PORT` (default 3000) and `HOST` (default `0.0.0.0`);
  - `CONCURRENT`, `QUEUED` and `TIMEOUT`;
  - `EXTERNAL` / `PROXY_URL`;
  - plus `BROWSER_PATH`, which the image sets.
- A healthcheck on `/health`, so compose can use `condition: service_healthy`.

## Usage with Cuprite in compose

This follows the Evil Martians "System of a test" setup:

- **The `chrome` service.** Use this image instead of `browserless/chrome`. `CONNECTION_TIMEOUT` and the
  M1-specific tag aren't needed, and `depends_on` can use `service_healthy`.
- **Connecting.** `url: ENV["CHROME_URL"]` (`http://chrome:3333`) works as is: one `/json/version`, then the
  WebSocket. The TCP availability check with fallback to a local Chrome also works as is.
- **Sessions.** Cuprite opens one connection per test process and calls `reset` between tests, so it's one Chrome
  per process. Parallel workers each get their own, so set `CONCURRENT` to at least the worker count.
- **The app's address.** `Capybara.server_host = "0.0.0.0"`, with `app_host` set to the app's hostname on the
  compose network. When Rails runs on the host instead, use `host.docker.internal`, which needs
  `extra_hosts: ["host.docker.internal:host-gateway"]` on Linux.
- **WebMock and VCR.** Allow the `chrome` host, because `/json/version` goes through `Net::HTTP`.
- **Launch flags.** `browser_options: {"no-sandbox" => nil}` isn't needed. Ferrum doesn't send launch flags to a
  remote browser anyway.
- **GitHub Actions.** Service containers start before checkout, so start the driver with `docker run` in a step
  after checkout when uploads need the workspace mounted.

## Ferrum changes

1. Apply `window_size` to each page in remote mode. Today it only feeds the local `--window-size` flag, so a
   remote browser silently ignores it.
2. `Browser#debug` in remote mode prints the DevTools URL instead of `Process.spawn(process.path, …)`, which
   fails because the path is nil.
3. Never look for a local binary when `url` or `ws_url` is set (ferrum#554).
4. Optionally, send `window_size` and `browser_options` in v2's `launch` query parameter (`defaultViewport` and
   `args`) when connecting remotely.

## Status

Done:
- Config is `BROWSER_PATH`, `HOST` and `PORT`.
- One Chrome per connection, on `--remote-debugging-port=0`, with the endpoint read from stderr.
- `/json/version` is answered on the fly, with a claim timeout.
- The WebSocket goes through `ReverseProxy`.
- The process group gets TERM, then KILL, and the profile is removed when the connection ends.
- `/health`.
- A graceful shutdown stops every Chrome.
- Trailing-slash routes (`/chrome/`, `/chromium/`, `/json/version/`), as in v2.

With `ws_url:`, Ferrum still calls `/json/version` before connecting to `/`. Pending Chromes are therefore matched
by query string, so a connection to `/` claims the one that call started, instead of starting a second.

Not done yet:
- `CONCURRENT`, `QUEUED` and `TIMEOUT`, plus `EXTERNAL`;
- the `launch` and `timeout` query parameters;
- the DevTools proxy (`/json/list`, `/json/new`, `/json/protocol`, `/devtools/*`);
- cleaned-up default flags;
- a `HEALTHCHECK` in the image;
- Go tests.
