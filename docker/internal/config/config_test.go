package config

import (
	"runtime"
	"testing"
	"time"
)

func TestLoadDefaults(t *testing.T) {
	t.Setenv("BROWSER_PATH", "/usr/bin/chromium")
	for _, key := range []string{"HOST", "PORT", "CONCURRENT", "QUEUED", "TIMEOUT", "EXTERNAL", "PROXY_URL"} {
		t.Setenv(key, "")
	}

	if err := Load(); err != nil {
		t.Fatal(err)
	}

	if Address != "0.0.0.0:3000" || Concurrent != runtime.NumCPU() || Queued != 10 || Timeout != 0 || External != nil {
		t.Fatalf("address=%s concurrent=%d queued=%d timeout=%s external=%v", Address, Concurrent, Queued, Timeout, External)
	}
}

func TestLoad(t *testing.T) {
	t.Setenv("BROWSER_PATH", "/usr/bin/chromium")
	t.Setenv("HOST", "127.0.0.1")
	t.Setenv("PORT", "9222")
	t.Setenv("CONCURRENT", "2")
	t.Setenv("QUEUED", "0")
	t.Setenv("TIMEOUT", "60000")
	t.Setenv("EXTERNAL", "")
	t.Setenv("PROXY_URL", "https://chrome.example.com")

	if err := Load(); err != nil {
		t.Fatal(err)
	}

	if Address != "127.0.0.1:9222" || Concurrent != 2 || Queued != 0 || Timeout != time.Minute || External.Host != "chrome.example.com" {
		t.Fatalf("address=%s concurrent=%d queued=%d timeout=%s external=%v", Address, Concurrent, Queued, Timeout, External)
	}
}

func TestLoadErrors(t *testing.T) {
	for name, env := range map[string]map[string]string{
		"no browser":        {"BROWSER_PATH": ""},
		"concurrent text":   {"CONCURRENT": "many"},
		"concurrent zero":   {"CONCURRENT": "0"},
		"queued negative":   {"QUEUED": "-1"},
		"timeout text":      {"TIMEOUT": "30s"},
		"external relative": {"EXTERNAL": "chrome.example.com"},
	} {
		t.Run(name, func(t *testing.T) {
			t.Setenv("BROWSER_PATH", "/usr/bin/chromium")
			for key, value := range env {
				t.Setenv(key, value)
			}

			if err := Load(); err == nil {
				t.Error("expected an error")
			}
		})
	}
}
