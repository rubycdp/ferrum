package browser

import (
	"fmt"
	"slices"
	"strings"
)

const (
	chromeDebuggingPortFlag = "--remote-debugging-port"
	chromeWindowSizeFlag    = "--window-size"
	chromeUserDataDirFlag   = "--user-data-dir"
	chromeResolution        = "1920,1080"
)

var (
	flags = []string{
		"--no-sandbox",
		"--headless",
		"--disable-gpu",
		"--hide-scrollbars",
		"--mute-audio",
		"--enable-automation",
		"--disable-web-security",
		"--disable-session-crashed-bubble",
		"--disable-breakpad",
		"--disable-sync",
		"--no-first-run",
		"--use-mock-keychain",
		"--keep-alive-for-test",
		"--disable-popup-blocking",
		"--disable-extensions",
		"--disable-component-extensions-with-background-pages",
		"--disable-hang-monitor",
		"--disable-features=site-per-process,TranslateUI",
		"--disable-translate",
		"--disable-background-networking",
		"--enable-features=NetworkService,NetworkServiceInProcess",
		"--disable-background-timer-throttling",
		"--disable-backgrounding-occluded-windows",
		"--disable-client-side-phishing-detection",
		"--disable-default-apps",
		"--disable-dev-shm-usage",
		"--disable-ipc-flooding-protection",
		"--disable-prompt-on-repost",
		"--disable-renderer-backgrounding",
		"--force-color-profile=srgb",
		"--metrics-recording-only",
		"--safebrowsing-disable-auto-update",
		"--password-store=basic",
		"--no-startup-window",
		fmt.Sprintf("%s=%s", chromeWindowSizeFlag, chromeResolution),
	}

	reserved = []string{chromeDebuggingPortFlag, chromeUserDataDirFlag}
)

func Defaults() []string {
	return slices.Clone(flags)
}

func Flags(dir string, options Options) []string {
	f := slices.DeleteFunc(slices.Clone(flags), options.IgnoreDefaultArgs.ignores)

	extra := slices.Clone(options.Args)
	if v := options.DefaultViewport; v != nil {
		extra = append(extra, fmt.Sprintf("%s=%d,%d", chromeWindowSizeFlag, v.Width, v.Height))
	}

	for _, flag := range extra {
		name := flagName(flag)
		if slices.Contains(reserved, name) {
			continue
		}

		if i := slices.IndexFunc(f, func(d string) bool { return flagName(d) == name }); i >= 0 {
			f[i] = flag
		} else {
			f = append(f, flag)
		}
	}

	return append(f,
		fmt.Sprintf("%s=%s", chromeDebuggingPortFlag, "0"),
		fmt.Sprintf("%s=%s", chromeUserDataDirFlag, dir),
	)
}

func flagName(flag string) string {
	name, _, _ := strings.Cut(flag, "=")
	return name
}
