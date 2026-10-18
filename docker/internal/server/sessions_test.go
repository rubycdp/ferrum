package server

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/rubycdp/ferrum/docker/internal/browser"
)

func newSessions(t *testing.T, config SessionsConfig) *Sessions {
	t.Helper()

	config.Binary = os.Args[0]
	if config.Concurrent == 0 {
		config.Concurrent = 4
	}

	s := NewSessions(config)
	t.Cleanup(s.StopAll)

	return s
}

func TestSessionsStartAndStop(t *testing.T) {
	s := newSessions(t, SessionsConfig{})

	b, err := s.Start(context.Background(), browser.Options{})
	if err != nil {
		t.Fatal(err)
	}
	if len(s.Browsers()) != 1 {
		t.Fatalf("browsers = %d, want 1", len(s.Browsers()))
	}

	s.Stop(b, "test")

	if len(s.Browsers()) != 0 {
		t.Fatalf("browsers = %d, want 0", len(s.Browsers()))
	}
	select {
	case <-b.Done():
	default:
		t.Fatal("browser process still running")
	}
}

func TestSessionsStartFailureFreesTheSlot(t *testing.T) {
	s := newSessions(t, SessionsConfig{Concurrent: 1})

	if _, err := s.Start(context.Background(), browser.Options{Args: []string{"--fake-exit"}}); err == nil {
		t.Fatal("expected an error")
	}

	if _, err := s.Start(context.Background(), browser.Options{}); err != nil {
		t.Fatalf("slot not freed: %v", err)
	}
}

func TestSessionsClaim(t *testing.T) {
	s := newSessions(t, SessionsConfig{})

	b, err := s.Start(context.Background(), browser.Options{})
	if err != nil {
		t.Fatal(err)
	}
	s.Reserve(b)

	if got := s.Claim(b.ID); got != b {
		t.Fatalf("claim = %v, want %v", got, b)
	}
	if got := s.Claim(b.ID); got != nil {
		t.Fatal("claimed twice")
	}
}

func TestSessionsClaimOrStart(t *testing.T) {
	s := newSessions(t, SessionsConfig{})
	ctx := context.Background()

	pending, err := s.Start(ctx, browser.Options{})
	if err != nil {
		t.Fatal(err)
	}
	s.Reserve(pending)

	t.Run("starts a browser without an id", func(t *testing.T) {
		b, err := s.ClaimOrStart(ctx, "", browser.Options{})
		if err != nil {
			t.Fatal(err)
		}
		if b == pending {
			t.Fatal("claimed a pending browser without its id")
		}
	})

	t.Run("claims the pending browser by id", func(t *testing.T) {
		b, err := s.ClaimOrStart(ctx, pending.ID, browser.Options{})
		if err != nil {
			t.Fatal(err)
		}
		if b != pending {
			t.Fatal("started a new browser instead of claiming the pending one")
		}
	})

	t.Run("starts a browser when the id is no longer pending", func(t *testing.T) {
		b, err := s.ClaimOrStart(ctx, pending.ID, browser.Options{})
		if err != nil {
			t.Fatal(err)
		}
		if b == pending {
			t.Fatal("claimed the same browser twice")
		}
	})
}

func TestSessionsUnclaimedBrowserIsStopped(t *testing.T) {
	s := newSessions(t, SessionsConfig{ClaimTimeout: 50 * time.Millisecond})

	b, err := s.Start(context.Background(), browser.Options{})
	if err != nil {
		t.Fatal(err)
	}
	s.Reserve(b)

	eventually(t, func() bool { return len(s.Browsers()) == 0 })
	<-b.Done()
}

func TestSessionsExitedBrowserIsRemoved(t *testing.T) {
	s := newSessions(t, SessionsConfig{})

	b, err := s.Start(context.Background(), browser.Options{})
	if err != nil {
		t.Fatal(err)
	}
	b.Stop()

	eventually(t, func() bool { return len(s.Browsers()) == 0 })
}

func TestSessionsLimits(t *testing.T) {
	ctx := context.Background()

	t.Run("rejects when the queue is full", func(t *testing.T) {
		s := newSessions(t, SessionsConfig{Concurrent: 1, Queued: 0})

		if _, err := s.Start(ctx, browser.Options{}); err != nil {
			t.Fatal(err)
		}
		if _, err := s.Start(ctx, browser.Options{}); !errors.Is(err, ErrQueueFull) {
			t.Fatalf("err = %v, want ErrQueueFull", err)
		}
	})

	t.Run("queued start waits for a free slot", func(t *testing.T) {
		s := newSessions(t, SessionsConfig{Concurrent: 1, Queued: 1})

		first, err := s.Start(ctx, browser.Options{})
		if err != nil {
			t.Fatal(err)
		}

		started := make(chan error, 1)
		go func() {
			_, err := s.Start(ctx, browser.Options{})
			started <- err
		}()

		select {
		case err := <-started:
			t.Fatalf("started without a free slot: %v", err)
		case <-time.After(200 * time.Millisecond):
		}

		s.Stop(first, "test")

		if err := <-started; err != nil {
			t.Fatal(err)
		}
	})

	t.Run("queued start gives up when the request is canceled", func(t *testing.T) {
		s := newSessions(t, SessionsConfig{Concurrent: 1, Queued: 1})

		if _, err := s.Start(ctx, browser.Options{}); err != nil {
			t.Fatal(err)
		}

		canceled, cancel := context.WithTimeout(ctx, 50*time.Millisecond)
		defer cancel()

		if _, err := s.Start(canceled, browser.Options{}); !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("err = %v, want DeadlineExceeded", err)
		}
	})

	t.Run("queued start gives up on shutdown", func(t *testing.T) {
		s := newSessions(t, SessionsConfig{Concurrent: 1, Queued: 1})

		if _, err := s.Start(ctx, browser.Options{}); err != nil {
			t.Fatal(err)
		}

		started := make(chan error, 1)
		go func() {
			_, err := s.Start(ctx, browser.Options{})
			started <- err
		}()
		time.Sleep(50 * time.Millisecond)

		s.StopAll()

		if err := <-started; !errors.Is(err, ErrClosed) {
			t.Fatalf("err = %v, want ErrClosed", err)
		}
	})
}
