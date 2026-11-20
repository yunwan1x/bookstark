package services

import (
	"bookstark/models"
	"bookstark/services/worldtv"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/net/html"
	"golang.org/x/net/html/charset"
)

var newsBusy atomic.Bool
var NewsClient = newsHTTPClient()

func newsHTTPClient() *http.Client {
	c := worldtv.NewHTTPClient()
	c.Timeout = 20 * time.Second
	c.CheckRedirect = func(r *http.Request, via []*http.Request) error {
		if len(via) >= 5 {
			return errors.New("too many redirects")
		}
		return NewsURL(r.URL.String())
	}
	return c
}
func NewsURL(raw string) error {
	u, e := url.Parse(raw)
	if e != nil || u.Hostname() == "" || u.User != nil || (u.Scheme != "https" && u.Scheme != "http") || (u.Port() != "" && u.Port() != "443" && u.Port() != "80") {
		return errors.New("invalid public HTTP(S) URL")
	}
	u.Scheme = "https"
	return worldtv.ValidateSource(u.String())
}
func canonicalNewsURL(raw string) string {
	u, e := url.Parse(strings.TrimSpace(raw))
	if e != nil {
		return ""
	}
	u.Fragment = ""
	u.Host = strings.ToLower(u.Host)
	if NewsURL(u.String()) != nil {
		return ""
	}
	return u.String()
}

var repoPattern = regexp.MustCompile(`^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`)
var branchPattern = regexp.MustCompile(`^[A-Za-z0-9_.-]+$`)

func ValidateNewsConfig(c models.NewsConfig) error {
	if len(c.Repositories) < 1 || len(c.Repositories) > 24 || c.SyncHours < 1 || c.SyncHours > 168 || c.FetchMinutes < 15 || c.FetchMinutes > 1440 || c.RetentionDays < 7 || c.RetentionDays > 365 {
		return errors.New("invalid intervals, retention or repository count")
	}
	seen := map[string]bool{}
	for _, r := range c.Repositories {
		if !repoPattern.MatchString(r.Repo) || !branchPattern.MatchString(r.Branch) || len(r.Repo) > 160 || len(r.Branch) > 100 || len(r.Path) > 240 || strings.Contains(r.Path, "..") || strings.HasPrefix(r.Path, "/") || strings.ContainsAny(r.Path, "?&#\\ \r\n") || !strings.HasSuffix(r.Path, ".opml") || !models.ValidNewsCategory(r.Category) || (r.Language != "zh" && r.Language != "en" && r.Language != "") {
			return errors.New("invalid repository, OPML path, category or language")
		}
		key := repoKey(r)
		if seen[key] {
			return errors.New("duplicate repository file")
		}
		seen[key] = true
	}
	return nil
}
func repoKey(r models.NewsRepository) string { return r.Repo + "@" + r.Branch + "/" + r.Path }
func newsGet(ctx context.Context, raw, etag, modified string) ([]byte, http.Header, int, error) {
	if e := NewsURL(raw); e != nil {
		return nil, nil, 0, e
	}
	req, e := http.NewRequestWithContext(ctx, "GET", raw, nil)
	if e != nil {
		return nil, nil, 0, e
	}
	req.Header.Set("User-Agent", "BookStark-RSS/1.0")
	req.Header.Set("Accept", "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9")
	if etag != "" {
		req.Header.Set("If-None-Match", etag)
	}
	if modified != "" {
		req.Header.Set("If-Modified-Since", modified)
	}
	res, e := NewsClient.Do(req)
	if e != nil {
		return nil, nil, 0, errors.New("request failed or timed out")
	}
	defer res.Body.Close()
	if res.StatusCode == 304 {
		return nil, res.Header, 304, nil
	}
	if res.StatusCode != 200 {
		return nil, res.Header, res.StatusCode, fmt.Errorf("HTTP %d", res.StatusCode)
	}
	b, e := io.ReadAll(io.LimitReader(res.Body, 8*1024*1024+1))
	if len(b) > 8*1024*1024 {
		return nil, nil, 0, errors.New("feed exceeds 8 MiB")
	}
	return b, res.Header, 200, e
}

type opmlOutline struct {
	Text     string        `xml:"text,attr"`
	Title    string        `xml:"title,attr"`
	URL      string        `xml:"xmlUrl,attr"`
	Children []opmlOutline `xml:"outline"`
}

func parseNewsOPML(b []byte) ([]opmlOutline, error) {
	var doc struct {
		XMLName xml.Name `xml:"opml"`
		Body    struct {
			Outlines []opmlOutline `xml:"outline"`
		} `xml:"body"`
	}
	d := xml.NewDecoder(strings.NewReader(string(b)))
	d.CharsetReader = charset.NewReaderLabel
	if e := d.Decode(&doc); e != nil {
		return nil, e
	}
	out := []opmlOutline{}
	seen := map[string]bool{}
	var walk func([]opmlOutline)
	walk = func(rows []opmlOutline) {
		for _, r := range rows {
			if r.URL != "" {
				r.URL = canonicalNewsURL(r.URL)
				if r.URL != "" && !seen[r.URL] {
					r.Title = plainNewsText(r.Title, 200)
					if r.Title == "" {
						r.Title = plainNewsText(r.Text, 200)
					}
					if r.Title == "" {
						r.Title = r.URL
					}
					seen[r.URL] = true
					out = append(out, r)
				}
			}
			walk(r.Children)
		}
	}
	walk(doc.Body.Outlines)
	if len(out) == 0 || len(out) > 10000 {
		return nil, errors.New("empty or oversized OPML inventory")
	}
	return out, nil
}
func syncNewsRepository(ctx context.Context, r models.NewsRepository) (int, error) {
	b, _, _, e := newsGet(ctx, "https://raw.githubusercontent.com/"+r.Repo+"/"+r.Branch+"/"+r.Path, "", "")
	if e != nil {
		return 0, e
	}
	rows, e := parseNewsOPML(b)
	if e != nil {
		return 0, e
	}
	tx, e := models.DB.BeginTx(ctx, nil)
	if e != nil {
		return 0, e
	}
	defer tx.Rollback()
	key := repoKey(r)
	if _, e = tx.ExecContext(ctx, "UPDATE md_news_membership SET present=0 WHERE repo_key=?", key); e != nil {
		return 0, e
	}
	added := 0
	for _, r0 := range rows {
		res, e := tx.ExecContext(ctx, `INSERT OR IGNORE INTO md_news_sources(url,name,category,language) VALUES(?,?,?,?)`, r0.URL, r0.Title, r.Category, r.Language)
		if e != nil {
			return 0, e
		}
		n, _ := res.RowsAffected()
		added += int(n)
		if _, e = tx.ExecContext(ctx, `UPDATE md_news_sources SET name=?,category=CASE WHEN edited=0 THEN ? ELSE category END,language=CASE WHEN edited=0 THEN ? ELSE language END WHERE url=?`, r0.Title, r.Category, r.Language, r0.URL); e != nil {
			return 0, e
		}
		if _, e = tx.ExecContext(ctx, `INSERT INTO md_news_membership(source_id,repo_key,present) SELECT id,?,1 FROM md_news_sources WHERE url=? ON CONFLICT(source_id,repo_key) DO UPDATE SET present=1`, key, r0.URL); e != nil {
			return 0, e
		}
	}
	return added, tx.Commit()
}
func plainNewsText(raw string, limit int) string {
	z := html.NewTokenizer(strings.NewReader(raw))
	var b strings.Builder
	skip := 0
	for {
		t := z.Next()
		if t == html.ErrorToken {
			break
		}
		if t == html.StartTagToken || t == html.EndTagToken {
			n, _ := z.TagName()
			tag := string(n)
			if tag == "script" || tag == "style" {
				if t == html.StartTagToken {
					skip++
				} else if skip > 0 {
					skip--
				}
			}
			b.WriteByte(' ')
		}
		if t == html.TextToken && skip == 0 {
			b.Write(z.Text())
		}
		if b.Len() > 50000 {
			break
		}
	}
	s := strings.Join(strings.Fields(b.String()), " ")
	r := []rune(s)
	if len(r) > limit {
		s = string(r[:limit]) + "…"
	}
	return s
}

type newsLink struct {
	Href string `xml:"href,attr"`
	Rel  string `xml:"rel,attr"`
	Text string `xml:",chardata"`
}
type newsEntry struct {
	Title       string     `xml:"title"`
	Links       []newsLink `xml:"link"`
	GUID        string     `xml:"guid"`
	ID          string     `xml:"id"`
	Description string     `xml:"description"`
	Summary     string     `xml:"summary"`
	Content     string     `xml:"content"`
	Encoded     string     `xml:"encoded"`
	PubDate     string     `xml:"pubDate"`
	Published   string     `xml:"published"`
	Updated     string     `xml:"updated"`
	Date        string     `xml:"date"`
}

func newsDate(raw string) time.Time {
	for _, layout := range []string{time.RFC3339Nano, time.RFC1123Z, time.RFC1123, time.RFC822Z, time.RFC822, time.RFC850, "Mon, 2 Jan 2006 15:04:05 -0700", "2006-01-02T15:04:05", "2006-01-02"} {
		if t, e := time.Parse(layout, strings.TrimSpace(raw)); e == nil {
			return t
		}
	}
	return time.Time{}
}
func parseNewsFeed(b []byte, base string, now time.Time) ([]models.NewsArticle, error) {
	var doc struct {
		XMLName xml.Name
		Channel struct {
			Items []newsEntry `xml:"item"`
		} `xml:"channel"`
		Entries []newsEntry `xml:"entry"`
		Items   []newsEntry `xml:"item"`
	}
	d := xml.NewDecoder(strings.NewReader(string(b)))
	d.CharsetReader = charset.NewReaderLabel
	if e := d.Decode(&doc); e != nil {
		return nil, e
	}
	var entries []newsEntry
	switch doc.XMLName.Local {
	case "rss":
		entries = doc.Channel.Items
	case "feed":
		entries = doc.Entries
	case "RDF":
		entries = doc.Items
	default:
		return nil, errors.New("not RSS or Atom")
	}
	baseURL, _ := url.Parse(base)
	out := []models.NewsArticle{}
	for i, e := range entries {
		if i >= 300 {
			break
		}
		link := ""
		for _, l := range e.Links {
			if l.Href != "" && (l.Rel == "" || l.Rel == "alternate") {
				link = l.Href
				break
			}
			if l.Text != "" {
				link = l.Text
				break
			}
		}
		if link == "" {
			link = e.GUID
		}
		u, err := url.Parse(strings.TrimSpace(link))
		if err != nil || link == "" {
			continue
		}
		if baseURL != nil {
			u = baseURL.ResolveReference(u)
		}
		link = canonicalNewsURL(u.String())
		title := plainNewsText(e.Title, 300)
		if link == "" || title == "" {
			continue
		}
		summary := e.Description
		if summary == "" {
			summary = e.Summary
		}
		if summary == "" {
			summary = e.Content
		}
		if summary == "" {
			summary = e.Encoded
		}
		published := time.Time{}
		for _, v := range []string{e.Published, e.PubDate, e.Date, e.Updated} {
			published = newsDate(v)
			if !published.IsZero() {
				break
			}
		}
		publishedUnix := int64(0)
		if !published.IsZero() && !published.After(now.Add(24*time.Hour)) {
			publishedUnix = published.Unix()
		}
		out = append(out, models.NewsArticle{URL: link, Title: title, Summary: plainNewsText(summary, 700), Published: publishedUnix})
		key := e.ID
		if key == "" {
			key = e.GUID
		}
		if key == "" {
			key = link
		}
		hash := sha256.Sum256([]byte(key))
		out[len(out)-1].ItemKey = hex.EncodeToString(hash[:])
	}
	return out, nil
}
func fetchNewsSource(ctx context.Context, s models.NewsSource, retention int) (int, error) {
	now := time.Now()
	b, h, status, e := newsGet(ctx, s.URL, s.ETag, s.Modified)
	if e != nil {
		return 0, newsSourceError(s.ID, now, e)
	}
	if status == 304 {
		_, e = models.DB.Exec(`UPDATE md_news_sources SET last_attempt=?,last_success=?,error='',failures=0 WHERE id=?`, now.Unix(), now.Unix(), s.ID)
		return 0, e
	}
	items, e := parseNewsFeed(b, s.URL, now)
	if e != nil {
		return 0, newsSourceError(s.ID, now, errors.New("invalid RSS/Atom content"))
	}
	tx, e := models.DB.BeginTx(ctx, nil)
	if e != nil {
		return 0, e
	}
	defer tx.Rollback()
	added := 0
	latest := int64(0)
	for _, a := range items {
		if a.Published > latest {
			latest = a.Published
		}
		if a.Published > 0 && a.Published < now.AddDate(0, 0, -retention).Unix() {
			continue
		}
		res, e := tx.ExecContext(ctx, `INSERT OR IGNORE INTO md_news_articles(source_id,item_key,url,title,summary,published,created) VALUES(?,?,?,?,?,?,?)`, s.ID, a.ItemKey, a.URL, a.Title, a.Summary, a.Published, now.Unix())
		if e != nil {
			return 0, e
		}
		n, _ := res.RowsAffected()
		added += int(n)
		if n == 0 {
			if _, e = tx.ExecContext(ctx, `UPDATE md_news_articles SET title=?,summary=?,published=? WHERE source_id=? AND (item_key=? OR url=?)`, a.Title, a.Summary, a.Published, s.ID, a.ItemKey, a.URL); e != nil {
				return 0, e
			}
		}
	}
	_, e = tx.ExecContext(ctx, `UPDATE md_news_sources SET last_attempt=?,last_success=?,latest_article=?,error='',failures=0,etag=?,modified=? WHERE id=?`, now.Unix(), now.Unix(), latest, h.Get("ETag"), h.Get("Last-Modified"), s.ID)
	if e != nil {
		return 0, e
	}
	return added, tx.Commit()
}
func newsSourceError(id int64, now time.Time, e error) error {
	_, dbErr := models.DB.Exec(`UPDATE md_news_sources SET last_attempt=?,error=?,failures=failures+1 WHERE id=?`, now.Unix(), e.Error(), id)
	if dbErr != nil {
		return dbErr
	}
	return e
}
func NewsRunning() bool { return newsBusy.Load() }

// Serialize administrator mutations with accepted jobs.
func LockNewsChanges() bool { return newsBusy.CompareAndSwap(false, true) }
func UnlockNewsChanges()    { newsBusy.Store(false) }
func BeginNewsJob(kind string, sourceID int64) error {
	if kind != "sync" && kind != "fetch" {
		return errors.New("invalid job")
	}
	if !newsBusy.CompareAndSwap(false, true) {
		return errors.New("news job already running")
	}
	go func() {
		defer newsBusy.Store(false)
		ctx, cancel := context.WithTimeout(context.Background(), 12*time.Minute)
		defer cancel()
		runNewsJob(ctx, kind, sourceID)
	}()
	return nil
}
func runNewsJob(ctx context.Context, kind string, sourceID int64) {
	start := time.Now().Unix()
	res, e := models.DB.Exec(`INSERT INTO md_news_runs(kind,started,status) VALUES(?,?,'running')`, kind, start)
	if e != nil {
		return
	}
	id, _ := res.LastInsertId()
	added, failed, succeeded := 0, 0, 0
	details := []string{}
	cfg, e := models.LoadNewsConfig()
	if e == nil {
		e = ValidateNewsConfig(cfg)
	}
	if e != nil {
		failed++
		details = append(details, e.Error())
	} else if kind == "sync" {
		for _, r := range cfg.Repositories {
			if !r.Enabled {
				continue
			}
			n, err := syncNewsRepository(ctx, r)
			added += n
			if err != nil {
				failed++
				details = append(details, repoKey(r)+": "+err.Error())
			} else {
				succeeded++
			}
		}
	} else {
		sources, err := models.NewsSources(false)
		if err != nil {
			failed++
			details = append(details, err.Error())
		} else {
			var mu sync.Mutex
			var wg sync.WaitGroup
			sem := make(chan struct{}, 4)
			for _, s := range sources {
				if sourceID > 0 {
					if s.ID != sourceID {
						continue
					}
				} else if !s.Enabled || s.Removed {
					continue
				}
				if sourceID == 0 && s.Failures > 0 {
					delay := time.Duration(1<<min(s.Failures, 5)) * time.Duration(cfg.FetchMinutes) * time.Minute
					if time.Since(time.Unix(s.LastAttempt, 0)) < delay {
						continue
					}
				}
				if ctx.Err() != nil {
					mu.Lock()
					failed++
					details = append(details, "job timed out")
					mu.Unlock()
					break
				}
				sem <- struct{}{}
				wg.Add(1)
				go func(s models.NewsSource) {
					defer wg.Done()
					defer func() { <-sem }()
					n, err := fetchNewsSource(ctx, s, cfg.RetentionDays)
					mu.Lock()
					defer mu.Unlock()
					added += n
					if err != nil {
						failed++
						details = append(details, s.Name+": "+err.Error())
					} else {
						succeeded++
					}
				}(s)
			}
			wg.Wait()
		}
		if _, err := models.DB.Exec(`DELETE FROM md_news_articles WHERE (CASE WHEN published>0 THEN published ELSE created END)<? AND url NOT IN (SELECT url FROM md_bookmark)`, time.Now().AddDate(0, 0, -cfg.RetentionDays).Unix()); err != nil {
			failed++
			details = append(details, "retention cleanup failed")
		}
	}
	status := "success"
	if failed > 0 {
		status = "partial"
		if succeeded == 0 {
			status = "failed"
		}
	}
	_, _ = models.DB.Exec(`UPDATE md_news_runs SET finished=?,status=?,added=?,failed=?,details=? WHERE id=?`, time.Now().Unix(), status, added, failed, strings.Join(details, "\n"), id)
	_, _ = models.DB.Exec(`DELETE FROM md_news_runs WHERE id NOT IN (SELECT id FROM md_news_runs ORDER BY id DESC LIMIT 100)`)
}
func NewsLastRun(kind string) int64 {
	var n sql.NullInt64
	_ = models.DB.QueryRow(`SELECT MAX(started) FROM md_news_runs WHERE kind=?`, kind).Scan(&n)
	return n.Int64
}
func StartNewsScheduler() func() {
	ctx, cancel := context.WithCancel(context.Background())
	_, _ = models.DB.Exec(`UPDATE md_news_runs SET status='interrupted',finished=? WHERE status='running'`, time.Now().Unix())
	go func() {
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				cfg, e := models.LoadNewsConfig()
				if e != nil || NewsRunning() {
					continue
				}
				if cfg.SyncEnabled && time.Since(time.Unix(NewsLastRun("sync"), 0)) >= time.Duration(cfg.SyncHours)*time.Hour {
					_ = BeginNewsJob("sync", 0)
				} else if cfg.FetchEnabled && time.Since(time.Unix(NewsLastRun("fetch"), 0)) >= time.Duration(cfg.FetchMinutes)*time.Minute {
					_ = BeginNewsJob("fetch", 0)
				}
			}
		}
	}()
	return cancel
}
