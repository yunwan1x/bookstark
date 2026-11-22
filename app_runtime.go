package main

import (
	"fmt"
	"log"
	"net/http"

	"bookstark/conf"
	"bookstark/models"
)

func initDatabases() error {
	if err := models.InitDB(conf.App.DBPath); err != nil {
		return fmt.Errorf("init db: %w", err)
	}
	if err := models.InitWebDAVDB(conf.App.WebDAVDBPath); err != nil {
		return fmt.Errorf("init webdav db: %w", err)
	}
	if err := models.InitShareCommentDB(); err != nil {
		return fmt.Errorf("init share comments db: %w", err)
	}
	// Backfill the built-in AI defaults without replacing user settings.
	if err := models.BackfillAIDefaults(); err != nil {
		log.Printf("backfill ai defaults: %v", err)
	}
	return nil
}

// headMethodFallback wraps a handler so that HEAD requests are routed
// to GET handlers. Gin's router does not fall back HEAD→GET automatically,
// causing HEAD to hit NoRoute and get redirected.
func headMethodFallback(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodHead {
			r.Method = http.MethodGet
			h.ServeHTTP(&headResponseWriter{ResponseWriter: w}, r)
			return
		}
		h.ServeHTTP(w, r)
	})
}

type headResponseWriter struct {
	http.ResponseWriter
}

func (w *headResponseWriter) Write(b []byte) (int, error) {
	return len(b), nil
}
