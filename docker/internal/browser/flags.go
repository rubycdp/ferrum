package browser

import (
	"fmt"
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
	}
)

func Flags(dir string) []string {
	f := make([]string, len(flags))
	copy(f, flags)
	f = append(f, []string{
		fmt.Sprintf("%s=%s", chromeDebuggingPortFlag, "0"),
		fmt.Sprintf("%s=%s", chromeWindowSizeFlag, chromeResolution),
		fmt.Sprintf("%s=%s", chromeUserDataDirFlag, dir),
	}...)

	return f
}
