package config

import (
	"net"
	"os"
)

var (
	Version string

	BrowserPath = os.Getenv("BROWSER_PATH")
	Address     = net.JoinHostPort(env("HOST", "0.0.0.0"), env("PORT", "3000"))
)

func env(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}

	return fallback
}
