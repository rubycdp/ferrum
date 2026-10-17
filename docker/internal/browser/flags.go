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
	defaultWidth            = 1024
	defaultHeight           = 768
)

var (
	flags = []string{
		"--allow-pre-commit-input",
		"--disable-background-networking",
		"--disable-background-timer-throttling",
		"--disable-backgrounding-occluded-windows",
		"--disable-blink-features=AutomationControlled",
		"--disable-breakpad",
		"--disable-client-side-phishing-detection",
		"--disable-component-extensions-with-background-pages",
		"--disable-component-update",
		"--disable-crash-reporter",
		"--disable-default-apps",
		"--disable-dev-shm-usage",
		"--disable-extensions",
		"--disable-features=site-per-process,IsolateOrigins,TranslateUI,Translate,MacAppCodeSignClone,InterestFeedContentSuggestion,OptimizationHints,AcceptCHFrame,MediaRouter",
		"--disable-field-trial-config",
		"--disable-hang-monitor",
		"--disable-infobars",
		"--disable-ipc-flooding-protection",
		"--disable-popup-blocking",
		"--disable-prompt-on-repost",
		"--disable-renderer-backgrounding",
		"--disable-search-engine-choice-screen",
		"--disable-session-crashed-bubble",
		"--disable-site-isolation-trials",
		"--disable-smooth-scrolling",
		"--disable-sync",
		"--disable-translate",
		"--enable-automation",
		"--enable-features=NetworkService,NetworkServiceInProcess",
		"--force-color-profile=srgb",
		"--headless",
		"--hide-scrollbars",
		"--keep-alive-for-test",
		"--metrics-recording-only",
		"--mute-audio",
		"--no-crash-upload",
		"--no-default-browser-check",
		"--no-first-run",
		"--no-startup-window",
		"--password-store=basic",
		"--safebrowsing-disable-auto-update",
		"--use-mock-keychain",
		"--no-sandbox",
		"--disable-setuid-sandbox",
		fmt.Sprintf("%s=%d,%d", chromeWindowSizeFlag, defaultWidth, defaultHeight),
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
