package main

import (
	"bookstark/models"
	"bookstark/services"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

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
