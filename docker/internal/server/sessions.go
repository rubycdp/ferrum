package server

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"time"

	"github.com/rubycdp/ferrum/docker/internal/browser"
)

const (
	startTimeout = 30 * time.Second
	claimTimeout = 30 * time.Second
)

var (
	ErrQueueFull = errors.New("too many sessions")
	ErrClosed    = errors.New("shutting down")
)

type SessionsConfig struct {
	Binary       string
	Concurrent   int
	Queued       int
	ClaimTimeout time.Duration
}

type Sessions struct {
	binary       string
	queued       int
	claimTimeout time.Duration
	slots        chan struct{}
	closed       chan struct{}
	closeOnce    sync.Once

	mu       sync.Mutex
	waiting  int
	browsers map[string]*browser.Browser
	pending  map[string]*browser.Browser
}

func NewSessions(config SessionsConfig) *Sessions {
	if config.ClaimTimeout == 0 {
		config.ClaimTimeout = claimTimeout
	}

	return &Sessions{
		binary:       config.Binary,
		queued:       config.Queued,
		claimTimeout: config.ClaimTimeout,
		slots:        make(chan struct{}, max(config.Concurrent, 1)),
		closed:       make(chan struct{}),
		browsers:     make(map[string]*browser.Browser),
		pending:      make(map[string]*browser.Browser),
	}
}

func (s *Sessions) Start(ctx context.Context, options browser.Options) (*browser.Browser, error) {
	if err := s.acquire(ctx); err != nil {
		return nil, err
	}

	b, err := browser.Start(s.binary, options, startTimeout)
	if err != nil {
		s.release()
		return nil, err
	}

	s.mu.Lock()
	s.browsers[b.ID] = b
	s.mu.Unlock()

	if s.isClosed() {
		s.Stop(b, "shutdown")
		return nil, ErrClosed
	}

	go func() {
		<-b.Done()
		s.Stop(b, "browser exited")
	}()

	return b, nil
}

func (s *Sessions) Reserve(b *browser.Browser) {
	s.mu.Lock()
	s.pending[b.ID] = b
	s.mu.Unlock()

	time.AfterFunc(s.claimTimeout, func() {
		if s.Claim(b.ID) != nil {
			s.Stop(b, "never claimed")
		}
	})
}

func (s *Sessions) Claim(id string) *browser.Browser {
	s.mu.Lock()
	defer s.mu.Unlock()

	b := s.pending[id]
	delete(s.pending, id)

	return b
}

func (s *Sessions) ClaimOrStart(ctx context.Context, id string, options browser.Options) (*browser.Browser, error) {
	if b := s.Claim(id); b != nil {
		return b, nil
	}

	return s.Start(ctx, options)
}

func (s *Sessions) Browsers() []*browser.Browser {
	s.mu.Lock()
	defer s.mu.Unlock()

	browsers := make([]*browser.Browser, 0, len(s.browsers))
	for _, b := range s.browsers {
		browsers = append(browsers, b)
	}

	return browsers
}

func (s *Sessions) Stop(b *browser.Browser, reason string) {
	s.mu.Lock()
	_, running := s.browsers[b.ID]
	delete(s.browsers, b.ID)
	delete(s.pending, b.ID)
	s.mu.Unlock()

	if !running {
		return
	}

	b.Stop()
	s.release()
	slog.Info("session ended", "id", b.ID, "reason", reason)
}

func (s *Sessions) StopAll() {
	s.closeOnce.Do(func() { close(s.closed) })

	var wg sync.WaitGroup
	for _, b := range s.Browsers() {
		wg.Go(func() { s.Stop(b, "shutdown") })
	}
	wg.Wait()
}

func (s *Sessions) acquire(ctx context.Context) error {
	select {
	case <-s.closed:
		return ErrClosed
	case s.slots <- struct{}{}:
		return nil
	default:
	}

	s.mu.Lock()
	if s.waiting >= s.queued {
		s.mu.Unlock()
		return ErrQueueFull
	}
	s.waiting++
	s.mu.Unlock()

	defer func() {
		s.mu.Lock()
		s.waiting--
		s.mu.Unlock()
	}()

	select {
	case s.slots <- struct{}{}:
		if s.isClosed() {
			s.release()
			return ErrClosed
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	case <-s.closed:
		return ErrClosed
	}
}

func (s *Sessions) isClosed() bool {
	select {
	case <-s.closed:
		return true
	default:
		return false
	}
}

func (s *Sessions) release() {
	<-s.slots
}
