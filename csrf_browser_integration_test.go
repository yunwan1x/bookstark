package main

import (
	"io"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"bookstark/conf"
	"bookstark/models"
	"bookstark/routers"
	"github.com/gin-gonic/gin"
)

// Opt-in real-browser test; all databases and uploads live in a temporary directory.
func TestCSRFMutationBrowser(t *testing.T) {
	runIsolatedBrowser(t, "csrf_browser_test.cjs")
}

func TestHomeBrowser(t *testing.T) {
	runIsolatedBrowser(t, "home_browser_test.cjs")
}

func TestPWAHomeBrowser(t *testing.T) {
	runIsolatedBrowser(t, "pwa_production_smoke_test.cjs")
}

func runIsolatedBrowser(t *testing.T, script string) {
	if os.Getenv("BOOKSTARK_BROWSER_TEST") != "1" {
		t.Skip("set BOOKSTARK_BROWSER_TEST=1 and make playwright available to Node")
	}
	repo, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	writer := gin.DefaultWriter
	gin.DefaultWriter = io.Discard
	t.Cleanup(func() { gin.DefaultWriter = writer })
	t.Chdir(t.TempDir())
	conf.LoadDefaults()
	conf.App.DBPath = filepath.Join(t.TempDir(), "browser.db")
	conf.App.AdminAccount = "admin"
	conf.App.AdminPassword = "csrf-browser-test-only"
	conf.App.JWTSecret = "isolated-browser-test-secret"
	if err := models.InitDB(conf.App.DBPath); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = models.DB.Close(); models.DB = nil })
	if err := models.SetShareCommentDBPath(filepath.Join(t.TempDir(), "comments.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = models.CloseShareCommentDB(); _ = models.SetShareCommentDBPath("") })
	routers.EmbedFS.StaticFS = EmbedFS.StaticFS
	routers.EmbedFS.TemplateFS = EmbedFS.TemplateFS
	routers.EmbedFS.ConfFS = EmbedFS.ConfFS
	server := httptest.NewServer(routers.Setup())
	defer server.Close()
	cmd := exec.Command("node", filepath.Join(repo, script))
	cmd.Env = append(os.Environ(), "BOOKSTARK_TEST_ORIGIN="+server.URL, "BOOKSTARK_TEST_PASSWORD="+conf.App.AdminPassword)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		t.Fatal(err)
	}
}
