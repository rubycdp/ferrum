package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/rubycdp/ferrum/docker/internal/browser"
)

const retryAfter = "5"

var requestTimeout = 10 * time.Second

type Config struct {
	Timeout  time.Duration
	External *url.URL
}

type Server struct {
	sessions *Sessions
	config   Config
	client   *http.Client
}

func New(sessions *Sessions, config Config) http.Handler {
	s := &Server{
		sessions: sessions,
		config:   config,
		client:   &http.Client{Timeout: requestTimeout},
	}

	mux := http.NewServeMux()
	handle(mux, "/health", s.health)
	handle(mux, "/json/version", s.version)
	handle(mux, "/devtools/browser/{id}", s.connect)
	handle(mux, "/chrome", s.connect)
	handle(mux, "/chromium", s.connect)
	mux.HandleFunc("GET /{$}", s.connect)

	return mux
}

func handle(mux *http.ServeMux, path string, handler http.HandlerFunc) {
	mux.HandleFunc("GET "+path, handler)
	mux.HandleFunc("GET "+path+"/{$}", handler)
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	w.Write([]byte("ok"))
}

func (s *Server) version(w http.ResponseWriter, r *http.Request) {
	options, ok := launchOptions(w, r)
	if !ok {
		return
	}
	if _, ok := s.sessionTimeout(w, r); !ok {
		return
	}

	b, err := s.sessions.Start(r.Context(), options)
	if err != nil {
		startError(w, err)
		return
	}

	var info map[string]any
	if err := s.getJSON(b, "/json/version", &info); err != nil {
		slog.Error("cannot fetch browser version", "id", b.ID, "error", err)
		s.sessions.Stop(b, "version failed")
		http.Error(w, "cannot fetch browser version", http.StatusBadGateway)
		return
	}

	info["webSocketDebuggerUrl"] = s.publicURL(r, b.WSPath, r.URL.RawQuery)
	s.sessions.Reserve(b, r.URL.RawQuery)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

func (s *Server) connect(w http.ResponseWriter, r *http.Request) {
	if !isUpgrade(r) {
		http.Error(w, "websocket upgrade required", http.StatusUpgradeRequired)
		return
	}

	options, ok := launchOptions(w, r)
	if !ok {
		return
	}
	timeout, ok := s.sessionTimeout(w, r)
	if !ok {
		return
	}

	b, err := s.sessions.ClaimOrStart(r.Context(), r.PathValue("id"), r.URL.RawQuery, options)
	if err != nil {
		startError(w, err)
		return
	}

	s.serve(w, r, b, timeout)
}

func (s *Server) serve(w http.ResponseWriter, r *http.Request, b *browser.Browser, timeout time.Duration) {
	if timeout > 0 {
		timer := time.AfterFunc(timeout, func() { s.sessions.Stop(b, "timeout") })
		defer timer.Stop()
	}

	slog.Info("session opened", "id", b.ID, "client", r.RemoteAddr, "timeout", timeout)
	proxyTo(b).ServeHTTP(w, r)
	s.sessions.Stop(b, "connection closed")
}

func (s *Server) sessionTimeout(w http.ResponseWriter, r *http.Request) (time.Duration, bool) {
	value := r.URL.Query().Get("timeout")
	if value == "" {
		return s.config.Timeout, true
	}

	ms, err := strconv.Atoi(value)
	if err != nil {
		http.Error(w, fmt.Sprintf("invalid timeout %q", value), http.StatusBadRequest)
		return 0, false
	}

	return time.Duration(max(ms, 0)) * time.Millisecond, true
}

func startError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrQueueFull):
		w.Header().Set("Retry-After", retryAfter)
		http.Error(w, err.Error(), http.StatusTooManyRequests)
	case errors.Is(err, context.Canceled):
	default:
		slog.Error("cannot start browser", "error", err)
		http.Error(w, "cannot start browser", http.StatusServiceUnavailable)
	}
}

func proxyTo(b *browser.Browser) *httputil.ReverseProxy {
	return &httputil.ReverseProxy{
		Rewrite: func(pr *httputil.ProxyRequest) {
			pr.Out.URL.Scheme = "http"
			pr.Out.URL.Host = b.Addr
			pr.Out.URL.Path = b.WSPath
			pr.Out.URL.RawPath = ""
			pr.Out.URL.RawQuery = ""
			pr.Out.Host = b.Addr
			pr.Out.Header.Del("Origin")
		},
		ErrorHandler: func(w http.ResponseWriter, _ *http.Request, err error) {
			slog.Error("cannot proxy to browser", "id", b.ID, "error", err)
			http.Error(w, "browser unavailable", http.StatusBadGateway)
		},
	}
}

func launchOptions(w http.ResponseWriter, r *http.Request) (browser.Options, bool) {
	options, err := browser.ParseOptions(r.URL.Query().Get("launch"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return options, false
	}

	return options, true
}

func (s *Server) getJSON(b *browser.Browser, path string, v any) error {
	req, err := http.NewRequest(http.MethodGet, "http://"+b.Addr+path, nil)
	if err != nil {
		return err
	}

	return s.doJSON(req, v)
}

func (s *Server) doJSON(req *http.Request, v any) error {
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status %s", resp.Status)
	}

	if err := json.NewDecoder(resp.Body).Decode(v); err != nil {
		return fmt.Errorf("decode: %w", err)
	}

	return nil
}

func (s *Server) publicURL(r *http.Request, wsPath, query string) string {
	if external := s.config.External; external != nil {
		scheme := "ws"
		if external.Scheme == "https" || external.Scheme == "wss" {
			scheme = "wss"
		}

		u := url.URL{Scheme: scheme, Host: external.Host, Path: path.Join("/", external.Path, wsPath), RawQuery: query}
		return u.String()
	}

	scheme := "ws"
	if r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
		scheme = "wss"
	}

	host := r.Header.Get("X-Forwarded-Host")
	if host == "" {
		host = r.Host
	}

	u := url.URL{Scheme: scheme, Host: host, Path: wsPath, RawQuery: query}
	return u.String()
}

func isUpgrade(r *http.Request) bool {
	return strings.EqualFold(r.Header.Get("Upgrade"), "websocket")
}
