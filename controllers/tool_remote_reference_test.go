package controllers

import (
	"bookstark/conf"
	"bookstark/models"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestToolRemoteReferencesDownloadOriginalResources(t *testing.T) {
	conf.LoadDefaults()
	dir := t.TempDir()
	if err := models.InitDB(filepath.Join(dir, "main.db")); err != nil {
		t.Fatal(err)
	}
	if err := models.InitWebDAVDB(filepath.Join(dir, "files.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { models.DB.Close(); models.DB = nil; models.WebDAVDB.Close(); models.WebDAVDB = nil })
	tool := marketTool{ID: 7, Title: "Referenced tool", Description: "Original files", Source: "reference-source", Revision: strings.Repeat("b", 64), Content: `<script type="module" src="/static/original.js"></script><link rel="stylesheet" href="/static/original.css">`, ToolMetadata: models.ToolMetadata{Version: "1.0.0", Distribution: "references", Access: "login", Permissions: models.ToolPermissions{ReadFiles: true}}}
	mode := ""
	resourceReads := 0
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Cookie") != "" {
			t.Error("workspace cookie forwarded")
		}
		switch r.URL.Path {
		case "/api/tool-market":
			item := tool
			item.Content = ""
			json.NewEncoder(w).Encode(map[string]any{"tools": []marketTool{item}})
		case "/api/tool-market/7":
			if r.Header.Get("Authorization") != "Market reference-session" {
				w.WriteHeader(401)
				return
			}
			item := tool
			if r.URL.Query().Get("metadata") == "1" {
				item.Content = ""
			}
			switch mode {
			case "inline-content":
				item.Content = "<h1>Changed after consent</h1>"
			case "policy":
				item.Permissions.Network = true
			case "downgrade":
				item.Distribution = ""
			case "unversioned":
				item.Distribution, item.Version, item.Hash = "", "", ""
			case "full-content":
				if r.URL.Query().Get("metadata") != "1" {
					item.Content = "<h1>Changed full response</h1>"
				}
			}
			json.NewEncoder(w).Encode(item)
		case "/static/original.js", "/static/dependency.js", "/static/original.css", "/upload-files/original.svg":
			resourceReads++
			if r.Header.Get("Authorization") != "" {
				t.Error("market token forwarded to a resource")
			}
			data := map[string]string{"/static/original.js": `import {value} from './dependency.js';window.originalValue=value;`, "/static/dependency.js": `export const value="current-original";`, "/static/original.css": `body{background:url('/upload-files/original.svg')}`, "/upload-files/original.svg": `<svg xmlns="http://www.w3.org/2000/svg"/>`}
			if strings.HasSuffix(r.URL.Path, ".css") {
				w.Header().Set("Content-Type", "text/css")
			} else {
				w.Header().Set("Content-Type", "text/javascript")
			}
			w.Write([]byte(data[r.URL.Path]))
		default:
			t.Errorf("unexpected resource/archive request: %s", r.URL.Path)
			w.WriteHeader(404)
		}
	}))
	defer remote.Close()
	tool.ResourceBase = remote.URL + "/shares/reference-source"
	var err error
	tool.Hash, err = referenceDigest(tool)
	if err != nil {
		t.Fatal(err)
	}
	stored, err := models.EncryptContent(conf.App.JWTSecret, "reference-session")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = models.DB.Exec("INSERT INTO md_tool_market_credentials(member_id,url,account,token) VALUES(1,?,'remote-user',?)", remote.URL+"/market", stored); err != nil {
		t.Fatal(err)
	}
	r := gin.New()
	r.Use(func(c *gin.Context) { c.Set("memberID", int64(1)) })
	r.POST("/api/tool-sources", RemoteToolCatalog)
	r.PUT("/api/tool-installs/:id", InstallMarketTool(r))
	r.GET("/api/tool-assets/:instance/:epoch/*filepath", ServeToolAsset)
	call := func(method, path, body string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		r.ServeHTTP(w, req)
		return w
	}
	w := call("POST", "/api/tool-sources", `{"server":"`+remote.URL+`/market"}`)
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	var catalog struct {
		Tools []marketTool `json:"tools"`
	}
	json.Unmarshal(w.Body.Bytes(), &catalog)
	if len(catalog.Tools) != 1 || resourceReads != 0 {
		t.Fatal("browsing downloaded tool resources")
	}
	id := catalog.Tools[0].ID
	if _, _, err := remoteTool(context.Background(), 1, id, false); err != nil || resourceReads != 0 {
		t.Fatalf("metadata downloaded resources: %v", err)
	}
	w = call("PUT", "/api/tool-installs/"+strconv.FormatInt(id, 10), `{"revision":"`+tool.Revision+`","hash":"`+tool.Hash+`"}`)
	if w.Code != 200 || resourceReads != 4 {
		t.Fatalf("reference install: %d %s, resources=%d", w.Code, w.Body.String(), resourceReads)
	}
	for _, value := range []string{"inline-content", "policy", "downgrade", "unversioned", "full-content"} {
		mode = value
		if _, _, err := remoteTool(context.Background(), 1, id); err == nil {
			t.Fatalf("accepted tampered %s manifest", value)
		}
	}
	if _, _, err := remoteTool(context.Background(), 2, id); err == nil {
		t.Fatal("cross-account source access")
	}
	remote.Close()
	raw, _ := models.GetInstalledToolContent(1, id)
	content, _ := models.DecodeContentForType("html", raw)
	paths := regexp.MustCompile(`/api/tool-assets/[^"\s<>]+`).FindAllString(content, -1)
	if len(paths) != 2 {
		t.Fatalf("resource URLs not localized: %s", content)
	}
	for _, p := range paths {
		if w := call("GET", p, ""); w.Code != 200 {
			t.Fatalf("installed resource depended on market: %d", w.Code)
		}
	}
}
