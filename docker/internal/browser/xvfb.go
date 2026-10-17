package browser

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

const (
	xvfbBinary  = "Xvfb"
	xvfbTimeout = 10 * time.Second
)

type xvfb struct {
	cmd     *exec.Cmd
	display string
	done    chan struct{}
}

func needsXvfb(options Options) bool {
	if !options.Headful() || os.Getenv("DISPLAY") != "" {
		return false
	}

	_, err := exec.LookPath(xvfbBinary)
	return err == nil
}

func startXvfb(width, height int) (*xvfb, error) {
	reader, writer, err := os.Pipe()
	if err != nil {
		return nil, fmt.Errorf("create xvfb display pipe: %w", err)
	}
	defer reader.Close()

	cmd := exec.Command(xvfbBinary, "-displayfd", "3", "-screen", "0", fmt.Sprintf("%dx%dx24", width, height), "-nolisten", "tcp")
	cmd.ExtraFiles = []*os.File{writer}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	err = cmd.Start()
	writer.Close()
	if err != nil {
		return nil, fmt.Errorf("start xvfb: %w", err)
	}

	x := &xvfb{cmd: cmd, done: make(chan struct{})}
	go func() {
		cmd.Wait()
		close(x.done)
	}()

	display := make(chan string, 1)
	go func() {
		line, _ := bufio.NewReader(reader).ReadString('\n')
		display <- strings.TrimSpace(line)
	}()

	select {
	case d := <-display:
		if d == "" {
			x.stop()
			return nil, errors.New("xvfb exited before it was ready")
		}
		x.display = ":" + d
		return x, nil
	case <-time.After(xvfbTimeout):
		x.stop()
		return nil, fmt.Errorf("xvfb did not start within %s", xvfbTimeout)
	}
}

func (x *xvfb) stop() {
	pgid := x.cmd.Process.Pid
	syscall.Kill(-pgid, syscall.SIGTERM)

	select {
	case <-x.done:
	case <-time.After(killTimeout):
		syscall.Kill(-pgid, syscall.SIGKILL)
		<-x.done
	}
}
