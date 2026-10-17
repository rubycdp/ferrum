package browser

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"
)

type Options struct {
	Args              []string    `json:"args"`
	DefaultViewport   *Viewport   `json:"defaultViewport"`
	IgnoreDefaultArgs IgnoredArgs `json:"ignoreDefaultArgs"`
	Headless          any         `json:"headless"`
}

func (o Options) Headful() bool {
	headless, ok := o.Headless.(bool)
	return ok && !headless
}

type Viewport struct {
	Width  int `json:"width"`
	Height int `json:"height"`
}

type IgnoredArgs struct {
	All  bool
	Args []string
}

func (i *IgnoredArgs) UnmarshalJSON(data []byte) error {
	if err := json.Unmarshal(data, &i.All); err == nil {
		return nil
	}

	return json.Unmarshal(data, &i.Args)
}

func (i IgnoredArgs) ignores(flag string) bool {
	if i.All {
		return true
	}

	for _, arg := range i.Args {
		if arg == flag || arg == flagName(flag) {
			return true
		}
	}

	return false
}

func ParseOptions(launch string) (Options, error) {
	var options Options
	if launch == "" {
		return options, nil
	}

	data := []byte(launch)
	if !strings.HasPrefix(strings.TrimSpace(launch), "{") {
		decoded, err := decodeBase64(launch)
		if err != nil {
			return options, fmt.Errorf("launch is neither JSON nor base64: %w", err)
		}
		data = decoded
	}

	if err := json.Unmarshal(data, &options); err != nil {
		return options, fmt.Errorf("invalid launch options: %w", err)
	}

	if v := options.DefaultViewport; v != nil && (v.Width <= 0 || v.Height <= 0) {
		return options, fmt.Errorf("invalid defaultViewport %dx%d", v.Width, v.Height)
	}

	return options, nil
}

func decodeBase64(s string) ([]byte, error) {
	for _, encoding := range []*base64.Encoding{base64.StdEncoding, base64.URLEncoding, base64.RawStdEncoding, base64.RawURLEncoding} {
		if data, err := encoding.DecodeString(s); err == nil {
			return data, nil
		}
	}

	return nil, base64.CorruptInputError(0)
}
