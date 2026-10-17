package config

import (
	"fmt"
	"net"
	"net/url"
	"os"
	"runtime"
	"strconv"
	"time"
)

var (
	Version string

	BrowserPath string
	Address     string
	Concurrent  int
	Queued      int
	Timeout     time.Duration
	External    *url.URL
)

func Load() error {
	BrowserPath = os.Getenv("BROWSER_PATH")
	if BrowserPath == "" {
		return fmt.Errorf("BROWSER_PATH is not set")
	}

	Address = net.JoinHostPort(env("HOST", "0.0.0.0"), env("PORT", "3000"))

	var err error
	if Concurrent, err = intEnv("CONCURRENT", runtime.NumCPU()); err != nil {
		return err
	}
	if Concurrent < 1 {
		return fmt.Errorf("CONCURRENT must be at least 1, got %d", Concurrent)
	}

	if Queued, err = intEnv("QUEUED", 10); err != nil {
		return err
	}
	if Queued < 0 {
		return fmt.Errorf("QUEUED must not be negative, got %d", Queued)
	}

	timeout, err := intEnv("TIMEOUT", 0)
	if err != nil {
		return err
	}
	Timeout = time.Duration(max(timeout, 0)) * time.Millisecond

	if External, err = externalURL(); err != nil {
		return err
	}

	return nil
}

func env(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}

	return fallback
}

func intEnv(key string, fallback int) (int, error) {
	value := env(key, "")
	if value == "" {
		return fallback, nil
	}

	n, err := strconv.Atoi(value)
	if err != nil {
		return 0, fmt.Errorf("%s must be a number, got %q", key, value)
	}

	return n, nil
}

func externalURL() (*url.URL, error) {
	value := env("EXTERNAL", env("PROXY_URL", ""))
	if value == "" {
		return nil, nil
	}

	u, err := url.Parse(value)
	if err != nil || u.Host == "" {
		return nil, fmt.Errorf("EXTERNAL must be an absolute URL, got %q", value)
	}

	return u, nil
}
