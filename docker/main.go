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

Serves one Chrome per CDP connection, compatible with browserless v2 clients.
Each WebSocket gets a fresh Chrome that is killed when the client disconnects.

Options:
  -h, --help       show this help
  -v, --version    print the version

Environment:
  BROWSER_PATH     Chrome or Chromium binary (set by the image)
  HOST             address to listen on (default 0.0.0.0)
  PORT             port to listen on (default 3000)

Endpoints:
  GET /json/version                start a Chrome, return its webSocketDebuggerUrl
  WS  /devtools/browser/<id>       connect to the Chrome started by /json/version
  WS  /, /chrome, /chromium        connect to a new Chrome
  GET /health                      liveness, never starts a Chrome

Launch options (per connection, in the URL of /json/version or the WebSocket):
  launch=<JSON or base64 JSON>
    args               extra Chrome flags, a flag with a default's name replaces it
    defaultViewport    {"width":1280,"height":720}, becomes --window-size
    ignoreDefaultArgs  true, or a list of default flags to drop
  Other launch keys and query params (token, blockAds) are ignored.
  --remote-debugging-port and --user-data-dir are managed by the driver.

  http://localhost:3000?launch={"args":["--accept-lang=de-DE"]}
  ws://localhost:3000/chrome?launch={"defaultViewport":{"width":1280,"height":720}}

Default Chrome flags:
%s
Examples:
  docker run --rm -p 3000:3000 ghcr.io/rubycdp/chrome
  docker run --rm -p 3000:3000 -v "$PWD:$PWD" ghcr.io/rubycdp/chromium
  BROWSER_PATH=/usr/bin/chromium PORT=9222 driver

  Ferrum::Browser.new(url: "http://localhost:3000")
  Ferrum::Browser.new(ws_url: "ws://localhost:3000/chrome")
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

	if config.BrowserPath == "" {
		slog.Error("BROWSER_PATH is not set")
		os.Exit(1)
	}

	sessions := server.NewSessions(config.BrowserPath)
	srv := &http.Server{
		Addr:              config.Address,
		Handler:           server.New(sessions),
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

	slog.Info("listening", "address", config.Address, "browser", config.BrowserPath, "version", config.Version)
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
