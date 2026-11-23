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

func runNative() error {
	dir, err := nativeDataDir()
	if err != nil {
		return err
	}
	launcher, listener, err := newLauncher(dir)
	if err != nil {
		return err
	}
	server := newLauncherServer(launcher)
	defer server.Close()
	go func() {
		if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Printf("BookStark launcher: %v", err)
		}
	}()

	capabilities := newNativeCapabilities()
	var app *application.App
	app = application.New(application.Options{
		Name:        "BookStark",
		Description: "BookStark local and remote workspaces",
		Assets:      application.AssetOptions{Handler: nativeAssetHandler(launcher)},
		RawMessageHandler: func(window application.Window, message string, _ *application.OriginInfo) {
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
			_ = server.Shutdown(ctx)
		},
	})
	capabilities.app = app
	configureNativeWindow(app, launcher, capabilities)
	return app.Run()
}
