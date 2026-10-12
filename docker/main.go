package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/rubycdp/ferrum/docker/internal/config"
	"github.com/rubycdp/ferrum/docker/internal/server"
)

const shutdownTimeout = 10 * time.Second

func main() {
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
