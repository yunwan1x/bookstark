//go:build wails && !android && !dev

package main

import (
	"net/http"
	"os"
	"path/filepath"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func nativeDataDir() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "BookStark"), nil
}

func configureNativeWindow(app *application.App, launcher *launcher) {
	menu := app.NewMenu()
	connection := menu.AddSubmenu("工作区")
	connection.Add("切换工作区").OnClick(func(_ *application.Context) {
		if window := app.Window.Current(); window != nil {
			window.SetURL(launcher.startURL())
		}
	})
	app.Menu.Set(menu)
	app.Window.NewWithOptions(application.WebviewWindowOptions{
		Title: "BookStark", Width: 1280, Height: 850, MinWidth: 390, MinHeight: 560,
		URL:     launcher.startURL(),
		Windows: application.WindowsWindow{Menu: menu},
		KeyBindings: map[string]func(application.Window){
			"Ctrl+Shift+L": func(window application.Window) { window.SetURL(launcher.startURL()) },
		},
	})
}

func nativeAssetHandler(_ *launcher) http.Handler { return http.NotFoundHandler() }
