# Design

> Better than browserless, not equal to it.

A small Go binary that runs as the entrypoint of a Docker container and gives each client its own Chrome over CDP.
It replaces browserless with minimal changes: usually swap the image and connect. It doesn't copy
browserless, though: where browserless gets in the way, the driver does it differently. There's no Puppeteer,
and nothing touches the client's targets: bytes go through unchanged. It's self-hosted only (local machines, CI,
your own servers) at least for now.

## Why

Most remote-Chrome bugs Ferrum and Cuprite users report come from browserless being too clever, not from CDP:

- Its own Puppeteer resets the viewport to 800x600 (ferrum#592, #492) and sets its own download folder (cuprite#279).
- It writes a raw `HTTP 408` onto a socket that is already a WebSocket when a limit is hit (ferrum#538).
- v2 kills sessions after 30s by default (ferrum#501).
- v2 reports `0.0.0.0` as the WebSocket host (ferrum#501) and leaves `User-Agent` out of `/json/version` (cuprite#300).
- `?token=` is lost on the way (ferrum#216, #439), and v2 needs a `/chrome` or `/chromium` path (ferrum#501).
- The startup window's context can't be addressed or disposed (ferrum#578, #540). Ferrum adopts it as its default
  context, so `reset` can't clean it and cookies and storage leak from one test to the next. Ferrum won't fix this:
  the startup window belongs to whoever launched Chrome, and the driver launches with `--no-startup-window`.
- `quit` doesn't end the session (ferrum#418), and orphaned Chrome trees pile up (ferrum#505).
- Zombie processes pile up when the main process is PID 1 (ferrum#364), and there's no native arm64 image (ferrum#270).

## Compared to browserless v2

Moving from browserless usually means swapping the image and nothing else, but check the differences below.

### Shared conventions

Kept so moving over takes minimal changes:

- Port 3000, uid 999 and dumb-init.
- Env: `PORT`, `HOST`, `CONCURRENT`, `QUEUED`, `TIMEOUT` and `EXTERNAL` / `PROXY_URL`.
- Query: `launch` (Puppeteer's launch format, JSON or base64) and `timeout`.

### What's different

| | browserless v2 | driver |
|---|---|---|
| Runtime | A TypeScript app on Node, using Puppeteer and Playwright | One static Go binary |
| Base image | Ubuntu | `debian:trixie-slim` |
| Browser | Installed by Playwright's installer | Debian's `chromium` package or Google's `.deb` |
| Image size | About 3 GB, 1 GB compressed | About 1 GB, under 500 MB compressed |
| Architectures | `chromium`: amd64 and arm64; `chrome`: amd64 only | Both images on amd64 and arm64 |
| Client's targets | Its own Puppeteer connection sets the viewport and the download folder | Nothing besides the client talks to Chrome |
| Session timeout | 30s by default | None by default |
| `/json/version` | A Chrome started once at boot, with cached metadata and a generic URL without path or query | The session's own Chrome, real metadata, a URL the client can reach, with the query kept |
| `headless: false` | One shared Xvfb `:99` at 1024x768x16, started with the container | One Xvfb per session, sized to the window |
| PID 1 | A bash script; dumb-init runs only the Node process | dumb-init, reaping every orphan |
| `--user <uid>` | `HOME` belongs to `blessuser` | `HOME` is world-writable, any uid works |
| Default flags | Puppeteer's plus browserless's | Ferrum's |
| Auth | `TOKEN` | None, so never publish the port |

### What's left out

These are browserless features the driver doesn't have and won't add, because Ferrum and Cuprite drive Chrome
over CDP themselves and files go through bind mounts:

- the REST APIs (`/screenshot`, `/pdf`, `/content`, `/function`, `/download`, `/scrape`, `/performance`);
- the `/chrome` and `/chromium` paths: an image has one browser, so connect to `/`;
- Playwright endpoints, and Firefox, WebKit and Edge images;
- token auth, CORS, `ALLOW_GET` and `ALLOW_FILE_PROTOCOL`;
- the sessions, metrics, pressure and config endpoints, the debugger UI and the alert webhooks;
- ad blocking, stealth, recording, reconnecting to a kept-alive browser;
- the file workspace, `DATA_DIR` and `DOWNLOAD_DIR`.

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
- `CONCURRENT` limits running sessions and defaults to the number of CPUs. Up to `QUEUED` (default 10) extra connections wait
  for a free slot. Beyond that they get `429` with `Retry-After`, as a plain HTTP response sent before the
  WebSocket upgrade, never bytes on a live socket.
- There's no session timeout by default; browserless v2 defaults to 30s. `TIMEOUT` and `?timeout=`, both in milliseconds, set one. The driver logs why each session ended, so `docker logs` shows it.

## HTTP surface

The driver serves everything through `net/http`, and WebSocket upgrades go through `httputil.ReverseProxy`.

| Route | Behavior |
|---|---|
| `GET /json/version` | Starts the session's Chrome, proxies Chrome's real `/json/version`, and rewrites `webSocketDebuggerUrl` to `ws(s)://<Host>/devtools/browser/<id>?<original query>` |
| WS `/devtools/browser/<id>` | Attaches to the Chrome started by `/json/version`, or starts a new one if it's no longer pending |
| WS `/` | Starts a new Chrome. For `ws_url:` clients |
| `GET /json`, `/json/list` | Targets of every running session, with URLs pointing at the driver |
| `PUT /json/new?<url>` | Opens a target, only while exactly one session runs (`409` otherwise) |
| `GET /json/protocol` | Chrome's protocol description, cached. Starts a short-lived Chrome only when none runs |
| WS `/devtools/page/<id>` | Connects to one target of whichever session owns it. Closing it doesn't end the session |
| `GET /devtools/*` | The DevTools frontend, served by a running Chrome |
| `GET /` | A dashboard of running sessions and their pages, each linking to DevTools. Refreshes every 3 seconds |
| `GET /health` | Driver liveness. Never starts a Chrome |

Every route also accepts a trailing slash: `/json/version/` works like `/json/version`.

`/json/version` is answered on the fly, so the client gets real `Browser`, `User-Agent` and protocol data, with no
Chrome started at boot or just for discovery. browserless v2 instead starts a throwaway Chrome once, caches its
metadata, and always returns its generic address (`EXTERNAL`, or `HOST:PORT`) with no path and no query.
Details:

- **Unclaimed sessions.** A Chrome started by `/json/version` is pending until a WebSocket claims it by its id. If
  none arrives within 30 seconds, for example from a stray `curl` or a misconfigured healthcheck, it's killed, and
  a late connection to its id gets a new Chrome. Only `url:` clients go through `/json/version`; `ws_url:` connects
  to `/` directly.
- **Reachable URL.** The URL is built from `Host` / `X-Forwarded-Host` / `X-Forwarded-Proto`, so it's always
  reachable from the client (no `0.0.0.0`), and the query string is kept. `EXTERNAL` (or `PROXY_URL`)
  overrides the scheme and host when the driver sits behind a proxy that rewrites them.
- **Host header.** Requests forwarded to Chrome carry `Host: 127.0.0.1:<port>`, because Chrome rejects any other
  host on its HTTP endpoint.
- **DevTools URLs.** In the `devtoolsFrontendUrl` returned by `/json`, the `ws=` parameter is rewritten to the
  driver's host. The dashboard at `/` links each page to the DevTools frontend served by its Chrome, a live view
  of the running test. That's our answer to browserless's debug viewer.

### Zero-copy tunnel (potential)

After the upgrade, `ReverseProxy` copies raw bytes between the two connections in userspace and never parses
frames. A possible optimization: `Hijack()` the client connection, dial Chrome, write the rewritten handshake,
then `io.Copy` between the two `*net.TCPConn`s. On Linux that uses `splice(2)`, so the bytes never enter
userspace. Bytes already buffered by `net/http` have to be flushed first, and both connections closed when either
copy ends. It's worth doing only if profiling shows the copy matters, since Chrome's JSON serialization dominates
CDP traffic.

## Launch options

The query string from `/json/version` or the WebSocket URL accepts:

- `launch`: JSON or base64-encoded JSON, in Puppeteer's launch format. Supported keys:
  - `args`: extra Chrome flags, e.g. `--proxy-server=…` or `--accept-lang=…`. A flag with the same name as a
    default replaces it;
  - `defaultViewport` `{width, height}`: becomes `--window-size`;
  - `ignoreDefaultArgs`: `true`, or a list of default flags to drop, by full flag or by name;
  - `headless: false`: Chrome runs with a window on its own Xvfb display, sized to the window and stopped with
    the session. Without Xvfb in `PATH` (e.g. on a desktop), Chrome opens a real window.
- `timeout`: the session timeout in milliseconds, overriding `TIMEOUT`. `0` turns it off.

`--remote-debugging-port` and `--user-data-dir` are always set by the driver. An invalid `launch` gets `400`
before any Chrome starts. Other parameters and other `launch` keys are ignored. `driver --help` lists the launch options and default flags.

Anyone who can connect can pass flags like `--renderer-cmd-prefix` and run commands in the container. There's no
authentication, so never publish the port beyond localhost or a private network.

Default flags are Ferrum's, the same as `Ferrum::Browser.new(dockerize: true)` locally, window size included
(`driver --help` lists them). The one exception is `--remote-allow-origins`: the driver strips `Origin` instead.

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
  The driver's commit is in the `org.opencontainers.image.revision` label.
- The Go binary is cross-compiled in a build stage, so the image has no Node, Playwright or npm.
- `.github/workflows/docker.yml` runs the Go tests, then builds each browser and architecture pair on a native
  runner, never through QEMU, which crashes Chrome (ferrum#270).
  - It runs the Ferrum suite against every image, with `FERRUM_URL` pointing at the driver. Specs tagged
    `:launch`, which start their own Chrome, are skipped.
  - It merges the architectures into one multi-arch tag by digest. A failed build or suite publishes nothing, so
    `latest` stays where it was.
- Builds happen on driver changes pushed to `main` and on a daily check for new browser versions: Google's apt
  repository for Chrome, `apt-cache policy chromium` for Chromium. The check builds a browser only when its
  version isn't published yet.
- Only the current browser version gets builds. Older tags stay on GHCR as they were, with the driver of their
  time: Google and Debian only serve the newest packages, so an old version can't be rebuilt. Rebuilding the same
  version with a newer driver moves its tags; pin a digest to keep an exact image.
- Fonts: Debian's font packages plus open substitutes for Microsoft fonts. Selawik replaces Segoe UI, Carlito
  replaces Calibri, Caladea replaces Cambria, and DejaVu replaces Tahoma.
- Env:
  - `PORT` (default 3000) and `HOST` (default `0.0.0.0`);
  - `CONCURRENT`, `QUEUED` and `TIMEOUT`;
  - `EXTERNAL` / `PROXY_URL`;
  - plus `BROWSER_PATH`, which the image sets.
- A `HEALTHCHECK` on `/health` (it follows `PORT`), so compose can use `condition: service_healthy`.

## Usage with Cuprite in compose

This follows the Evil Martians "System of a test" setup:

- **The `chrome` service.** Use `ghcr.io/rubycdp/chrome` or `chromium`. One tag works on amd64 and arm64, and
  `depends_on` can use `service_healthy`.
- **Connecting.** `url: ENV["CHROME_URL"]` (`http://chrome:3333`) works as is: one `/json/version`, then the
  WebSocket. The TCP availability check with fallback to a local Chrome also works as is.
- **Sessions.** Cuprite opens one connection per test process and calls `reset` between tests, so it's one Chrome
  per process. Parallel workers each get their own, so set `CONCURRENT` to at least the worker count.
- **The app's address.** `Capybara.server_host = "0.0.0.0"`, with `app_host` set to the app's hostname on the
  compose network. When Rails runs on the host instead, use `host.docker.internal`, which needs
  `extra_hosts: ["host.docker.internal:host-gateway"]` on Linux.
- **WebMock and VCR.** Allow the `chrome` host, because `/json/version` goes through `Net::HTTP`.
- **Launch flags.** `browser_options: {"no-sandbox" => nil}` isn't needed. Ferrum doesn't send launch flags to a
  remote browser, so put them in the URL instead, e.g. `?launch={"defaultViewport":{"width":1400,"height":1400}}`.
- **GitHub Actions.** Service containers start before checkout, so start the driver with `docker run` in a step
  after checkout when uploads need the workspace mounted.

## Ferrum changes

1. Apply `window_size` to each page in remote mode. Today it only feeds the local `--window-size` flag, so a
   remote browser silently ignores it.
2. `Browser#debug` in remote mode prints the DevTools URL instead of `Process.spawn(process.path, …)`, which
   fails because the path is nil.
3. Never look for a local binary when `url` or `ws_url` is set (ferrum#554).
4. Optionally, send `window_size` and `browser_options` in the `launch` query parameter (`defaultViewport` and
   `args`) when connecting remotely.

## Status

Done:
- Config: `BROWSER_PATH`, `HOST`, `PORT`, `CONCURRENT`, `QUEUED`, `TIMEOUT`, `EXTERNAL` / `PROXY_URL`. Invalid
  values stop the driver at startup.
- One Chrome per connection, on `--remote-debugging-port=0`, with the endpoint read from stderr.
- `/json/version` is answered on the fly, with a claim timeout.
- The WebSocket goes through `ReverseProxy`.
- The process group gets TERM, then KILL, and the profile is removed when the connection ends. Each session logs
  why it ended: `connection closed`, `browser exited`, `timeout`, `never claimed` or `shutdown`.
- Session limits with `429` and `Retry-After`; queued connections give up when the client leaves or the driver
  shuts down.
- Launch options (`args`, `defaultViewport`, `ignoreDefaultArgs`, `headless`) and `timeout` in the URL.
- The DevTools routes.
- The dashboard at `/`, linked from each "session opened" log line.
- `/health` and the image's `HEALTHCHECK`, trailing-slash routes, `driver --help` and `--version`.
- A graceful shutdown stops every Chrome.
- Go tests (`go test ./...`), with the test binary acting as a fake Chrome, run in CI before any image is built.
- The Ferrum suite runs against every image in CI, and a daily check builds new browser versions.

Not done yet:
- the zero-copy tunnel;
- the Ferrum changes above.
