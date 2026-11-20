package services

import (
	"bookstark/conf"
	"bookstark/models"
	"context"
	"io"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

type newsTransport func(*http.Request) (*http.Response, error)

func (f newsTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func newsTestDB(t *testing.T) {
	t.Helper()
	conf.LoadDefaults()
	conf.App.AdminPassword = "news-test-only"
	if e := models.InitDB(filepath.Join(t.TempDir(), "news.db")); e != nil {
		t.Fatal(e)
	}
	old := NewsClient
	t.Cleanup(func() { NewsClient = old; models.DB.Close() })
}
func mockNewsHTTP(body string, status int) {
	NewsClient = &http.Client{Transport: newsTransport(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: status, Header: http.Header{"Etag": []string{"news-v1"}}, Body: io.NopCloser(strings.NewReader(body))}, nil
	})}
}
func TestNewsValidationAndTextOnly(t *testing.T) {
	for _, u := range []string{"http://127.0.0.1/rss", "https://169.254.169.254/", "https://localhost/rss", "file:///tmp/news", "https://user:pass@example.com/rss", "https://example.com:8080/rss", "https://[::1]/rss", "https://100.64.0.1/rss"} {
		if NewsURL(u) == nil {
			t.Fatalf("accepted %s", u)
		}
	}
	for _, u := range []string{"https://example.com/rss", "http://example.com/rss"} {
		if e := NewsURL(u); e != nil {
			t.Fatal(e)
		}
	}
	c := models.DefaultNewsConfig()
	if e := ValidateNewsConfig(c); e != nil {
		t.Fatal(e)
	}
	c.Repositories[0].Path = "../secret.opml"
	if ValidateNewsConfig(c) == nil {
		t.Fatal("path traversal accepted")
	}
	now := time.Date(2026, 11, 20, 8, 0, 0, 0, time.UTC)
	feed := `<rss version="2.0"><channel><item><title>&lt;b&gt;Hello&lt;/b&gt;</title><link>https://example.com/a#top</link><guid>x</guid><description><![CDATA[<script>alert(1)</script><p>Safe &amp; sound<img src="https://tracker.test/pixel"></p>]]></description><pubDate>Fri, 20 Nov 2026 08:00:00 +0000</pubDate></item><item><title>unsafe</title><link>javascript:alert(1)</link></item></channel></rss>`
	a, e := parseNewsFeed([]byte(feed), "https://example.com/feed", now)
	if e != nil || len(a) != 1 {
		t.Fatalf("%+v %v", a, e)
	}
	if a[0].Title != "Hello" || a[0].Summary != "Safe & sound" || a[0].URL != "https://example.com/a" || a[0].Published != now.Unix() {
		t.Fatalf("not clean: %+v", a)
	}
	atom := `<feed xmlns="http://www.w3.org/2005/Atom"><entry><id>atom1</id><title>Atom</title><link rel="alternate" href="/article"/><updated>2026-11-20T07:00:00Z</updated><summary>Summary</summary></entry></feed>`
	a, e = parseNewsFeed([]byte(atom), "https://example.com/feed", now)
	if e != nil || len(a) != 1 || a[0].URL != "https://example.com/article" {
		t.Fatalf("atom %+v %v", a, e)
	}
	if _, e = parseNewsFeed([]byte("<html>Not a feed</html>"), "https://example.com", now); e == nil {
		t.Fatal("HTML accepted")
	}
}
func TestNewsSyncPreservesOverridesAndRemoval(t *testing.T) {
	newsTestDB(t)
	r := models.DefaultNewsConfig().Repositories[0]
	ctx := context.Background()
	body := `<opml><body><outline text="Group"><outline text="One" xmlUrl="https://example.com/rss"/><outline text="Duplicate" xmlUrl="https://example.com/rss"/></outline></body></opml>`
	mockNewsHTTP(body, 200)
	n, e := syncNewsRepository(ctx, r)
	if e != nil || n != 1 {
		t.Fatalf("sync %d %v", n, e)
	}
	sources, _ := models.NewsSources(false)
	if len(sources) != 1 || sources[0].Enabled {
		t.Fatal("new sources must remain pending")
	}
	_, e = models.DB.Exec(`UPDATE md_news_sources SET enabled=1,edited=1,category='design',language='zh'`)
	if e != nil {
		t.Fatal(e)
	}
	r2 := r
	r2.Path = "other.opml"
	if _, e = syncNewsRepository(ctx, r2); e != nil {
		t.Fatal(e)
	}
	mockNewsHTTP(`<opml><body><outline text="Two" xmlUrl="https://example.net/rss"/></body></opml>`, 200)
	if _, e = syncNewsRepository(ctx, r); e != nil {
		t.Fatal(e)
	}
	sources, _ = models.NewsSources(false)
	if sources[0].Removed || !sources[0].Enabled || sources[0].Category != "design" || sources[0].Language != "zh" {
		t.Fatalf("manual overrides or multiple memberships lost %+v", sources[0])
	}
	mockNewsHTTP(`<opml><body></body></opml>`, 200)
	if _, e = syncNewsRepository(ctx, r2); e == nil {
		t.Fatal("empty inventory accepted")
	}
	sources, _ = models.NewsSources(false)
	if sources[0].Removed {
		t.Fatal("failed sync marked removed")
	}
	mockNewsHTTP(`<opml><body><outline text="Two" xmlUrl="https://example.net/rss"/></body></opml>`, 200)
	if _, e = syncNewsRepository(ctx, r2); e != nil {
		t.Fatal(e)
	}
	sources, _ = models.NewsSources(false)
	if !sources[0].Removed || !sources[0].Enabled {
		t.Fatal("removal must flag, not change enabled state")
	}
}
func TestNewsFetchCacheDedupFailureAndRetention(t *testing.T) {
	newsTestDB(t)
	ctx := context.Background()
	_, e := models.DB.Exec(`INSERT INTO md_news_sources(url,name,enabled,category,language) VALUES('https://example.com/rss','Example',1,'ai-tools','en')`)
	if e != nil {
		t.Fatal(e)
	}
	sources, _ := models.NewsSources(false)
	s := sources[0]
	body := `<rss><channel><item><title>One</title><link>https://example.com/a</link><guid>a</guid><description>Summary</description></item></channel></rss>`
	mockNewsHTTP(body, 200)
	n, e := fetchNewsSource(ctx, s, 90)
	if e != nil || n != 1 {
		t.Fatalf("fetch %d %v", n, e)
	}
	mockNewsHTTP(strings.Replace(body, "<guid>a</guid>", "<guid>changed</guid>", 1), 200)
	if n, e = fetchNewsSource(ctx, s, 90); e != nil || n != 0 {
		t.Fatalf("duplicate URL inserted %d %v", n, e)
	}
	sources, _ = models.NewsSources(false)
	s = sources[0]
	NewsClient = &http.Client{Transport: newsTransport(func(r *http.Request) (*http.Response, error) {
		if r.Header.Get("If-None-Match") != "news-v1" {
			t.Error("no conditional request")
		}
		return &http.Response{StatusCode: 304, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(""))}, nil
	})}
	if n, e = fetchNewsSource(ctx, s, 90); e != nil || n != 0 {
		t.Fatal(n, e)
	}
	mockNewsHTTP("<html>bad feed</html>", 200)
	if _, e = fetchNewsSource(ctx, s, 90); e == nil {
		t.Fatal("invalid feed accepted")
	}
	a, total, e := models.ListNews(1, "", "", "", "")
	if e != nil || total != 1 || len(a) != 1 {
		t.Fatal("failure erased cache", total, e)
	}
	sources, _ = models.NewsSources(false)
	if sources[0].Failures != 1 || sources[0].LastSuccess == 0 {
		t.Fatal("failure state not preserved")
	}
	_, _ = models.DB.Exec(`UPDATE md_news_sources SET enabled=0`)
	_, total, _ = models.ListNews(1, "", "", "", "")
	if total != 0 {
		t.Fatal("disabled source exposed")
	}
}

func TestNewsJobRetentionAndMutationLock(t *testing.T) {
	newsTestDB(t)
	if !LockNewsChanges() {
		t.Fatal("lock failed")
	}
	if BeginNewsJob("fetch", 0) == nil {
		t.Fatal("job bypassed settings lock")
	}
	UnlockNewsChanges()
	_, e := models.DB.Exec(`INSERT INTO md_news_sources(id,url,name,enabled) VALUES(1,'https://example.com/feed','Source',1)`)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = models.DB.Exec(`INSERT INTO md_news_membership(source_id,repo_key) VALUES(1,'fixture/repo@main/feeds.opml')`); e != nil {
		t.Fatal(e)
	}
	old := time.Now().AddDate(0, 0, -100).Unix()
	for _, u := range []string{"https://example.com/old", "https://example.com/saved"} {
		_, e = models.DB.Exec(`INSERT INTO md_news_articles(source_id,item_key,url,title,published,created) VALUES(1,?,?,?, ?,?)`, u, u, u, old, old)
		if e != nil {
			t.Fatal(e)
		}
	}
	bookmark := models.Bookmark{Title: "Saved", URL: "https://example.com/saved", MemberID: 1}
	if e = bookmark.Insert(); e != nil {
		t.Fatal(e)
	}
	mockNewsHTTP(`<rss><channel><item><title>Fresh</title><guid>fresh</guid><link>https://example.com/fresh</link></item></channel></rss>`, 200)
	runNewsJob(context.Background(), "fetch", 0)
	var n int
	if e = models.DB.QueryRow(`SELECT COUNT(*) FROM md_news_articles`).Scan(&n); e != nil || n != 2 {
		t.Fatal("retention lost bookmark or failed cleanup", n, e)
	}
	var status string
	var added int
	if e = models.DB.QueryRow(`SELECT status,added FROM md_news_runs ORDER BY id DESC LIMIT 1`).Scan(&status, &added); e != nil || status != "success" || added != 1 {
		t.Fatal(status, added, e)
	}
}

func TestNewsUnknownDatesRemainUnknown(t *testing.T) {
	newsTestDB(t)
	now := time.Now()
	body := `<rss><channel><item><title>Undated</title><guid>u</guid><link>https://example.com/undated</link></item><item><title>Dated</title><guid>d</guid><link>https://example.com/dated</link><pubDate>` + now.Add(-time.Hour).Format(time.RFC1123Z) + `</pubDate></item></channel></rss>`
	items, e := parseNewsFeed([]byte(body), "https://example.com/feed", now)
	if e != nil || len(items) != 2 || items[0].Published != 0 {
		t.Fatal(items, e)
	}
	_, e = models.DB.Exec(`INSERT INTO md_news_sources(url,name,enabled) VALUES('https://example.com/feed','Example',1)`)
	if e != nil {
		t.Fatal(e)
	}
	sources, _ := models.NewsSources(false)
	mockNewsHTTP(body, 200)
	if _, e = fetchNewsSource(context.Background(), sources[0], 90); e != nil {
		t.Fatal(e)
	}
	list, _, e := models.ListNews(1, "", "", "", "")
	if e != nil || len(list) != 2 || list[0].Title != "Dated" || list[1].Published != 0 {
		t.Fatal(list, e)
	}
	_, _ = models.DB.Exec(`UPDATE md_news_articles SET published=created WHERE title='Undated'`)
	if _, e = fetchNewsSource(context.Background(), sources[0], 90); e != nil {
		t.Fatal(e)
	}
	list, _, _ = models.ListNews(1, "", "", "", "")
	if list[1].Published != 0 {
		t.Fatal("existing undated cache was not corrected")
	}
}

func TestNewsCategoryLimitAndLegacyConfig(t *testing.T) {
	newsTestDB(t)
	// Older saved configurations gain the new default without resetting schedules.
	if e := models.BatchUpdateSettings(map[string]string{"news_config": `{"fetchMinutes":45}`}); e != nil {
		t.Fatal(e)
	}
	cfg, e := models.LoadNewsConfig()
	if e != nil || cfg.MaxPerCategory != 100 || cfg.FetchMinutes != 45 {
		t.Fatal(cfg, e)
	}
	for _, n := range []int{0, -1, 1001} {
		bad := cfg
		bad.MaxPerCategory = n
		if ValidateNewsConfig(bad) == nil {
			t.Fatal("accepted invalid limit", n)
		}
	}
	cfg.MaxPerCategory = 2
	if e = models.SaveNewsConfig(cfg); e != nil {
		t.Fatal(e)
	}
	if _, e = models.DB.Exec(`INSERT INTO md_news_sources(id,url,name,category,enabled) VALUES(1,'https://one.example/rss','One','ai-tools',0),(2,'https://two.example/rss','Two','ai-tools',0),(3,'https://three.example/rss','Three','design',0)`); e != nil {
		t.Fatal(e)
	}
	now := time.Now().Unix()
	for _, a := range []struct {
		id, source int
		published  int64
	}{{1, 1, now - 10}, {2, 2, now}, {3, 1, now}, {4, 2, 0}, {5, 3, now}, {6, 3, now - 10}, {7, 3, now - 20}} {
		if _, e = models.DB.Exec(`INSERT INTO md_news_articles(id,source_id,item_key,url,title,published,created) VALUES(?,?,?,?,'Story',?,?)`, a.id, a.source, a.id, "https://example.com/"+strconv.Itoa(a.id), a.published, now); e != nil {
			t.Fatal(e)
		}
	}
	b := models.Bookmark{Title: "Keep bookmark", URL: "https://example.com/1", MemberID: 1}
	if e = b.Insert(); e != nil {
		t.Fatal(e)
	}
	// Also trim when sources are disabled or skipped: cleanup is job-wide.
	runNewsJob(context.Background(), "fetch", 0)
	var ids string
	if e = models.DB.QueryRow(`SELECT group_concat(id,',') FROM (SELECT id FROM md_news_articles ORDER BY id)`).Scan(&ids); e != nil || ids != "2,3,5,6" {
		t.Fatal(ids, e)
	}
	var n int
	if e = models.DB.QueryRow(`SELECT COUNT(*) FROM md_bookmark WHERE url=?`, b.URL).Scan(&n); e != nil || n != 1 {
		t.Fatal("bookmark deleted", n, e)
	}
	// A tighter saved cap applies on the next update with deterministic tie ordering.
	cfg.MaxPerCategory = 1
	if e = models.SaveNewsConfig(cfg); e != nil {
		t.Fatal(e)
	}
	runNewsJob(context.Background(), "fetch", 0)
	if e = models.DB.QueryRow(`SELECT group_concat(id,',') FROM (SELECT id FROM md_news_articles ORDER BY id)`).Scan(&ids); e != nil || ids != "3,5" {
		t.Fatal(ids, e)
	}
}
