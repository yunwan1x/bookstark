//go:build wails && android && !dev

package main

import (
	"errors"
	"net/http"
	"path/filepath"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func init() {
	application.RegisterAndroidMain(main)
}

func nativeDataDir() (string, error) {
	dir := application.Android.StoragePath()
	if !filepath.IsAbs(dir) {
		return "", errors.New("Android app storage is unavailable")
	}
	return filepath.Join(dir, "bookstark"), nil
}

func configureNativeWindow(app *application.App, _ *launcher) {
	app.Window.NewWithOptions(application.WebviewWindowOptions{Title: "BookStark"})
}

func nativeAssetHandler(l *launcher) http.Handler { return http.HandlerFunc(l.webviewBootstrap) }
