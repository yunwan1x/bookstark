package worldtv

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type memoryStore struct {
	mu  sync.Mutex
	raw string
	err error
}

func (s *memoryStore) Load() (string, error) { s.mu.Lock(); defer s.mu.Unlock(); return s.raw, s.err }
func (s *memoryStore) Save(v string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.err != nil {
		return s.err
	}
	s.raw = v
	return nil
}

type transportFunc func(*http.Request) (*http.Response, error)

func (f transportFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

const playlist = "#EXTM3U\n#EXTINF:-1 tvg-id=\"News.jp\" tvg-name=\"News\" tvg-country=\"JP\" group-title=\"Japan\",News\nhttps://media.example/live.m3u8\n"

func response(code int, body string) *http.Response {
	return &http.Response{StatusCode: code, Header: http.Header{"Etag": []string{"v1"}}, Body: io.NopCloser(strings.NewReader(body))}
}
func testManager(t *testing.T, fn transportFunc) (*Manager, *memoryStore) {
	t.Helper()
	s := &memoryStore{}
	m := New(s, filepath.Join(t.TempDir(), "worldtv", "channels.json"), &http.Client{Transport: fn})
	return m, s
}
func TestParseStableIDsAndSafeURLs(t *testing.T) {
	a, e := Parse([]byte(playlist))
	if e != nil || len(a) != 1 {
		t.Fatal(a, e)
	}
	b, e := Parse([]byte(strings.ReplaceAll(playlist, "media.example", "changed.example")))
	if e != nil || a[0].ID != b[0].ID {
		t.Fatal("unstable IDs", e)
	}
	b, e = Parse([]byte(playlist + "#EXTINF:-1 tvg-id=\"News.jp\",Duplicate\nhttps://other.example/live\n#EXTINF:-1,Unsafe\njavascript:alert(1)\n#EXTINF:-1 tvg-name=\"Video\" group-title=\"a,b\",Video Ⓨ\nhttps://www.youtube.com/@test/live\n"))
	if e != nil || len(b) != 2 || !b[1].External || b[1].Group != "a,b" {
		t.Fatal(b, e)
	}
	for _, invalid := range []string{"<html>error</html>", "#EXTM3U\n", "#EXTM3U\n#EXTINF:-1,Bad\nfile:///etc/passwd"} {
		if _, e := Parse([]byte(invalid)); e == nil {
			t.Fatal("accepted invalid playlist")
		}
	}
	if _, e := Parse(make([]byte, MaxBytes+1)); e == nil {
		t.Fatal("unbounded playlist")
	}
}
func TestRunPersistsScheduleAndFailureKeepsCatalog(t *testing.T) {
	code, body, calls := 200, playlist, 0
	m, s := testManager(t, func(r *http.Request) (*http.Response, error) { calls++; return response(code, body), nil })
	cfg := Config{"https://feed.example/list.m3u", true, 6}
	if _, e := m.Configure(cfg); e != nil {
		t.Fatal(e)
	}
	if e := m.Run(context.Background(), true); e != nil || calls != 0 {
		t.Fatal("ran before due", e)
	}
	if e := m.Run(context.Background(), false); e != nil {
		t.Fatal(e)
	}
	state, _ := m.Snapshot()
	if state.Count != 1 || state.NextRun.Before(time.Now().Add(5*time.Hour)) {
		t.Fatal(state)
	}
	before, _ := os.ReadFile(m.path)
	code = 502
	if e := m.Run(context.Background(), false); e == nil {
		t.Fatal("expected failure")
	}
	after, _ := os.ReadFile(m.path)
	if string(before) != string(after) {
		t.Fatal("failed pull replaced catalog")
	}
	restarted := New(s, m.path, m.client)
	state, e := restarted.Snapshot()
	if e != nil || state.Error == "" || state.LastSuccess.IsZero() || state.Config != cfg || state.NextRun.IsZero() {
		t.Fatal(state, e)
	}
	if _, e := restarted.Configure(Config{cfg.Source, false, 12}); e != nil {
		t.Fatal(e)
	}
	count := calls
	if e := restarted.Run(context.Background(), true); e != nil || calls != count {
		t.Fatal("disabled schedule ran", e)
	}
	state, _ = restarted.Snapshot()
	if !state.NextRun.IsZero() {
		t.Fatal("disabled task has next run")
	}
	code = 200
	body = "#EXTM3U\n"
	if e := m.Run(context.Background(), false); e == nil {
		t.Fatal("empty replaced catalog")
	}
}
func TestETag304AndSourceChange(t *testing.T) {
	request := 0
	m, _ := testManager(t, func(r *http.Request) (*http.Response, error) {
		request++
		if request == 2 {
			if r.Header.Get("If-None-Match") != "v1" {
				t.Error("missing validator")
			}
			return response(304, ""), nil
		}
		if request == 3 && r.Header.Get("If-None-Match") != "" {
			t.Error("old validator leaked to new subscription")
		}
		return response(200, playlist), nil
	})
	m.Configure(Config{"https://a.example/list", false, 6})
	if e := m.Run(context.Background(), false); e != nil {
		t.Fatal(e)
	}
	old, _ := m.Catalog()
	if e := m.Run(context.Background(), false); e != nil {
		t.Fatal(e)
	}
	updated, _ := m.Catalog()
	if !updated.UpdatedAt.Equal(old.UpdatedAt) || !updated.CheckedAt.After(old.CheckedAt) {
		t.Fatal("304 timestamps")
	}
	m.Configure(Config{"https://b.example/list", false, 6})
	if e := m.Run(context.Background(), false); e != nil {
		t.Fatal(e)
	}
}
func TestConcurrentPullAndSaveBlocked(t *testing.T) {
	entered, release := make(chan struct{}), make(chan struct{})
	m, _ := testManager(t, func(r *http.Request) (*http.Response, error) {
		close(entered)
		<-release
		return response(200, playlist), nil
	})
	m.Configure(Config{"https://feed.example/list", true, 6})
	done := make(chan error, 1)
	go func() { done <- m.Run(context.Background(), false) }()
	<-entered
	if e := m.Run(context.Background(), false); !errors.Is(e, ErrBusy) {
		t.Error(e)
	}
	if _, e := m.Configure(Config{"https://other.example/list", false, 12}); !errors.Is(e, ErrBusy) {
		t.Error(e)
	}
	state, _ := m.Snapshot()
	if !state.Running {
		t.Error("not marked running")
	}
	close(release)
	if e := <-done; e != nil {
		t.Fatal(e)
	}
}
func TestLegacyMigrationAndDueRun(t *testing.T) {
	calls := 0
	m, s := testManager(t, func(r *http.Request) (*http.Response, error) { calls++; return response(502, ""), nil })
	rows, _ := Parse([]byte(playlist))
	stamp := time.Now().Add(-7 * time.Hour).UTC()
	if e := atomicCatalog(m.path, Catalog{Schema: 1, Source: DefaultSource, CheckedAt: stamp, UpdatedAt: stamp, Channels: rows}); e != nil {
		t.Fatal(e)
	}
	state, e := m.Snapshot()
	if e != nil || !state.Config.Enabled || state.Count != 1 || state.NextRun.After(time.Now()) {
		t.Fatal(state, e)
	}
	if e = m.Run(context.Background(), true); e == nil || calls != 1 {
		t.Fatal("did not run overdue migration", e)
	}
	m.Configure(Config{DefaultSource, false, 6})
	other := New(s, m.path, m.client)
	state, _ = other.Snapshot()
	if state.Config.Enabled {
		t.Fatal("migration overwrote saved disable")
	}
}
func TestPersistenceFailureDoesNotChangeConfig(t *testing.T) {
	m, s := testManager(t, nil)
	original, e := m.Snapshot()
	if e != nil {
		t.Fatal(e)
	}
	s.err = errors.New("disk full")
	if _, e = m.Configure(Config{"https://new.example/list", true, 12}); e == nil {
		t.Fatal("expected store error")
	}
	current, _ := m.Snapshot()
	if current.Config != original.Config {
		t.Fatal("unsaved config became active")
	}
}
func TestSourceAndDialSafety(t *testing.T) {
	for _, s := range []string{"http://feed.example/list", "https://127.0.0.1/list", "https://[::1]/list", "https://169.254.169.254/list", "https://user:pass@feed.example/list", "https://localhost/list", "https://100.64.0.1/list"} {
		if ValidateSource(s) == nil {
			t.Errorf("accepted %s", s)
		}
	}
	for _, ip := range []string{"127.0.0.1", "10.0.0.1", "::ffff:192.168.1.1", "0.0.0.1", "100.64.1.1"} {
		if publicIP(net.ParseIP(ip)) {
			t.Fatal(ip)
		}
	}
	if !publicIP(net.ParseIP("8.8.8.8")) || !publicIP(net.ParseIP("2606:4700:4700::1111")) {
		t.Fatal("rejected public IP")
	}
	client := NewHTTPClient()
	if _, e := client.Get("https://127.0.0.1:1/list"); e == nil {
		t.Fatal("dialed loopback")
	}
	req, _ := http.NewRequest("GET", "http://example.com/list", nil)
	if e := client.CheckRedirect(req, []*http.Request{{}}); e == nil {
		t.Fatal("redirect downgraded to http")
	}
	for _, hours := range []int{0, -1, 1, 168} {
		if ValidateConfig(Config{DefaultSource, true, hours}) == nil {
			t.Fatal("bad period")
		}
	}
}
