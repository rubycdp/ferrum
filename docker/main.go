package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/rubycdp/ferrum/docker/internal/browser"
	"github.com/rubycdp/ferrum/docker/internal/config"
	"github.com/rubycdp/ferrum/docker/internal/server"
)

const shutdownTimeout = 10 * time.Second

const usage = `Usage: driver [options]

Serves one Chrome per CDP connection.
Each WebSocket gets a fresh Chrome that is killed when the client disconnects.

Options:
  -h, --help       show this help
  -v, --version    print the version

Environment:
  BROWSER_PATH     Chrome or Chromium binary (set by the image)
  HOST             address to listen on (default 0.0.0.0)
  PORT             port to listen on (default 3000)
  CONCURRENT       running sessions at most (default: number of CPUs)
  QUEUED           connections waiting for a free session, the rest get 429 (default 10)
  TIMEOUT          session timeout in milliseconds (default 0, no timeout)
  EXTERNAL         public URL of the driver behind a proxy, e.g. https://chrome.example.com
                   (PROXY_URL works too)

Endpoints:
  GET /json/version                start a Chrome, return its webSocketDebuggerUrl
  WS  /devtools/browser/<id>       connect to the Chrome started by /json/version
  WS  /                            connect to a new Chrome
  GET /json, /json/list            targets of every running session
  PUT /json/new?<url>              open a target, when exactly one session runs
  GET /json/protocol               the CDP protocol description
  WS  /devtools/page/<id>          connect to one target, e.g. from DevTools
  GET /devtools/*                  the DevTools frontend of a running session
  GET /health                      liveness, never starts a Chrome
  GET /                            dashboard: running sessions with DevTools links

Launch options (per connection, in the URL of /json/version or the WebSocket):
  launch=<JSON or base64 JSON>
    args               extra Chrome flags, a flag with a default's name replaces it
    defaultViewport    {"width":1280,"height":720}, becomes --window-size
    ignoreDefaultArgs  true, or a list of default flags to drop
    headless           false runs Chrome with a window, under its own Xvfb
  timeout=<ms>         session timeout for this connection, overrides TIMEOUT
  Other launch keys and query params are ignored.
  --remote-debugging-port and --user-data-dir are managed by the driver.

  http://localhost:3000?launch={"args":["--accept-lang=de-DE"]}&timeout=60000
  ws://localhost:3000?launch={"defaultViewport":{"width":1280,"height":720}}

Default Chrome flags:
%s
Examples:
  docker run --rm -p 3000:3000 ghcr.io/rubycdp/chrome
  docker run --rm -p 3000:3000 -v "$PWD:$PWD" ghcr.io/rubycdp/chromium
  BROWSER_PATH=/usr/bin/chromium PORT=9222 driver

  Ferrum::Browser.new(url: "http://localhost:3000")
  Ferrum::Browser.new(ws_url: "ws://localhost:3000")
`

func main() {
	showVersion := flag.Bool("version", false, "")
	flag.BoolVar(showVersion, "v", false, "")
	flag.Usage = func() { fmt.Fprintf(flag.CommandLine.Output(), usage, defaultFlags()) }
	flag.Parse()

	if *showVersion {
		fmt.Println(config.Version)
		return
	}

	if err := config.Load(); err != nil {
		slog.Error("invalid configuration", "error", err)
		os.Exit(1)
	}

	sessions := server.NewSessions(server.SessionsConfig{
		Binary:     config.BrowserPath,
		Concurrent: config.Concurrent,
		Queued:     config.Queued,
	})
	srv := &http.Server{
		Addr:              config.Address,
		Handler:           server.New(sessions, server.Config{Timeout: config.Timeout, External: config.External}),
		ReadHeaderTimeout: 10 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		<-ctx.Done()
		slog.Info("shutting down")

		shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		srv.Shutdown(shutdownCtx)
	}()

	slog.Info("listening", "address", config.Address, "browser", config.BrowserPath, "version", config.Version,
		"concurrent", config.Concurrent, "queued", config.Queued, "timeout", config.Timeout)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		slog.Error("server failed", "error", err)
		os.Exit(1)
	}

	sessions.StopAll()
}

func defaultFlags() string {
	var b strings.Builder
	for _, flag := range browser.Defaults() {
		b.WriteString("  " + flag + "\n")
	}

	return b.String()
}
