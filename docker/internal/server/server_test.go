package server

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"slices"
	"strings"
	"testing"
	"time"
)

type testServer struct {
	*httptest.Server
	sessions *Sessions
}

func newServer(t *testing.T, sessions SessionsConfig, config Config) *testServer {
	t.Helper()

	s := newSessions(t, sessions)
	srv := httptest.NewServer(New(s, config))
	t.Cleanup(srv.Close)

	return &testServer{Server: srv, sessions: s}
}

func (s *testServer) addr() string {
	return strings.TrimPrefix(s.URL, "http://")
}

func (s *testServer) get(t *testing.T, path string) *http.Response {
	t.Helper()

	resp, err := http.Get(s.URL + path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { resp.Body.Close() })

	return resp
}

func (s *testServer) body(t *testing.T, path string) string {
	t.Helper()

	body, err := io.ReadAll(s.get(t, path).Body)
	if err != nil {
		t.Fatal(err)
	}

	return string(body)
}

func (s *testServer) version(t *testing.T, query string) map[string]any {
	t.Helper()

	resp := s.get(t, "/json/version"+query)
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("status = %d: %s", resp.StatusCode, body)
	}

	var info map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		t.Fatal(err)
	}

	return info
}

func wsPath(t *testing.T, raw any) string {
	t.Helper()

	u, err := url.Parse(raw.(string))
	if err != nil {
		t.Fatal(err)
	}

	return u.RequestURI()
}

func TestHealth(t *testing.T) {
	srv := newServer(t, SessionsConfig{}, Config{})

	if resp := srv.get(t, "/health"); resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	if len(srv.sessions.Browsers()) != 0 {
		t.Fatal("health started a browser")
	}
}

func TestVersionAndClaim(t *testing.T) {
	srv := newServer(t, SessionsConfig{}, Config{})

	info := srv.version(t, "?token=abc")
	if info["Browser"] != "Fake/1.0" {
		t.Errorf("Browser = %v", info["Browser"])
	}

	ws, _ := url.Parse(info["webSocketDebuggerUrl"].(string))
	if ws.Host != srv.addr() || ws.RawQuery != "token=abc" || !strings.HasPrefix(ws.Path, "/devtools/browser/") {
		t.Fatalf("webSocketDebuggerUrl = %s", ws)
	}

	conn, resp := dial(t, srv.addr(), ws.RequestURI())
	if resp.StatusCode != http.StatusSwitchingProtocols {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	conn.roundTrip(t, "hello")

	conn.Close()
	eventually(t, func() bool { return len(srv.sessions.Browsers()) == 0 })
}

func TestConnectLeavesPendingBrowsersAlone(t *testing.T) {
	srv := newServer(t, SessionsConfig{}, Config{})

	info := srv.version(t, "")
	anonymous, _ := dial(t, srv.addr(), "/")
	anonymous.roundTrip(t, "anonymous")

	if n := len(srv.sessions.Browsers()); n != 2 {
		t.Fatalf("browsers = %d, want 2", n)
	}

	conn, resp := dial(t, srv.addr(), wsPath(t, info["webSocketDebuggerUrl"]))
	if resp.StatusCode != http.StatusSwitchingProtocols {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	conn.roundTrip(t, "hello")

	if n := len(srv.sessions.Browsers()); n != 2 {
		t.Fatalf("browsers = %d, want 2", n)
	}
}

func TestBadRequests(t *testing.T) {
	srv := newServer(t, SessionsConfig{}, Config{})

	for path, status := range map[string]int{
		"/json/version?launch=%7Bbroken":  http.StatusBadRequest,
		"/json/version?timeout=soon":      http.StatusBadRequest,
		"/chrome":                         http.StatusNotFound,
		"/devtools/browser/missing":       http.StatusUpgradeRequired,
		"/devtools/page/missing":          http.StatusUpgradeRequired,
		"/unknown":                        http.StatusNotFound,
		"/devtools/inspector.html":        http.StatusServiceUnavailable,
		"/json/new?https://example.com/":  http.StatusConflict,
		"/json/version/?launch=%7Bbroken": http.StatusBadRequest,
	} {
		if resp := srv.get(t, path); resp.StatusCode != status {
			t.Errorf("%s: status = %d, want %d", path, resp.StatusCode, status)
		}
	}

	if n := len(srv.sessions.Browsers()); n != 0 {
		t.Fatalf("bad requests started %d browsers", n)
	}
}

func TestLaunchOptionsReachTheBrowser(t *testing.T) {
	srv := newServer(t, SessionsConfig{}, Config{})

	launch := url.QueryEscape(`{"args":["--accept-lang=de-DE","--user-data-dir=/elsewhere"],"defaultViewport":{"width":1280,"height":720},"ignoreDefaultArgs":["--mute-audio"]}`)
	info := srv.version(t, "?launch="+launch)

	var args []string
	for _, arg := range info["Args"].([]any) {
		args = append(args, arg.(string))
	}

	for _, want := range []string{"--accept-lang=de-DE", "--window-size=1280,720", "--remote-debugging-port=0"} {
		if !slices.Contains(args, want) {
			t.Errorf("missing %s in %v", want, args)
		}
	}
	for _, unwanted := range []string{"--mute-audio", "--window-size=1024,768", "--user-data-dir=/elsewhere"} {
		if slices.Contains(args, unwanted) {
			t.Errorf("unexpected %s in %v", unwanted, args)
		}
	}
}

func TestQueueLimit(t *testing.T) {
	srv := newServer(t, SessionsConfig{Concurrent: 1, Queued: 0}, Config{})

	conn, _ := dial(t, srv.addr(), "/")
	conn.roundTrip(t, "hello")

	resp := srv.get(t, "/json/version")
	if resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want 429", resp.StatusCode)
	}
	if resp.Header.Get("Retry-After") == "" {
		t.Error("missing Retry-After")
	}

	_, resp = dial(t, srv.addr(), "/")
	if resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("websocket status = %d, want 429", resp.StatusCode)
	}
}

func TestQueuedConnectionWaitsForAFreeSession(t *testing.T) {
	srv := newServer(t, SessionsConfig{Concurrent: 1, Queued: 1}, Config{})

	first, _ := dial(t, srv.addr(), "/")
	first.roundTrip(t, "first")

	time.AfterFunc(200*time.Millisecond, func() { first.Close() })

	second, resp := dial(t, srv.addr(), "/")
	if resp.StatusCode != http.StatusSwitchingProtocols {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	second.roundTrip(t, "second")
}

func TestSessionTimeout(t *testing.T) {
	t.Run("from the query", func(t *testing.T) {
		srv := newServer(t, SessionsConfig{}, Config{})

		conn, _ := dial(t, srv.addr(), "/?timeout=100")
		conn.roundTrip(t, "hello")
		conn.waitClosed(t)
		eventually(t, func() bool { return len(srv.sessions.Browsers()) == 0 })
	})

	t.Run("from the config", func(t *testing.T) {
		srv := newServer(t, SessionsConfig{}, Config{Timeout: 100 * time.Millisecond})

		conn, _ := dial(t, srv.addr(), "/")
		conn.roundTrip(t, "hello")
		conn.waitClosed(t)
	})

	t.Run("query 0 turns it off", func(t *testing.T) {
		srv := newServer(t, SessionsConfig{}, Config{Timeout: 100 * time.Millisecond})

		conn, _ := dial(t, srv.addr(), "/?timeout=0")
		time.Sleep(300 * time.Millisecond)
		conn.roundTrip(t, "still here")
	})
}

func TestPublicURL(t *testing.T) {
	t.Run("forwarded headers", func(t *testing.T) {
		srv := newServer(t, SessionsConfig{}, Config{})

		req, _ := http.NewRequest(http.MethodGet, srv.URL+"/json/version", nil)
		req.Header.Set("X-Forwarded-Host", "chrome.example.com")
		req.Header.Set("X-Forwarded-Proto", "https")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()

		var info map[string]any
		json.NewDecoder(resp.Body).Decode(&info)
		if ws := info["webSocketDebuggerUrl"].(string); !strings.HasPrefix(ws, "wss://chrome.example.com/devtools/browser/") {
			t.Fatalf("webSocketDebuggerUrl = %s", ws)
		}
	})

	t.Run("external", func(t *testing.T) {
		external, _ := url.Parse("https://proxy.example.com/chrome")
		srv := newServer(t, SessionsConfig{}, Config{External: external})

		info := srv.version(t, "?a=1")
		ws := info["webSocketDebuggerUrl"].(string)
		if !strings.HasPrefix(ws, "wss://proxy.example.com/chrome/devtools/browser/") || !strings.HasSuffix(ws, "?a=1") {
			t.Fatalf("webSocketDebuggerUrl = %s", ws)
		}
	})
}

func TestVersionTimesOutOnAStuckBrowser(t *testing.T) {
	defer func(timeout time.Duration) { requestTimeout = timeout }(requestTimeout)
	requestTimeout = 100 * time.Millisecond

	srv := newServer(t, SessionsConfig{}, Config{})

	launch := url.QueryEscape(`{"args":["--fake-slow-version"]}`)
	if resp := srv.get(t, "/json/version?launch="+launch); resp.StatusCode != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", resp.StatusCode)
	}
	eventually(t, func() bool { return len(srv.sessions.Browsers()) == 0 })
}

func TestDevTools(t *testing.T) {
	srv := newServer(t, SessionsConfig{}, Config{})

	conn, _ := dial(t, srv.addr(), "/")
	conn.roundTrip(t, "hello")

	var targets []map[string]any
	json.NewDecoder(srv.get(t, "/json/list").Body).Decode(&targets)
	if len(targets) != 1 {
		t.Fatalf("targets = %v", targets)
	}

	target := targets[0]
	id := target["id"].(string)
	if ws := target["webSocketDebuggerUrl"]; ws != "ws://"+srv.addr()+"/devtools/page/"+id {
		t.Errorf("webSocketDebuggerUrl = %v", ws)
	}
	if frontend := target["devtoolsFrontendUrl"]; frontend != "/devtools/inspector.html?ws="+srv.addr()+"/devtools/page/"+id {
		t.Errorf("devtoolsFrontendUrl = %v", frontend)
	}

	t.Run("/json is an alias", func(t *testing.T) {
		var alias []map[string]any
		json.NewDecoder(srv.get(t, "/json").Body).Decode(&alias)
		if len(alias) != 1 || alias[0]["id"] != id {
			t.Fatalf("targets = %v", alias)
		}
	})

	t.Run("page websocket", func(t *testing.T) {
		page, resp := dial(t, srv.addr(), "/devtools/page/"+id)
		if resp.StatusCode != http.StatusSwitchingProtocols {
			t.Fatalf("status = %d", resp.StatusCode)
		}
		page.roundTrip(t, "page")
		page.Close()

		conn.roundTrip(t, "session survives the page connection")
	})

	t.Run("unknown page", func(t *testing.T) {
		_, resp := dial(t, srv.addr(), "/devtools/page/missing")
		if resp.StatusCode != http.StatusNotFound {
			t.Fatalf("status = %d, want 404", resp.StatusCode)
		}
	})

	t.Run("frontend", func(t *testing.T) {
		body, _ := io.ReadAll(srv.get(t, "/devtools/inspector.html").Body)
		if !strings.HasPrefix(string(body), "inspector ") {
			t.Fatalf("body = %s", body)
		}
	})

	t.Run("protocol", func(t *testing.T) {
		body, _ := io.ReadAll(srv.get(t, "/json/protocol").Body)
		if !strings.Contains(string(body), `"major":"1"`) {
			t.Fatalf("body = %s", body)
		}
	})

	t.Run("new target", func(t *testing.T) {
		req, _ := http.NewRequest(http.MethodPut, srv.URL+"/json/new?https://example.com/", nil)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()

		var created map[string]any
		json.NewDecoder(resp.Body).Decode(&created)
		if created["url"] != "https://example.com/" || !strings.HasPrefix(created["webSocketDebuggerUrl"].(string), "ws://"+srv.addr()+"/devtools/page/") {
			t.Fatalf("target = %v", created)
		}
	})
}

func TestProtocolWithoutASession(t *testing.T) {
	srv := newServer(t, SessionsConfig{}, Config{})

	body, _ := io.ReadAll(srv.get(t, "/json/protocol").Body)
	if !strings.Contains(string(body), `"major":"1"`) {
		t.Fatalf("body = %s", body)
	}
	if n := len(srv.sessions.Browsers()); n != 0 {
		t.Fatalf("browsers = %d, want 0", n)
	}
}

func TestDashboard(t *testing.T) {
	srv := newServer(t, SessionsConfig{}, Config{})

	if body := srv.body(t, "/"); !strings.Contains(body, "No running sessions.") {
		t.Fatalf("body = %s", body)
	}

	conn, _ := dial(t, srv.addr(), "/")
	conn.roundTrip(t, "hello")

	b := srv.sessions.Browsers()[0]
	body := srv.body(t, "/")
	if !strings.Contains(body, `id="`+b.ID+`"`) {
		t.Errorf("session %s missing in %s", b.ID, body)
	}
	if want := srv.URL + "/devtools/inspector.html?ws=" + srv.addr() + "/devtools/page/page-"; !strings.Contains(body, want) {
		t.Errorf("DevTools link %s missing in %s", want, body)
	}

	t.Run("behind a proxy", func(t *testing.T) {
		external, _ := url.Parse("https://proxy.example.com/chrome")
		srv := newServer(t, SessionsConfig{}, Config{External: external})
		conn, _ := dial(t, srv.addr(), "/")
		conn.roundTrip(t, "hello")

		want := "https://proxy.example.com/chrome/devtools/inspector.html?wss=proxy.example.com/chrome/devtools/page/page-"
		if body := srv.body(t, "/"); !strings.Contains(body, want) {
			t.Errorf("DevTools link %s missing in %s", want, body)
		}
	})
}
