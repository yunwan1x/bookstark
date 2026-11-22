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

	app := application.New(application.Options{
		Name:        "BookStark",
		Description: "BookStark local and remote workspaces",
		Assets:      application.AssetOptions{Handler: nativeAssetHandler(launcher)},
		OnShutdown: func() {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			_ = server.Shutdown(ctx)
		},
	})
	configureNativeWindow(app, launcher)
	return app.Run()
}
