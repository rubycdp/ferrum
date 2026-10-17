package server

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"slices"
	"strings"
	"testing"
	"time"
)

const fakeBrowserEnv = "FAKE_BROWSER"

func TestMain(m *testing.M) {
	if os.Getenv(fakeBrowserEnv) == "1" {
		fakeBrowser(os.Args[1:])
		return
	}

	os.Setenv(fakeBrowserEnv, "1")
	os.Exit(m.Run())
}

func fakeBrowser(args []string) {
	if slices.Contains(args, "--fake-exit") {
		os.Exit(1)
	}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		os.Exit(1)
	}

	addr := listener.Addr().String()
	id := randomID()
	pageID := "page-" + id

	mux := http.NewServeMux()
	mux.HandleFunc("GET /json/version", func(w http.ResponseWriter, _ *http.Request) {
		if slices.Contains(args, "--fake-slow-version") {
			time.Sleep(time.Minute)
		}
		json.NewEncoder(w).Encode(map[string]any{
			"Browser":              "Fake/1.0",
			"Args":                 args,
			"webSocketDebuggerUrl": "ws://" + addr + "/devtools/browser/" + id,
		})
	})
	mux.HandleFunc("GET /json/list", func(w http.ResponseWriter, _ *http.Request) {
		json.NewEncoder(w).Encode([]map[string]any{{
			"id":                   pageID,
			"type":                 "page",
			"webSocketDebuggerUrl": "ws://" + addr + "/devtools/page/" + pageID,
			"devtoolsFrontendUrl":  "/devtools/inspector.html?ws=" + addr + "/devtools/page/" + pageID,
		}})
	})
	mux.HandleFunc("GET /json/protocol", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte(`{"version":{"major":"1","minor":"3"}}`))
	})
	mux.HandleFunc("PUT /json/new", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"id":                   "new-" + id,
			"url":                  r.URL.RawQuery,
			"webSocketDebuggerUrl": "ws://" + addr + "/devtools/page/new-" + id,
			"devtoolsFrontendUrl":  "/devtools/inspector.html?ws=" + addr + "/devtools/page/new-" + id,
		})
	})
	mux.HandleFunc("GET /devtools/inspector.html", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("inspector " + id))
	})
	mux.HandleFunc("GET /devtools/browser/"+id, echo)
	mux.HandleFunc("GET /devtools/page/"+pageID, echo)

	fmt.Fprintf(os.Stderr, "starting\nDevTools listening on ws://%s/devtools/browser/%s\n", addr, id)
	http.Serve(listener, mux)
}

func echo(w http.ResponseWriter, r *http.Request) {
	if !isUpgrade(r) {
		http.Error(w, "upgrade required", http.StatusBadRequest)
		return
	}

	conn, buf, err := w.(http.Hijacker).Hijack()
	if err != nil {
		return
	}
	defer conn.Close()

	buf.WriteString("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
	buf.Flush()
	io.Copy(conn, buf)
}

func randomID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return hex.EncodeToString(b)
}

type wsConn struct {
	net.Conn
	reader *bufio.Reader
}

func dial(t *testing.T, addr, path string) (*wsConn, *http.Response) {
	t.Helper()

	conn, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })

	fmt.Fprintf(conn, "GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"+
		"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n", path, addr)

	reader := bufio.NewReader(conn)
	resp, err := http.ReadResponse(reader, nil)
	if err != nil {
		t.Fatal(err)
	}

	return &wsConn{Conn: conn, reader: reader}, resp
}

func (c *wsConn) roundTrip(t *testing.T, message string) {
	t.Helper()

	c.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := io.WriteString(c, message); err != nil {
		t.Fatal(err)
	}

	got := make([]byte, len(message))
	if _, err := io.ReadFull(c.reader, got); err != nil {
		t.Fatal(err)
	}
	if string(got) != message {
		t.Fatalf("echo = %q, want %q", got, message)
	}
}

func (c *wsConn) waitClosed(t *testing.T) {
	t.Helper()

	c.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := c.reader.ReadByte(); err == nil || strings.Contains(err.Error(), "timeout") {
		t.Fatalf("connection still open: %v", err)
	}
}

func eventually(t *testing.T, condition func() bool) {
	t.Helper()

	deadline := time.Now().Add(5 * time.Second)
	for !condition() {
		if time.Now().After(deadline) {
			t.Fatal("condition not met in time")
		}
		time.Sleep(10 * time.Millisecond)
	}
}
