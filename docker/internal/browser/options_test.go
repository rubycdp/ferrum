package browser

import (
	"encoding/base64"
	"slices"
	"testing"
)

func TestParseOptions(t *testing.T) {
	launch := `{"args":["--accept-lang=de-DE"],"defaultViewport":{"width":1280,"height":720},"ignoreDefaultArgs":["--headless"],"headless":false}`

	for name, input := range map[string]string{
		"json":       launch,
		"base64":     base64.StdEncoding.EncodeToString([]byte(launch)),
		"base64 url": base64.RawURLEncoding.EncodeToString([]byte(launch)),
	} {
		t.Run(name, func(t *testing.T) {
			options, err := ParseOptions(input)
			if err != nil {
				t.Fatal(err)
			}

			if !slices.Equal(options.Args, []string{"--accept-lang=de-DE"}) {
				t.Errorf("args = %v", options.Args)
			}
			if v := options.DefaultViewport; v == nil || v.Width != 1280 || v.Height != 720 {
				t.Errorf("defaultViewport = %+v", v)
			}
			if !slices.Equal(options.IgnoreDefaultArgs.Args, []string{"--headless"}) {
				t.Errorf("ignoreDefaultArgs = %+v", options.IgnoreDefaultArgs)
			}
		})
	}
}

func TestParseOptionsIgnoreAllDefaultArgs(t *testing.T) {
	options, err := ParseOptions(`{"ignoreDefaultArgs":true}`)
	if err != nil {
		t.Fatal(err)
	}

	if !options.IgnoreDefaultArgs.All {
		t.Error("expected all default args to be ignored")
	}
}

func TestParseOptionsErrors(t *testing.T) {
	for name, input := range map[string]string{
		"not json or base64": "%%%",
		"broken json":        `{"args":`,
		"wrong type":         `{"args":"--foo"}`,
		"empty viewport":     `{"defaultViewport":{"width":0,"height":720}}`,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseOptions(input); err == nil {
				t.Error("expected an error")
			}
		})
	}
}

func TestFlags(t *testing.T) {
	t.Run("defaults", func(t *testing.T) {
		f := Flags("/tmp/profile", Options{})

		if !slices.Equal(f[:len(flags)], flags) {
			t.Errorf("defaults changed: %v", f)
		}
		if !slices.Equal(f[len(flags):], []string{"--remote-debugging-port=0", "--user-data-dir=/tmp/profile"}) {
			t.Errorf("managed flags = %v", f[len(flags):])
		}
	})

	t.Run("args replace defaults by name and add the rest", func(t *testing.T) {
		f := Flags("/tmp/profile", Options{Args: []string{"--window-size=800,600", "--accept-lang=de-DE"}})

		if !slices.Contains(f, "--window-size=800,600") || slices.Contains(f, "--window-size=1024,768") {
			t.Errorf("window size not replaced: %v", f)
		}
		if !slices.Contains(f, "--accept-lang=de-DE") {
			t.Errorf("flag not added: %v", f)
		}
	})

	t.Run("defaultViewport becomes the window size", func(t *testing.T) {
		f := Flags("/tmp/profile", Options{DefaultViewport: &Viewport{Width: 1280, Height: 720}})

		if !slices.Contains(f, "--window-size=1280,720") || slices.Contains(f, "--window-size=1024,768") {
			t.Errorf("window size not replaced: %v", f)
		}
	})

	t.Run("managed flags can't be overridden", func(t *testing.T) {
		f := Flags("/tmp/profile", Options{
			Args:              []string{"--remote-debugging-port=9222", "--user-data-dir=/elsewhere"},
			IgnoreDefaultArgs: IgnoredArgs{All: true},
		})

		if !slices.Equal(f, []string{"--remote-debugging-port=0", "--user-data-dir=/tmp/profile"}) {
			t.Errorf("flags = %v", f)
		}
	})

	t.Run("ignoreDefaultArgs drops by full flag or name", func(t *testing.T) {
		f := Flags("/tmp/profile", Options{IgnoreDefaultArgs: IgnoredArgs{Args: []string{"--headless", "--disable-features"}}})

		for _, flag := range f {
			if flagName(flag) == "--headless" || flagName(flag) == "--disable-features" {
				t.Errorf("%s not dropped", flag)
			}
		}
		if len(f) != len(flags) {
			t.Errorf("expected %d flags, got %d", len(flags), len(f))
		}
	})
}

func TestHeadful(t *testing.T) {
	for launch, headful := range map[string]bool{
		`{}`:                   false,
		`{"headless":true}`:    false,
		`{"headless":"new"}`:   false,
		`{"headless":"shell"}`: false,
		`{"headless":false}`:   true,
	} {
		options, err := ParseOptions(launch)
		if err != nil {
			t.Fatal(err)
		}

		if options.Headful() != headful {
			t.Errorf("%s: headful = %v, want %v", launch, options.Headful(), headful)
		}

		if f := Flags("/tmp/profile", options); slices.Contains(f, "--headless") == headful {
			t.Errorf("%s: flags = %v", launch, f)
		}
	}
}

func TestWindowSize(t *testing.T) {
	if w, h := windowSize(Flags("/tmp/profile", Options{})); w != 1024 || h != 768 {
		t.Errorf("default = %dx%d", w, h)
	}
	if w, h := windowSize(Flags("/tmp/profile", Options{DefaultViewport: &Viewport{Width: 800, Height: 600}})); w != 800 || h != 600 {
		t.Errorf("viewport = %dx%d", w, h)
	}
	if w, h := windowSize([]string{"--window-size=bogus"}); w != 1024 || h != 768 {
		t.Errorf("invalid = %dx%d", w, h)
	}
}
