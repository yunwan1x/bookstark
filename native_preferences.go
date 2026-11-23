//go:build wails

package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

const defaultLocalAdminPassword = "wy19870714"

type workspacePreferences struct {
	Ask    bool   `json:"ask"`
	Last   string `json:"last"`
	Remote string `json:"remote"`
}

func (l *launcher) preferences() (workspacePreferences, error) {
	var p workspacePreferences
	data, err := os.ReadFile(filepath.Join(l.dir, "startup.json"))
	if errors.Is(err, os.ErrNotExist) {
		return p, nil
	}
	if err != nil {
		return p, err
	}
	err = json.Unmarshal(data, &p)
	return p, err
}

func (l *launcher) savePreferences(p workspacePreferences) error {
	data, err := json.Marshal(p)
	if err != nil {
		return err
	}
	return writePrivateFile(filepath.Join(l.dir, "startup.json"), data)
}

func (l *launcher) rememberWorkspace(kind, remote string, ask *bool) error {
	l.settingsMu.Lock()
	defer l.settingsMu.Unlock()
	p, err := l.preferences()
	if err != nil {
		return err
	}
	p.Last = kind
	if kind == "remote" {
		p.Remote = remote
	}
	if ask != nil {
		p.Ask = *ask
	}
	return l.savePreferences(p)
}

func probeWorkspace(address string) error {
	client := &http.Client{Timeout: 6 * time.Second, CheckRedirect: func(_ *http.Request, via []*http.Request) error {
		if len(via) >= 5 {
			return errors.New("too many redirects")
		}
		return nil
	}}
	response, err := client.Get(address)
	if err != nil {
		return errors.New("native.startup.unreachable")
	}
	defer response.Body.Close()
	if response.StatusCode >= 500 || response.StatusCode == 404 {
		return errors.New("native.startup.unreachable")
	}
	return nil
}

func (l *launcher) resumeWorkspace(w http.ResponseWriter, r *http.Request) {
	p, err := l.preferences()
	if err == nil {
		switch p.Last {
		case "local":
			_, err = l.startLocal("", "")
		case "remote":
			p.Remote, err = validateServerURL(p.Remote)
			if err == nil {
				err = probeWorkspace(p.Remote)
			}
		default:
			err = errors.New("native.startup.choose")
		}
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	if err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"error": "native.startup.unreachable"})
		return
	}
	target := "/"
	if p.Last == "remote" {
		target = p.Remote
	}
	json.NewEncoder(w).Encode(map[string]string{"url": target})
}
