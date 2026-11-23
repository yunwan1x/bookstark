//go:build wails && !android && !dev

package main

import (
	"path/filepath"
	"testing"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func TestNativeDesktopSingleInstance(t *testing.T) {
	dir := t.TempDir()
	var options application.Options
	restorer := &nativeWindowRestorer{}
	window := &lifecycleWindow{}
	restorer.configure(func() application.Window { return window }, func() application.Window { t.Fatal("unexpected extra window"); return nil })
	configureNativeApplication(&options, dir, restorer)
	if options.SingleInstance == nil || options.SingleInstance.UniqueID == "" || nativeLauncherBeforeApp() {
		t.Fatal("desktop must arbitrate before binding launcher port")
	}
	if options.SingleInstance.UniqueID != nativeInstanceID(filepath.Join(dir, "unused", "..")) {
		t.Fatal("equivalent profile paths use different instance IDs")
	}
	if options.SingleInstance.UniqueID == nativeInstanceID(filepath.Join(dir, "other")) {
		t.Fatal("independent profiles share an instance ID")
	}
	options.SingleInstance.OnSecondInstanceLaunch(application.SecondInstanceData{})
	if window.focused != 1 {
		t.Fatal("second launch did not activate main window")
	}
}
