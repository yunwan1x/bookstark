package controllers

import (
	"bookstark/conf"
	"bookstark/models"
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

func TestToolRemoteInstallDownloadsToWorkspace(t *testing.T) {
	conf.LoadDefaults()
	dir := t.TempDir()
	if err := models.InitDB(filepath.Join(dir, "main.db")); err != nil {
		t.Fatal(err)
	}
	if err := models.InitWebDAVDB(filepath.Join(dir, "files.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { models.DB.Close(); models.DB = nil; models.WebDAVDB.Close(); models.WebDAVDB = nil })
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Cookie") != "" || r.Header.Get("Authorization") != "" {
			t.Error("credentials forwarded")
		}
		switch r.URL.Path {
		case "/api/tool-market":
			json.NewEncoder(w).Encode(map[string]any{"tools": []marketTool{{ID: 7, Title: "Remote", Source: "remote", Revision: "v1"}}})
		case "/api/tool-market/7":
			json.NewEncoder(w).Encode(marketTool{ID: 7, Title: "Remote", Source: "remote", Revision: "v1", Content: `<script src="/static/remote.js"></script>`})
		case "/static/remote.js":
			w.Header().Set("Content-Type", "text/javascript")
			w.Write([]byte(`window.remoteInstalled=true;`))
		default:
			w.WriteHeader(404)
		}
	}))
	defer remote.Close()
	original := toolClientFactory
	toolClientFactory = func() *http.Client { return remote.Client() }
	t.Cleanup(func() { toolClientFactory = original })
	r := gin.New()
	r.Use(func(c *gin.Context) { c.Set("memberID", int64(1)) })
	r.POST("/api/tool-sources", RemoteToolCatalog)
	r.PUT("/api/tool-installs/:id", InstallMarketTool(r))
	r.GET("/api/tool-assets/:instance/:epoch/*filepath", ServeToolAsset)
	request := func(method, p, body string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(method, p, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		r.ServeHTTP(w, req)
		return w
	}
	w := request("POST", "/api/tool-sources", `{"server":"`+remote.URL+`"}`)
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	var catalog struct {
		Tools []marketTool `json:"tools"`
	}
	json.Unmarshal(w.Body.Bytes(), &catalog)
	if len(catalog.Tools) != 1 || catalog.Tools[0].ID >= 0 {
		t.Fatal("remote ID not isolated")
	}
	id := catalog.Tools[0].ID
	w = request("PUT", "/api/tool-installs/"+strconv.FormatInt(id, 10), `{"revision":"v1"}`)
	if w.Code != 200 {
		t.Fatalf("remote install %d: %s", w.Code, w.Body.String())
	}
	remote.Close()
	raw, err := models.GetInstalledToolContent(1, id)
	if err != nil {
		t.Fatal(err)
	}
	content, _ := models.DecodeContentForType("html", raw)
	p := regexp.MustCompile(`/api/tool-assets/[^"\s<>]+`).FindString(content)
	if p == "" {
		t.Fatal("remote URL not localized")
	}
	w = request("GET", p, "")
	if w.Code != 200 || !strings.Contains(w.Body.String(), "remoteInstalled") {
		t.Fatalf("local copy unavailable after remote shutdown: %d %s", w.Code, w.Body.String())
	}
	// Another account cannot resolve this server's mapped installation ID.
	if _, _, err := remoteTool(context.Background(), 2, id); err == nil {
		t.Fatal("cross-account source access")
	}
}
func TestToolResourceFetchBlocksPrivateNetworks(t *testing.T) {
	for _, raw := range []string{"http://127.0.0.1:1234/file.js", "http://[::1]/file.js", "http://169.254.169.254/latest/meta-data/", "file:///etc/passwd", "http://user:password@example.com/file.js"} {
		u, _ := url.Parse(raw)
		if _, _, err := fetchToolURL(context.Background(), u); err == nil {
			t.Fatalf("unsafe fetch accepted: %s", raw)
		}
	}
}
