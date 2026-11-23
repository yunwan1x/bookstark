//go:build wails && !dev

package main

import (
	"sync"
	"testing"

	"github.com/wailsapp/wails/v3/pkg/application"
)

type lifecycleWindow struct {
	application.Window
	minimised                bool
	shown, focused, restored int
}

func (w *lifecycleWindow) Show() application.Window { w.shown++; return w }
func (w *lifecycleWindow) Focus()                   { w.focused++ }
func (w *lifecycleWindow) IsMinimised() bool        { return w.minimised }
func (w *lifecycleWindow) UnMinimise()              { w.minimised = false; w.restored++ }

func TestNativeWindowActivation(t *testing.T) {
	r := &nativeWindowRestorer{}
	r.activate() // Early notifications must not prevent normal startup.
	var current *lifecycleWindow
	created := 0
	r.configure(func() application.Window {
		if current == nil {
			return nil
		}
		return current
	}, func() application.Window { created++; current = &lifecycleWindow{}; return current })
	r.activate()
	first := current
	r.activate()
	if created != 1 || first.shown != 2 || first.focused != 2 || first.restored != 0 {
		t.Fatalf("normal activation recreated or resized window: created=%d window=%+v", created, first)
	}
	first.minimised = true
	r.activate()
	if first.minimised || first.restored != 1 || created != 1 {
		t.Fatal("minimised window not restored")
	}
	current = nil // Wails removes destroyed windows from its window manager.
	r.activate()
	if created != 2 || current == first || current.focused != 1 {
		t.Fatal("closed main window not recreated")
	}
	current = nil
	var calls sync.WaitGroup
	for i := 0; i < 20; i++ {
		calls.Add(1)
		go func() { defer calls.Done(); r.activate() }()
	}
	calls.Wait()
	if created != 3 {
		t.Fatalf("concurrent activation created %d windows", created-2)
	}
}
