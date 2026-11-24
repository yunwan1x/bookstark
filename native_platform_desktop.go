//go:build wails && !android && !dev

package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

func nativeDataDir() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "BookStark"), nil
}

const nativeMainWindowName = "bookstark-main"

// Our pages use the narrow BookStark bridge rather than loading Wails' full
// frontend runtime. ExecJS still needs its ready notification, including on the
// workspace chooser and remote pages, or close/save scripts remain queued.
const nativeDesktopReadyJS = `(function(){if(window!==window.top)return;var b=window.chrome&&window.chrome.webview||window.webkit&&window.webkit.messageHandlers.external;if(b&&typeof b.postMessage==='function')b.postMessage('wails:runtime:ready')})()`

func nativeLauncherBeforeApp() bool { return false }

func nativeInstanceID(dir string) string {
	absolute, err := filepath.Abs(dir)
	if err == nil {
		dir = absolute
	}
	return fmt.Sprintf("com.bookstark.gui.profile_%x", sha256.Sum256([]byte(filepath.Clean(dir))))
}

func configureNativeApplication(options *application.Options, dir string, restorer *nativeWindowRestorer) {
	options.Windows.WebviewUserDataPath = filepath.Join(dir, "webview")
	options.SingleInstance = &application.SingleInstanceOptions{
		UniqueID:               nativeInstanceID(dir),
		OnSecondInstanceLaunch: func(application.SecondInstanceData) { restorer.activate() },
	}
}

func configureNativeWindow(app *application.App, launcher *launcher, capabilities *nativeCapabilities, restorer *nativeWindowRestorer) {
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
			window.ExecJS("window.BookStarkHost ? BookStarkHost.navigate(function(){location.href=" + strconv.Quote(launcher.startURL()+"?choose=1") + "}) : location.assign(" + strconv.Quote(launcher.startURL()+"?choose=1") + ")")
		}
	})
	app.Menu.Set(menu)
	restorer.configure(func() application.Window {
		window, _ := app.Window.GetByName(nativeMainWindowName)
		return window
	}, func() application.Window {
		token := rand.Text()
		proof, _ := json.Marshal(token)
		window := app.Window.NewWithOptions(application.WebviewWindowOptions{
			Name:  nativeMainWindowName,
			Title: "BookStark", Width: 1280, Height: 850, MinWidth: 390, MinHeight: 560,
			URL:     launcher.startURL(),
			JS:      nativeDesktopReadyJS + ";if(window===top){if(!window.__BookStarkFrameToken)Object.defineProperty(window,'__BookStarkFrameToken',{value:" + string(proof) + "});window.dispatchEvent(new Event('bookstark:frame-ready'));}",
			Windows: application.WindowsWindow{Menu: menu},
			KeyBindings: map[string]func(application.Window){
				"Alt+Left": func(w application.Window) {
					w.ExecJS("window.BookStarkHost ? BookStarkHost.navigate(function(){history.back()}) : history.back()")
				},
				"Alt+Right": func(w application.Window) {
					w.ExecJS("window.BookStarkHost ? BookStarkHost.navigate(function(){history.forward()}) : history.forward()")
				},
				"Ctrl+Shift+L": func(window application.Window) {
					window.ExecJS("window.BookStarkHost ? BookStarkHost.navigate(function(){location.href=" + strconv.Quote(launcher.startURL()+"?choose=1") + "}) : location.assign(" + strconv.Quote(launcher.startURL()+"?choose=1") + ")")
				},
			},
		})
		capabilities.mu.Lock()
		capabilities.frameTokens[window.ID()] = token
		capabilities.mu.Unlock()
		capabilities.guardClose(window)
		return window
	})
	app.Event.OnApplicationEvent(events.Mac.ApplicationShouldHandleReopen, func(*application.ApplicationEvent) {
		restorer.activate()
	})
	restorer.activate()
}

func nativeAssetHandler(_ *launcher) http.Handler { return http.NotFoundHandler() }

func openNativeExternalURL(app *application.App, address string) error {
	return app.Browser.OpenURL(address)
}
