package server

import (
	"log/slog"
	"sync"
	"time"

	"github.com/rubycdp/ferrum/docker/internal/browser"
)

const (
	startTimeout = 30 * time.Second
	claimTimeout = 30 * time.Second
)

type Sessions struct {
	binary string

	mu       sync.Mutex
	browsers map[string]*browser.Browser
	pending  map[string]reservation
}

type reservation struct {
	browser *browser.Browser
	options string
}

func NewSessions(binary string) *Sessions {
	return &Sessions{
		binary:   binary,
		browsers: make(map[string]*browser.Browser),
		pending:  make(map[string]reservation),
	}
}

func (s *Sessions) Start() (*browser.Browser, error) {
	b, err := browser.Start(s.binary, startTimeout)
	if err != nil {
		return nil, err
	}

	s.mu.Lock()
	s.browsers[b.ID] = b
	s.mu.Unlock()

	go func() {
		<-b.Done()
		s.Stop(b)
	}()

	return b, nil
}

func (s *Sessions) Reserve(b *browser.Browser, options string) {
	s.mu.Lock()
	s.pending[b.ID] = reservation{browser: b, options: options}
	s.mu.Unlock()

	time.AfterFunc(claimTimeout, func() {
		if s.Claim(b.ID) != nil {
			slog.Warn("browser was never claimed, stopping", "id", b.ID, "timeout", claimTimeout)
			s.Stop(b)
		}
	})
}

func (s *Sessions) Claim(id string) *browser.Browser {
	s.mu.Lock()
	defer s.mu.Unlock()

	r := s.pending[id]
	delete(s.pending, id)

	return r.browser
}

func (s *Sessions) ClaimOrStart(options string) (*browser.Browser, error) {
	s.mu.Lock()
	for id, r := range s.pending {
		if r.options == options {
			delete(s.pending, id)
			s.mu.Unlock()
			return r.browser, nil
		}
	}
	s.mu.Unlock()

	return s.Start()
}

func (s *Sessions) Stop(b *browser.Browser) {
	s.mu.Lock()
	delete(s.browsers, b.ID)
	delete(s.pending, b.ID)
	s.mu.Unlock()

	b.Stop()
}

func (s *Sessions) StopAll() {
	s.mu.Lock()
	browsers := make([]*browser.Browser, 0, len(s.browsers))
	for _, b := range s.browsers {
		browsers = append(browsers, b)
	}
	s.mu.Unlock()

	var wg sync.WaitGroup
	for _, b := range browsers {
		wg.Go(func() { s.Stop(b) })
	}
	wg.Wait()
}
