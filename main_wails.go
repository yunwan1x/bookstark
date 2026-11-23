//go:build wails && !dev

package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"time"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func main() {
	if err := runNative(); err != nil {
		log.Fatal(err)
	}
}

func runNative() error { return runNativeWithOptions(nil) }

// The optional override lets integration tests exercise macOS-style lifetime on Linux.
func runNativeWithOptions(override func(*application.Options)) error {
	dir, err := nativeDataDir()
	if err != nil {
		return err
	}
	var launcher *launcher
	var server *http.Server
	startLauncher := func() error {
		l, listener, listenerErr := newLauncher(dir)
		if listenerErr != nil {
			return listenerErr
		}
		launcher = l
		server = newLauncherServer(launcher)
		go func() {
			if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
				log.Printf("BookStark launcher: %v", err)
			}
		}()
		return nil
	}
	// Android needs its bootstrap handler before application.New. Desktop must
	// arbitrate single-instance ownership before binding the persisted workspace port.
	if nativeLauncherBeforeApp() {
		if err := startLauncher(); err != nil {
			return err
		}
	}
	defer func() {
		if server != nil {
			_ = server.Close()
		}
	}()

	capabilities := newNativeCapabilities()
	var app *application.App
	restorer := &nativeWindowRestorer{}
	options := application.Options{
		Name:        "BookStark",
		Description: "BookStark local and remote workspaces",
		Assets:      application.AssetOptions{Handler: nativeAssetHandler(launcher)},
		RawMessageHandler: func(window application.Window, message string, origin *application.OriginInfo) {
			if capabilities.handleClient(window, message, origin) {
				return
			}
			capabilities.handle(window, message)
			if address, ok := nativeExternalURL(message); ok {
				if err := openNativeExternalURL(app, address); err != nil {
					log.Printf("BookStark open external link: %v", err)
				}
			}
		},
		ShouldQuit: capabilities.shouldQuit,
		OnShutdown: func() {
			capabilities.close()
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			if server != nil {
				_ = server.Shutdown(ctx)
			}
		},
	}
	configureNativeApplication(&options, dir, restorer)
	if override != nil {
		override(&options)
	}
	app = application.New(options)
	if launcher == nil {
		if err := startLauncher(); err != nil {
			return err
		}
	}
	capabilities.app = app
	capabilities.workspace = launcher
	configureNativeWindow(app, launcher, capabilities, restorer)
	return app.Run()
}
