package worldtv

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const SettingKey = "world_tv_state"

var ErrBusy = errors.New("正在拉取，请完成后再操作")

type Config struct {
	Source        string `json:"source"`
	Enabled       bool   `json:"enabled"`
	IntervalHours int    `json:"intervalHours"`
}
type State struct {
	Config      Config    `json:"config"`
	LastAttempt time.Time `json:"lastAttempt"`
	LastSuccess time.Time `json:"lastSuccess"`
	NextRun     time.Time `json:"nextRun"`
	Error       string    `json:"error"`
	Count       int       `json:"count"`
	DurationMS  int64     `json:"durationMs"`
	Running     bool      `json:"running"`
}
type Store interface {
	Load() (string, error)
	Save(string) error
}
type Manager struct {
	mu          sync.Mutex
	store       Store
	path        string
	client      *http.Client
	state       State
	initialized bool
}

func New(store Store, path string, client *http.Client) *Manager {
	if client == nil {
		client = NewHTTPClient()
	}
	return &Manager{store: store, path: path, client: client}
}
func (m *Manager) catalog() (Catalog, error) {
	var c Catalog
	b, e := os.ReadFile(m.path)
	if e != nil {
		return c, e
	}
	e = json.Unmarshal(b, &c)
	return c, e
}
func (m *Manager) initLocked() error {
	if m.initialized {
		return nil
	}
	raw, e := m.store.Load()
	if e != nil {
		return e
	}
	if raw != "" {
		if e = json.Unmarshal([]byte(raw), &m.state); e != nil {
			return errors.New("世界电视配置损坏")
		}
		if e = ValidateConfig(m.state.Config); e != nil {
			return e
		}
		m.state.Running = false
	} else {
		m.state.Config = Config{Source: DefaultSource, IntervalHours: 6}
		// Adopt the legacy file and its six-hour schedule once. Fresh installs stay off.
		if c, e := m.catalog(); e == nil && len(c.Channels) > 0 && c.Source == DefaultSource {
			m.state.Config.Enabled = true
			m.state.LastSuccess = c.CheckedAt
			m.state.LastAttempt = c.CheckedAt
			m.state.Count = len(c.Channels)
			m.state.NextRun = c.CheckedAt.Add(6 * time.Hour)
		}
		if e = m.persistLocked(); e != nil {
			return e
		}
	}
	m.initialized = true
	return nil
}
func (m *Manager) persistLocked() error {
	b, e := json.Marshal(m.state)
	if e != nil {
		return e
	}
	return m.store.Save(string(b))
}
func ValidateConfig(c Config) error {
	if e := ValidateSource(c.Source); e != nil {
		return e
	}
	if c.IntervalHours != 6 && c.IntervalHours != 12 && c.IntervalHours != 24 {
		return errors.New("拉取间隔须为 6、12 或 24 小时")
	}
	return nil
}
func (m *Manager) Snapshot() (State, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	e := m.initLocked()
	return m.state, e
}
func (m *Manager) Catalog() (Catalog, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	c, e := m.catalog()
	if os.IsNotExist(e) {
		return Catalog{Channels: []Channel{}}, nil
	}
	return c, e
}
func (m *Manager) Configure(c Config) (State, error) {
	if e := ValidateConfig(c); e != nil {
		return State{}, e
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if e := m.initLocked(); e != nil {
		return m.state, e
	}
	if m.state.Running {
		return m.state, ErrBusy
	}
	old := m.state
	m.state.Config = c
	if c != old.Config {
		m.state.NextRun = time.Time{}
		if c.Enabled {
			m.state.NextRun = time.Now().UTC().Add(time.Duration(c.IntervalHours) * time.Hour)
		}
	}
	if e := m.persistLocked(); e != nil {
		m.state = old
		return old, e
	}
	return m.state, nil
}
func (m *Manager) Run(ctx context.Context, dueOnly bool) error {
	m.mu.Lock()
	if e := m.initLocked(); e != nil {
		m.mu.Unlock()
		return e
	}
	now := time.Now().UTC()
	if m.state.Running {
		m.mu.Unlock()
		return ErrBusy
	}
	if dueOnly && (!m.state.Config.Enabled || m.state.NextRun.After(now)) {
		m.mu.Unlock()
		return nil
	}
	cfg := m.state.Config
	m.state.Running = true
	m.state.LastAttempt = now
	m.mu.Unlock()
	started := time.Now()
	c, e := m.fetch(ctx, cfg.Source)
	m.mu.Lock()
	defer m.mu.Unlock()
	m.state.Running = false
	m.state.DurationMS = time.Since(started).Milliseconds()
	m.state.Error = ""
	if e != nil {
		m.state.Error = e.Error()
	} else {
		m.state.LastSuccess = c.CheckedAt
		m.state.Count = len(c.Channels)
	}
	m.state.NextRun = time.Time{}
	if cfg.Enabled {
		m.state.NextRun = time.Now().UTC().Add(time.Duration(cfg.IntervalHours) * time.Hour)
	}
	if persistErr := m.persistLocked(); persistErr != nil {
		return fmt.Errorf("保存拉取状态失败: %w", persistErr)
	}
	return e
}
func (m *Manager) fetch(ctx context.Context, source string) (Catalog, error) {
	var empty Catalog
	if e := ValidateSource(source); e != nil {
		return empty, e
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	req, e := http.NewRequestWithContext(ctx, http.MethodGet, source, nil)
	if e != nil {
		return empty, e
	}
	req.Header.Set("User-Agent", "BookStark-WorldTV/2.0")
	old, oldErr := m.catalog()
	same := oldErr == nil && old.Source == source && len(old.Channels) > 0
	if same && old.ETag != "" {
		req.Header.Set("If-None-Match", old.ETag)
	}
	resp, e := m.client.Do(req)
	if e != nil {
		return empty, errors.New("订阅请求失败，请检查公网 HTTPS 地址和网络连接")
	}
	defer resp.Body.Close()
	now := time.Now().UTC()
	if resp.StatusCode == http.StatusNotModified && same {
		old.CheckedAt = now
		return old, atomicCatalog(m.path, old)
	}
	if resp.StatusCode != http.StatusOK {
		return empty, fmt.Errorf("订阅服务器返回 HTTP %d", resp.StatusCode)
	}
	body, e := io.ReadAll(io.LimitReader(resp.Body, MaxBytes+1))
	if e != nil {
		return empty, errors.New("订阅内容读取失败")
	}
	rows, e := Parse(body)
	if e != nil {
		return empty, e
	}
	// The existing upstream is large. A tiny response likely means a partial file.
	if source == DefaultSource && len(rows) < 100 {
		return empty, errors.New("订阅列表不完整（少于 100 个频道），保留现有列表")
	}
	sum := sha256.Sum256(body)
	c := Catalog{1, source, now, now, hex.EncodeToString(sum[:]), resp.Header.Get("ETag"), rows}
	if same && old.Revision == c.Revision {
		c.UpdatedAt = old.UpdatedAt
	}
	return c, atomicCatalog(m.path, c)
}
func atomicCatalog(path string, c Catalog) error {
	if e := os.MkdirAll(filepath.Dir(path), 0755); e != nil {
		return e
	}
	f, e := os.CreateTemp(filepath.Dir(path), ".worldtv-*")
	if e != nil {
		return e
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if e = json.NewEncoder(f).Encode(c); e != nil {
		return e
	}
	if e = f.Chmod(0644); e != nil {
		return e
	}
	if e = f.Sync(); e != nil {
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	return os.Rename(f.Name(), path)
}

// Start returns a stop function which waits for any in-flight scheduled pull.
func (m *Manager) Start(onError func(error)) func() {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		tick := time.NewTicker(30 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-tick.C:
				if e := m.Run(ctx, true); e != nil && !errors.Is(e, ErrBusy) && ctx.Err() == nil {
					onError(e)
				}
			}
		}
	}()
	return func() { cancel(); <-done }
}
