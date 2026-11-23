package main

import (
	"bookstark/conf"
	"bookstark/models"
	"bookstark/routers"
	"bookstark/services"
	"bookstark/services/worldtv"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Opt-in real-browser test; all databases and uploads live in a temporary directory.
func TestCSRFMutationBrowser(t *testing.T) {
	runIsolatedBrowser(t, "csrf_browser_test.cjs")
}

func TestProfileSettingsBrowser(t *testing.T) {
	runIsolatedBrowser(t, "profile_settings_browser_test.cjs")
}

func TestLoginPasswordBrowser(t *testing.T) {
	runIsolatedBrowser(t, "login_password_browser_test.cjs")
}

func TestHomeBrowser(t *testing.T) {
	runIsolatedBrowser(t, "home_browser_test.cjs")
}

func TestPWAHomeBrowser(t *testing.T) {
	runIsolatedBrowser(t, "pwa_production_smoke_test.cjs")
}

func runIsolatedBrowser(t *testing.T, script string, setup ...func(*testing.T)) {
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
	for _, prepare := range setup {
		prepare(t)
	}
	server := httptest.NewServer(routers.Setup())
	defer server.Close()
	cmd := exec.Command("node", filepath.Join(repo, "tests", "browser", script))
	cmd.Env = append(os.Environ(), "BOOKSTARK_TEST_ORIGIN="+server.URL, "BOOKSTARK_TEST_PASSWORD="+conf.App.AdminPassword)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		t.Fatal(err)
	}
}

func TestNativeCompatibilityBrowser(t *testing.T) {
	runIsolatedBrowser(t, "native_compat_browser_test.cjs")
}

func TestLocalToolsBrowser(t *testing.T) {
	runIsolatedBrowser(t, "local_tools_browser_test.cjs")
}

func TestNativeToolsNavigationBrowser(t *testing.T) {
	runIsolatedBrowser(t, "native_tools_navigation_browser_test.cjs", func(t *testing.T) {
		bookmark := &models.Bookmark{Title: "Native external bookmark", URL: "https://example.com/native-link?q=bookstark", MemberID: 1, IsPublic: true, NavVisible: true}
		if err := bookmark.Insert(); err != nil {
			t.Fatal(err)
		}
	})
}

type newsBrowserTransport struct{}

func (newsBrowserTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	body := `<rss><channel><item><title>Fetched fixture story</title><guid>fetched</guid><link>https://example.com/fetched</link><description><![CDATA[<p>Plain summary<img src="https://tracker.invalid/pixel"></p>]]></description></item></channel></rss>`
	if r.URL.Hostname() == "raw.githubusercontent.com" {
		body = `<opml><body><outline text="Imported source" xmlUrl="https://example.org/feed"/></body></opml>`
	}
	return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body))}, nil
}
func TestNewsWorkspaceBrowser(t *testing.T) {
	runIsolatedBrowser(t, "news_browser_test.cjs", func(t *testing.T) {
		old := services.NewsClient
		services.NewsClient = &http.Client{Transport: newsBrowserTransport{}}
		t.Cleanup(func() { services.NewsClient = old })
		for i := 1; i <= 3; i++ {
			enabled := i != 3
			_, err := models.DB.Exec(`INSERT INTO md_news_sources(id,url,name,category,language,enabled,last_success) VALUES(?,?,?,?,?,?,?)`, i, fmt.Sprintf("https://example.com/feed%d", i), []string{"Anthropic Research", "量子位", "Hidden Source"}[i-1], []string{"ai-research", "ai-tools", "other"}[i-1], []string{"en", "zh", "en"}[i-1], enabled, time.Now().Unix())
			if err != nil {
				t.Fatal(err)
			}
			_, err = models.DB.Exec(`INSERT INTO md_news_membership(source_id,repo_key) VALUES(?,?)`, i, "fixture/repo@main/feeds.opml")
			if err != nil {
				t.Fatal(err)
			}
		}
		for i := 0; i < 19; i++ {
			source := i%2 + 1
			if i == 18 {
				source = 3
			}
			_, err := models.DB.Exec(`INSERT INTO md_news_articles(source_id,item_key,url,title,summary,published,created) VALUES(?,?,?,?,?,?,?)`, source, fmt.Sprint(i), fmt.Sprintf("https://example.com/article/%d", i), fmt.Sprintf("News fixture %02d", i), "A safe excerpt <img src=x onerror=alert(1)> only.", time.Now().Unix()-int64(i*60), time.Now().Unix())
			if err != nil {
				t.Fatal(err)
			}
		}
	})
}

func TestPublicWorkspaceBrowser(t *testing.T) {
	runIsolatedBrowser(t, "public_workspace_browser_test.cjs", func(t *testing.T) {
		for i := 0; i < 17; i++ {
			blog := &models.Blog{BlogTitle: fmt.Sprintf("Workspace article %02d", i), BlogIdentify: fmt.Sprintf("workspace-%d", i), BlogType: "article", BlogContent: "A public knowledge resource.", MemberID: 1, Visibility: 1}
			if err := blog.Insert(); err != nil {
				t.Fatal(err)
			}
			if err := models.BindLabelsFromNames(blog.BlogID, "blog", "工具"); err != nil {
				t.Fatal(err)
			}
		}
		note := &models.Blog{BlogTitle: "Workspace note", BlogIdentify: "workspace-note", BlogType: "note", BlogContent: "**One idea at a time.**\n\n- Capture\n- Connect", MemberID: 1, Visibility: 1}
		if err := note.Insert(); err != nil {
			t.Fatal(err)
		}
		book := &models.Book{BookName: "Workspace book", Identify: "workspace-book", MemberID: 1, Description: "Knowledge, organized.", CreateTime: time.Now()}
		if err := book.Insert(); err != nil {
			t.Fatal(err)
		}
		if _, err := models.CreateShare("book", book.BookID, 1, ""); err != nil {
			t.Fatal(err)
		}
		for i, title := range []string{"投资认知—从市场机制到投资决策", "技术笔记", "设计手册"} {
			extra := &models.Book{BookName: title, Identify: fmt.Sprintf("widget-book-%d", i), MemberID: 1, Description: "记录实践中的思考与经验，从知识整理到日常应用。", CreateTime: time.Now()}
			if err := extra.Insert(); err != nil {
				t.Fatal(err)
			}
			if _, err := models.CreateShare("book", extra.BookID, 1, ""); err != nil {
				t.Fatal(err)
			}
		}

		bookmark := &models.Bookmark{Title: "Workspace bookmark", URL: "https://example.com/docs", Description: "Reference documentation", MemberID: 1, IsPublic: true}
		if err := bookmark.Insert(); err != nil {
			t.Fatal(err)
		}
	})
}

func TestWorldTVBrowser(t *testing.T) {
	runIsolatedBrowser(t, "world_tv_browser_test.cjs", func(t *testing.T) {
		path := filepath.Join(models.UploadBaseDir, "worldtv", "channels.json")
		if e := os.MkdirAll(filepath.Dir(path), 0755); e != nil {
			t.Fatal(e)
		}
		c := worldtv.Catalog{Schema: 1, Source: worldtv.DefaultSource, CheckedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(), Channels: []worldtv.Channel{
			{ID: "nhk", Name: "NHK WORLD-JAPAN", Country: "JP", Group: "Japan", URL: "https://media.example/nhk.m3u8", Language: "en"},
			{ID: "france", Name: "France 24", Country: "FR", Group: "France", URL: "https://media.example/france.m3u8", Language: "fr"},
			{ID: "video", Name: "<img src=x onerror=alert(1)>", Country: "JP", Group: "Japan", URL: "https://www.youtube.com/@test/live", External: true},
		}}
		b, _ := json.Marshal(c)
		if e := os.WriteFile(path, b, 0644); e != nil {
			t.Fatal(e)
		}
	})
}

func TestToolMarketBrowser(t *testing.T) {
	runIsolatedBrowser(t, "tool_market_browser_test.cjs", func(t *testing.T) {
		// A separate marketplace authenticates independently of the local workspace.
		revision := strings.Repeat("a", 64)
		content := `<h1>Remote tool installed</h1><script src="/static/remote-reference.js"></script>`
		var tool map[string]any
		remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			switch r.URL.Path {
			case "/market/index.json":
				json.NewEncoder(w).Encode(map[string]any{"protocol": 1, "name": "远端工具市场", "login_required": true})
			case "/api/tool-market":
				json.NewEncoder(w).Encode(map[string]any{"tools": []any{tool}})
			case "/market/login":
				var credentials struct {
					Account  string `json:"account"`
					Password string `json:"password"`
				}
				json.NewDecoder(r.Body).Decode(&credentials)
				if credentials.Account != "remote-user" || credentials.Password != "remote-password" {
					w.WriteHeader(401)
					json.NewEncoder(w).Encode(map[string]string{"error": "market_login_failed"})
					return
				}
				json.NewEncoder(w).Encode(map[string]string{"token": "fixture-remote-market-session", "account": "remote-user"})
			case "/api/tool-market/777":
				if r.Header.Get("Authorization") != "Market fixture-remote-market-session" {
					w.WriteHeader(401)
					json.NewEncoder(w).Encode(map[string]string{"error": "market_login_required"})
					return
				}
				item := make(map[string]any, len(tool))
				for key, value := range tool {
					item[key] = value
				}
				if r.URL.Query().Get("metadata") != "1" {
					item["content"] = content
				}
				json.NewEncoder(w).Encode(item)
			case "/static/remote-reference.js":
				if r.Header.Get("Authorization") != "" || r.Header.Get("Cookie") != "" {
					t.Error("market credentials forwarded to an original resource")
				}
				w.Header().Set("Content-Type", "text/javascript")
				w.Write([]byte("window.remoteReferenceDownloaded=true;"))
			default:
				w.WriteHeader(404)
			}
		}))
		manifest := struct {
			Version     string                 `json:"version"`
			Title       string                 `json:"title"`
			Description string                 `json:"description"`
			Permissions models.ToolPermissions `json:"permissions"`
			Access      string                 `json:"access"`
			Members     []int64                `json:"members,omitempty"`
			Content     string                 `json:"content"`
			Base        string                 `json:"resource_base"`
		}{"1.0.0", "远端工具", "市场账号独立验证", models.ToolPermissions{}, "login", nil, content, remote.URL + "/shares/remote-fixture"}
		manifestBytes, err := json.Marshal(manifest)
		if err != nil {
			t.Fatal(err)
		}
		tool = map[string]any{"id": 777, "title": manifest.Title, "description": manifest.Description, "author": "Remote author", "revision": revision, "version": manifest.Version, "category": "document", "size": len(content) + len("window.remoteReferenceDownloaded=true;"), "asset_count": 1, "hash": fmt.Sprintf("%x", sha256.Sum256(manifestBytes)), "offline": true, "access": "login", "distribution": "references", "source": "remote-fixture", "resource_base": manifest.Base, "permissions": models.ToolPermissions{}}
		t.Cleanup(remote.Close)
		t.Setenv("BOOKSTARK_MARKET_REMOTE_URL", remote.URL)
		if err := models.InitWebDAVDB(filepath.Join(t.TempDir(), "tool-files.db")); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { models.WebDAVDB.Close(); models.WebDAVDB = nil })
		if _, err := models.EnsureDAVRoot(1); err != nil {
			t.Fatal(err)
		}
		for name, content := range map[string]string{"market-fixture.js": "window.marketStaticLoaded=true;", "market-fixture.css": "body { --market-local-style: ready; }", "market-module.js": "import {value} from './market-dep.js'; window.marketModule=value;", "market-dep.js": "export const value=42;"} {
			mime := "text/javascript"
			if strings.HasSuffix(name, ".css") {
				mime = "text/css"
			}
			node, _, err := models.PutDAVFile(1, "/"+name, mime, strings.NewReader(content), 20<<20, 100<<20)
			if err != nil {
				t.Fatal(err)
			}
			if _, err = models.CreateOrUpdateDAVPublicAsset(1, node.NodeID, "/"+name); err != nil {
				t.Fatal(err)
			}
		}
		for i, title := range []string{"投资驾驶学校", "Craft 白板", "世界电视", "街机游戏厅"} {
			content := `<!doctype html><html><head><meta charset="utf-8"><script src="/dav-public/admin/market-fixture.js"></script><script type="module" src="/dav-public/admin/market-module.js"></script><link rel="stylesheet" href="/dav-public/admin/market-fixture.css"></head><body><h1>Tool v1</h1><label for="value">Value</label><input id="value"><button id="save">Save</button><output id="result"></output><script>document.getElementById('value').value=localStorage.getItem('value')||'';document.getElementById('save').onclick=()=>{localStorage.setItem('value',document.getElementById('value').value);document.getElementById('result').textContent='saved';};</script></body></html>`
			raw, err := models.EncodeHTMLContent(content)
			if err != nil {
				t.Fatal(err)
			}
			b := &models.Blog{BlogTitle: title, BlogIdentify: fmt.Sprintf("market-browser-%d", i), MemberID: 1, BlogType: "article", EditorType: "html", Visibility: 0, BlogContent: raw, BlogDesc: "HTML 工具"}
			if err := b.Insert(); err != nil {
				t.Fatal(err)
			}

		}
	})
}
