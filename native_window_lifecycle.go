//go:build wails && !dev

package main

import (
	"github.com/wailsapp/wails/v3/pkg/application"
	"sync"
)

// All desktop activation paths use the same named main window. Serializing the
// lookup and creation prevents simultaneous launches from creating two windows.
type nativeWindowRestorer struct {
	mu     sync.Mutex
	find   func() application.Window
	create func() application.Window
}

func (r *nativeWindowRestorer) configure(find, create func() application.Window) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.find, r.create = find, create
}

func (r *nativeWindowRestorer) activate() {
	r.mu.Lock()
	defer r.mu.Unlock()
	// A launch during startup needs no extra window; startup will create it.
	if r.find == nil || r.create == nil {
		return
	}
	window := r.find()
	if window == nil {
		window = r.create()
	}
	window.Show()
	if window.IsMinimised() {
		window.UnMinimise()
	}
	window.Focus()
}
