package browser

import (
	"bufio"
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"os"
	"os/exec"
	"path"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"
)

const killTimeout = 5 * time.Second

var listeningPattern = regexp.MustCompile(`DevTools listening on (ws://\S+)`)

type Browser struct {
	ID     string
	Addr   string
	WSPath string

	cmd      *exec.Cmd
	xvfb     *xvfb
	dir      string
	done     chan struct{}
	stopOnce sync.Once
}

func Start(binary string, options Options, timeout time.Duration) (*Browser, error) {
	dir, err := os.MkdirTemp("", "chrome-")
	if err != nil {
		return nil, fmt.Errorf("create user data dir: %w", err)
	}

	flags := Flags(dir, options)
	cmd := exec.Command(binary, flags...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	var x *xvfb
	if needsXvfb(options) {
		if x, err = startXvfb(windowSize(flags)); err != nil {
			os.RemoveAll(dir)
			return nil, err
		}
		cmd.Env = append(os.Environ(), "DISPLAY="+x.display)
	}

	stderr, writer, err := os.Pipe()
	if err != nil {
		cleanup(x, dir)
		return nil, fmt.Errorf("create stderr pipe: %w", err)
	}
	cmd.Stderr = writer

	err = cmd.Start()
	writer.Close()
	if err != nil {
		stderr.Close()
		cleanup(x, dir)
		return nil, fmt.Errorf("start browser: %w", err)
	}

	b := &Browser{cmd: cmd, xvfb: x, dir: dir, done: make(chan struct{})}
	go b.wait()

	wsURL := make(chan string, 1)
	go b.readStderr(stderr, wsURL)

	select {
	case raw := <-wsURL:
		if err := b.setEndpoint(raw); err != nil {
			b.Stop()
			return nil, err
		}
		slog.Info("browser started", "pid", b.Pid(), "id", b.ID, "addr", b.Addr)
		return b, nil
	case <-b.done:
		b.Stop()
		return nil, errors.New("browser exited before it was ready")
	case <-time.After(timeout):
		b.Stop()
		return nil, fmt.Errorf("browser did not start within %s", timeout)
	}
}

func (b *Browser) Pid() int {
	return b.cmd.Process.Pid
}

func (b *Browser) Done() <-chan struct{} {
	return b.done
}

func (b *Browser) Stop() {
	b.stopOnce.Do(func() {
		pgid := b.Pid()
		syscall.Kill(-pgid, syscall.SIGTERM)

		select {
		case <-b.done:
		case <-time.After(killTimeout):
			slog.Warn("browser ignored SIGTERM, killing", "pid", pgid)
		}

		syscall.Kill(-pgid, syscall.SIGKILL)
		<-b.done

		if b.xvfb != nil {
			b.xvfb.stop()
		}

		if err := os.RemoveAll(b.dir); err != nil {
			slog.Warn("cannot remove user data dir", "dir", b.dir, "error", err)
		}

		slog.Info("browser stopped", "pid", pgid, "id", b.ID)
	})
}

func cleanup(x *xvfb, dir string) {
	if x != nil {
		x.stop()
	}
	os.RemoveAll(dir)
}

func (b *Browser) wait() {
	err := b.cmd.Wait()
	slog.Debug("browser exited", "pid", b.Pid(), "error", err)
	close(b.done)
}

func (b *Browser) readStderr(stderr *os.File, wsURL chan<- string) {
	defer stderr.Close()

	reader := bufio.NewReader(stderr)
	for {
		line, err := reader.ReadString('\n')
		if line = strings.TrimSpace(line); line != "" {
			if match := listeningPattern.FindStringSubmatch(line); match != nil {
				select {
				case wsURL <- match[1]:
				default:
				}
			} else {
				slog.Debug("browser stderr", "pid", b.Pid(), "line", line)
			}
		}
		if err != nil {
			return
		}
	}
}

func (b *Browser) setEndpoint(raw string) error {
	endpoint, err := url.Parse(raw)
	if err != nil {
		return fmt.Errorf("parse browser websocket url %q: %w", raw, err)
	}

	b.Addr = endpoint.Host
	b.WSPath = endpoint.Path
	b.ID = path.Base(endpoint.Path)

	return nil
}
