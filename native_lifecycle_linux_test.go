//go:build wails && linux && !android && !dev

package main

import (
	"fmt"
	"github.com/wailsapp/wails/v3/pkg/application"
	"os"
	"testing"
)

// GTK's main loop must run on the main goroutine, not a testing.T worker.
// The opt-in helper uses the production startup path with macOS-style lifetime.
func TestMain(m *testing.M) {
	if os.Getenv("BOOKSTARK_GUI_LIFECYCLE_HELPER") == "retained" {
		if err := runNativeWithOptions(func(options *application.Options) {
			options.Linux.DisableQuitOnLastWindowClosed = true
		}); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		os.Exit(0)
	}
	os.Exit(m.Run())
}
