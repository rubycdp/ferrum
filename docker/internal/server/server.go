package server

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"

	"github.com/rubycdp/ferrum/docker/internal/browser"
)

type Server struct {
	sessions *Sessions
}

func New(sessions *Sessions) http.Handler {
	s := &Server{sessions: sessions}

	mux := http.NewServeMux()
	handle(mux, "/health", s.health)
	handle(mux, "/json/version", s.version)
	handle(mux, "/devtools/browser/{id}", s.claim)
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
	b, err := s.sessions.Start()
	if err != nil {
		slog.Error("cannot start browser", "error", err)
		http.Error(w, "cannot start browser", http.StatusServiceUnavailable)
		return
	}

	info, err := fetchVersion(b)
	if err != nil {
		slog.Error("cannot fetch browser version", "id", b.ID, "error", err)
		s.sessions.Stop(b)
		http.Error(w, "cannot fetch browser version", http.StatusBadGateway)
		return
	}

	info["webSocketDebuggerUrl"] = publicURL(r, b.WSPath)
	s.sessions.Reserve(b, r.URL.RawQuery)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

func (s *Server) claim(w http.ResponseWriter, r *http.Request) {
	if !isUpgrade(r) {
		http.Error(w, "websocket upgrade required", http.StatusUpgradeRequired)
		return
	}

	b := s.sessions.Claim(r.PathValue("id"))
	if b == nil {
		http.Error(w, "browser not found", http.StatusNotFound)
		return
	}

	s.serve(w, r, b)
}

func (s *Server) connect(w http.ResponseWriter, r *http.Request) {
	if !isUpgrade(r) {
		http.Error(w, "websocket upgrade required", http.StatusUpgradeRequired)
		return
	}

	b, err := s.sessions.ClaimOrStart(r.URL.RawQuery)
	if err != nil {
		slog.Error("cannot start browser", "error", err)
		http.Error(w, "cannot start browser", http.StatusServiceUnavailable)
		return
	}

	s.serve(w, r, b)
}

func (s *Server) serve(w http.ResponseWriter, r *http.Request, b *browser.Browser) {
	defer s.sessions.Stop(b)

	slog.Info("session opened", "id", b.ID, "client", r.RemoteAddr)
	proxyTo(b).ServeHTTP(w, r)
	slog.Info("session closed", "id", b.ID, "client", r.RemoteAddr)
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

func fetchVersion(b *browser.Browser) (map[string]any, error) {
	resp, err := http.Get("http://" + b.Addr + "/json/version")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status %s", resp.Status)
	}

	var info map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return nil, fmt.Errorf("decode: %w", err)
	}

	return info, nil
}

func publicURL(r *http.Request, wsPath string) string {
	scheme := "ws"
	if r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
		scheme = "wss"
	}

	host := r.Header.Get("X-Forwarded-Host")
	if host == "" {
		host = r.Host
	}

	u := url.URL{Scheme: scheme, Host: host, Path: wsPath, RawQuery: r.URL.RawQuery}
	return u.String()
}

func isUpgrade(r *http.Request) bool {
	return strings.EqualFold(r.Header.Get("Upgrade"), "websocket")
}
