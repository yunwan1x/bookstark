package controllers_test

import (
	"bookstark/models"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestNewsAdminValidationAndPublicCache(t *testing.T) {
	r, token := initAssetControllerTest(t)
	cfg := models.DefaultNewsConfig()
	bad := cfg
	bad.FetchMinutes = 1
	if w := adminAssetRequest(r, token, "PUT", "/api/admin/news/config", bad); w.Code != 400 {
		t.Fatal(w.Code, w.Body.String())
	}
	for _, n := range []int{0, -1, 1001} {
		bad = cfg
		bad.MaxPerCategory = n
		if w := adminAssetRequest(r, token, "PUT", "/api/admin/news/config", bad); w.Code != 400 {
			t.Fatal("invalid category limit accepted", n, w.Code)
		}
	}
	if w := adminAssetRequest(r, token, "PUT", "/api/admin/news/config", cfg); w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if w := adminAssetRequest(r, token, "PUT", "/api/admin/settings", map[string]string{"news_config": "{}"}); w.Code != 400 {
		t.Fatal("bypassed config validation", w.Code)
	}
	_, e := models.DB.Exec(`INSERT INTO md_news_sources(id,url,name,category,language,enabled,error) VALUES(1,'https://example.com/rss','Public source','ai-tools','zh',1,'private operational error'),(2,'https://private.example/rss','Hidden source','other','en',0,'')`)
	if e != nil {
		t.Fatal(e)
	}
	for i := 1; i <= 2; i++ {
		_, e = models.DB.Exec(`INSERT INTO md_news_articles(source_id,item_key,url,title,summary,published,created) VALUES(?,?,?,?,?,?,?)`, i, "id", []string{"https://example.com/a", "https://private.example/a"}[i-1], []string{"Visible title", "Hidden title"}[i-1], "Safe text", time.Now().Unix(), time.Now().Unix())
		if e != nil {
			t.Fatal(e)
		}
	}
	w := adminAssetRequest(r, "", "GET", "/shares", nil)
	if w.Code != 200 || !strings.Contains(w.Body.String(), "Visible title") || strings.Contains(w.Body.String(), "Hidden title") {
		t.Fatal("incorrect public news", w.Code)
	}
	w = adminAssetRequest(r, "", "GET", "/api/news/sources", nil)
	if w.Code != 200 || strings.Contains(w.Body.String(), "Hidden source") || strings.Contains(w.Body.String(), "private operational error") || strings.Contains(w.Body.String(), "example.com/rss") {
		t.Fatal("source metadata exposure", w.Body.String())
	}
	w = adminAssetRequest(r, token, "PATCH", "/api/admin/news/sources", map[string]any{"ids": []int64{1}, "enabled": false, "category": "design"})
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	sources, _ := models.NewsSources(false)
	if sources[0].Name == "Public source" && sources[0].Enabled {
		t.Fatal("not disabled")
	}
	w = adminAssetRequest(r, "", "GET", "/shares", nil)
	if strings.Contains(w.Body.String(), "Visible title") {
		t.Fatal("disabled news visible")
	}
	w = adminAssetRequest(r, token, "GET", "/api/admin/news", nil)
	var body map[string]any
	if e = json.Unmarshal(w.Body.Bytes(), &body); e != nil || w.Code != 200 {
		t.Fatal("admin payload", e)
	}
}
