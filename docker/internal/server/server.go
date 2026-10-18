package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"path"
	"strconv"
	"strings"
	"sync"
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

	protocolMu sync.Mutex
	protocol   []byte
}

func New(sessions *Sessions, config Config) http.Handler {
	s := &Server{
		sessions: sessions,
		config:   config,
		client:   &http.Client{Timeout: requestTimeout},
	}

	mux := http.NewServeMux()
	handle(mux, "GET", "/health", s.health)
	handle(mux, "GET", "/json/version", s.version)
	handle(mux, "GET", "/json", s.list)
	handle(mux, "GET", "/json/list", s.list)
	handle(mux, "GET", "/json/protocol", s.jsonProtocol)
	handle(mux, "PUT", "/json/new", s.newTarget)
	handle(mux, "GET", "/json/new", s.newTarget)
	handle(mux, "GET", "/devtools/browser/{id}", s.connect)
	handle(mux, "GET", "/devtools/page/{id}", s.page)
	mux.HandleFunc("GET /devtools/{path...}", s.frontend)
	mux.HandleFunc("GET /{$}", s.root)

	return mux
}

func handle(mux *http.ServeMux, method, path string, handler http.HandlerFunc) {
	mux.HandleFunc(method+" "+path, handler)
	mux.HandleFunc(method+" "+path+"/{$}", handler)
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
		s.startError(w, err)
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
	s.sessions.Reserve(b)

	writeJSON(w, info)
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

	b, err := s.sessions.ClaimOrStart(r.Context(), r.PathValue("id"), options)
	if err != nil {
		s.startError(w, err)
		return
	}

	if timeout > 0 {
		timer := time.AfterFunc(timeout, func() { s.sessions.Stop(b, "timeout") })
		defer timer.Stop()
	}

	slog.Info("session opened", "id", b.ID, "client", r.RemoteAddr, "timeout", timeout, "dashboard", s.httpURL(r, "/")+"#"+b.ID)
	proxy(b, b.WSPath, "").ServeHTTP(w, r)
	s.sessions.Stop(b, "connection closed")
}

func (s *Server) page(w http.ResponseWriter, r *http.Request) {
	if !isUpgrade(r) {
		http.Error(w, "websocket upgrade required", http.StatusUpgradeRequired)
		return
	}

	id := r.PathValue("id")
	for _, b := range s.sessions.Browsers() {
		targets, err := s.targets(b)
		if err != nil {
			continue
		}

		for _, target := range targets {
			if target["id"] == id {
				proxy(b, "/devtools/page/"+id, "").ServeHTTP(w, r)
				return
			}
		}
	}

	http.Error(w, "target not found", http.StatusNotFound)
}

func (s *Server) list(w http.ResponseWriter, r *http.Request) {
	all := []map[string]any{}
	for _, b := range s.sessions.Browsers() {
		targets, err := s.targets(b)
		if err != nil {
			slog.Warn("cannot list browser targets", "id", b.ID, "error", err)
			continue
		}

		for _, target := range targets {
			all = append(all, s.publicTarget(r, b, target))
		}
	}

	writeJSON(w, all)
}

func (s *Server) newTarget(w http.ResponseWriter, r *http.Request) {
	browsers := s.sessions.Browsers()
	if len(browsers) != 1 {
		http.Error(w, fmt.Sprintf("/json/new needs exactly one running session, there are %d", len(browsers)), http.StatusConflict)
		return
	}

	b := browsers[0]
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPut, "http://"+b.Addr+"/json/new?"+r.URL.RawQuery, nil)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var target map[string]any
	if err := s.doJSON(req, &target); err != nil {
		http.Error(w, "cannot create target", http.StatusBadGateway)
		return
	}

	writeJSON(w, s.publicTarget(r, b, target))
}

func (s *Server) jsonProtocol(w http.ResponseWriter, r *http.Request) {
	s.protocolMu.Lock()
	defer s.protocolMu.Unlock()

	if s.protocol == nil {
		protocol, err := s.fetchProtocol(r.Context())
		if err != nil {
			s.startError(w, err)
			return
		}
		s.protocol = protocol
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(s.protocol)
}

func (s *Server) frontend(w http.ResponseWriter, r *http.Request) {
	browsers := s.sessions.Browsers()
	if len(browsers) == 0 {
		http.Error(w, "no running session", http.StatusServiceUnavailable)
		return
	}

	proxy(browsers[0], r.URL.Path, r.URL.RawQuery).ServeHTTP(w, r)
}

func (s *Server) fetchProtocol(ctx context.Context) ([]byte, error) {
	if browsers := s.sessions.Browsers(); len(browsers) > 0 {
		return s.get(browsers[0], "/json/protocol")
	}

	b, err := s.sessions.Start(ctx, browser.Options{})
	if err != nil {
		return nil, err
	}
	defer s.sessions.Stop(b, "protocol fetched")

	return s.get(b, "/json/protocol")
}

func (s *Server) startError(w http.ResponseWriter, err error) {
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

func (s *Server) targets(b *browser.Browser) ([]map[string]any, error) {
	var targets []map[string]any
	return targets, s.getJSON(b, "/json/list", &targets)
}

func (s *Server) publicTarget(r *http.Request, b *browser.Browser, target map[string]any) map[string]any {
	id, _ := target["id"].(string)
	wsURL := s.publicURL(r, "/devtools/page/"+id, "")
	target["webSocketDebuggerUrl"] = wsURL

	if frontend, ok := target["devtoolsFrontendUrl"].(string); ok {
		u, _ := url.Parse(wsURL)
		param := "ws="
		if u.Scheme == "wss" {
			param = "wss="
		}
		frontend = strings.Replace(frontend, "ws="+b.Addr, param+u.Host+strings.TrimSuffix(u.Path, "/devtools/page/"+id), 1)
		target["devtoolsFrontendUrl"] = frontend
	}

	return target
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

func (s *Server) get(b *browser.Browser, path string) ([]byte, error) {
	resp, err := s.client.Get("http://" + b.Addr + path)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status %s", resp.Status)
	}

	return io.ReadAll(resp.Body)
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

func proxy(b *browser.Browser, path, query string) *httputil.ReverseProxy {
	return &httputil.ReverseProxy{
		Rewrite: func(pr *httputil.ProxyRequest) {
			pr.Out.URL.Scheme = "http"
			pr.Out.URL.Host = b.Addr
			pr.Out.URL.Path = path
			pr.Out.URL.RawPath = ""
			pr.Out.URL.RawQuery = query
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

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func isUpgrade(r *http.Request) bool {
	return strings.EqualFold(r.Header.Get("Upgrade"), "websocket")
}
