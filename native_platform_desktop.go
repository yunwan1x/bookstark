//go:build wails && !android && !dev

package main

import (
	"net/http"
	"os"
	"path/filepath"
	"strconv"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func nativeDataDir() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "BookStark"), nil
}

func configureNativeWindow(app *application.App, launcher *launcher, capabilities *nativeCapabilities) {
	menu := app.NewMenu()
	connection := menu.AddSubmenu("工作区 / Workspace")
	connection.Add("返回 / Back").OnClick(func(_ *application.Context) {
		if w := app.Window.Current(); w != nil {
			w.ExecJS("window.BookStarkHost ? BookStarkHost.navigate(function(){history.back()}) : history.back()")
		}
	})
	connection.Add("前进 / Forward").OnClick(func(_ *application.Context) {
		if w := app.Window.Current(); w != nil {
			w.ExecJS("window.BookStarkHost ? BookStarkHost.navigate(function(){history.forward()}) : history.forward()")
		}
	})
	connection.Add("切换工作区").OnClick(func(_ *application.Context) {
		if window := app.Window.Current(); window != nil {
			window.ExecJS("window.BookStarkHost ? BookStarkHost.navigate(function(){location.href=" + strconv.Quote(launcher.startURL()) + "}) : location.assign(" + strconv.Quote(launcher.startURL()) + ")")
		}
	})
	app.Menu.Set(menu)
	window := app.Window.NewWithOptions(application.WebviewWindowOptions{
		Title: "BookStark", Width: 1280, Height: 850, MinWidth: 390, MinHeight: 560,
		URL:     launcher.startURL(),
		Windows: application.WindowsWindow{Menu: menu},
		KeyBindings: map[string]func(application.Window){
			"Alt+Left": func(w application.Window) {
				w.ExecJS("window.BookStarkHost ? BookStarkHost.navigate(function(){history.back()}) : history.back()")
			},
			"Alt+Right": func(w application.Window) {
				w.ExecJS("window.BookStarkHost ? BookStarkHost.navigate(function(){history.forward()}) : history.forward()")
			},
			"Ctrl+Shift+L": func(window application.Window) {
				window.ExecJS("window.BookStarkHost ? BookStarkHost.navigate(function(){location.href=" + strconv.Quote(launcher.startURL()) + "}) : location.assign(" + strconv.Quote(launcher.startURL()) + ")")
			},
		},
	})
	capabilities.guardClose(window)
}

func nativeAssetHandler(_ *launcher) http.Handler { return http.NotFoundHandler() }

func openNativeExternalURL(app *application.App, address string) error {
	return app.Browser.OpenURL(address)
}
