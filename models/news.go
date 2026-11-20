package models

import (
	"database/sql"
	"encoding/json"
	"errors"
	"strings"
)

type NewsRepository struct {
	Repo     string `json:"repo"`
	Branch   string `json:"branch"`
	Path     string `json:"path"`
	Category string `json:"category"`
	Language string `json:"language"`
	Enabled  bool   `json:"enabled"`
}
type NewsConfig struct {
	Repositories   []NewsRepository `json:"repositories"`
	SyncEnabled    bool             `json:"syncEnabled"`
	SyncHours      int              `json:"syncHours"`
	FetchEnabled   bool             `json:"fetchEnabled"`
	FetchMinutes   int              `json:"fetchMinutes"`
	RetentionDays  int              `json:"retentionDays"`
	MaxPerCategory int              `json:"maxPerCategory"`
}

func DefaultNewsConfig() NewsConfig {
	c := NewsConfig{Repositories: []NewsRepository{
		{"alan-turing-institute/ai-rss-feeds", "main", "feeds.opml", "ai-research", "en", true},
		{"xiangyugongzuoliu/awesome-rss-feeds-list", "main", "feeds/cn-ai-tools.opml", "ai-tools", "zh", true},
		{"xiangyugongzuoliu/awesome-rss-feeds-list", "main", "feeds/en-ai-research.opml", "ai-research", "en", true},
	}, SyncHours: 24, FetchMinutes: 30, RetentionDays: 90, MaxPerCategory: 100}
	for _, group := range []struct{ file, category string }{{"backend", "development"}, {"web-frontend", "development"}, {"product-design", "design"}, {"finance", "finance"}, {"essays", "other"}} {
		for _, lang := range []string{"cn", "en"} {
			language := lang
			if lang == "cn" {
				language = "zh"
			}
			c.Repositories = append(c.Repositories, NewsRepository{"xiangyugongzuoliu/awesome-rss-feeds-list", "main", "feeds/" + lang + "-" + group.file + ".opml", group.category, language, true})
		}
	}
	c.Repositories = append(c.Repositories, NewsRepository{"xiangyugongzuoliu/awesome-rss-feeds-list", "main", "feeds/cn-ai-research.opml", "ai-research", "zh", true}, NewsRepository{"xiangyugongzuoliu/awesome-rss-feeds-list", "main", "feeds/en-ai-tools.opml", "ai-tools", "en", true})
	return c
}
func LoadNewsConfig() (NewsConfig, error) {
	c := DefaultNewsConfig()
	var raw string
	err := DB.QueryRow("SELECT value FROM md_settings WHERE key='news_config'").Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return c, nil
	}
	if err != nil {
		return c, err
	}
	err = json.Unmarshal([]byte(raw), &c)
	return c, err
}
func SaveNewsConfig(c NewsConfig) error {
	b, e := json.Marshal(c)
	if e != nil {
		return e
	}
	return BatchUpdateSettings(map[string]string{"news_config": string(b)})
}

var NewsCategories = []string{"ai-research", "ai-tools", "development", "design", "finance", "other"}

func ValidNewsCategory(s string) bool {
	for _, v := range NewsCategories {
		if s == v {
			return true
		}
	}
	return false
}
func InitNewsTables() error {
	for _, q := range []string{
		`CREATE TABLE IF NOT EXISTS md_news_sources(id INTEGER PRIMARY KEY AUTOINCREMENT,url TEXT NOT NULL UNIQUE,name TEXT NOT NULL,category TEXT NOT NULL DEFAULT 'other',language TEXT NOT NULL DEFAULT '',enabled INTEGER NOT NULL DEFAULT 0,edited INTEGER NOT NULL DEFAULT 0,etag TEXT NOT NULL DEFAULT '',modified TEXT NOT NULL DEFAULT '',last_attempt INTEGER NOT NULL DEFAULT 0,last_success INTEGER NOT NULL DEFAULT 0,latest_article INTEGER NOT NULL DEFAULT 0,error TEXT NOT NULL DEFAULT '',failures INTEGER NOT NULL DEFAULT 0)`,
		`CREATE TABLE IF NOT EXISTS md_news_membership(source_id INTEGER NOT NULL,repo_key TEXT NOT NULL,present INTEGER NOT NULL DEFAULT 1,PRIMARY KEY(source_id,repo_key),FOREIGN KEY(source_id) REFERENCES md_news_sources(id))`,
		`CREATE TABLE IF NOT EXISTS md_news_articles(id INTEGER PRIMARY KEY AUTOINCREMENT,source_id INTEGER NOT NULL,item_key TEXT NOT NULL,url TEXT NOT NULL,title TEXT NOT NULL,summary TEXT NOT NULL DEFAULT '',published INTEGER NOT NULL,created INTEGER NOT NULL,UNIQUE(source_id,item_key),UNIQUE(url),FOREIGN KEY(source_id) REFERENCES md_news_sources(id))`,
		`CREATE INDEX IF NOT EXISTS idx_news_published ON md_news_articles(published DESC,id DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_news_article_source ON md_news_articles(source_id)`,
		`CREATE TABLE IF NOT EXISTS md_news_runs(id INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT NOT NULL,started INTEGER NOT NULL,finished INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL,added INTEGER NOT NULL DEFAULT 0,failed INTEGER NOT NULL DEFAULT 0,details TEXT NOT NULL DEFAULT '')`,
	} {
		if _, e := DB.Exec(q); e != nil {
			return e
		}
	}

	// Cache v3 refills source diversity after the previous timestamp-only cap.
	// Invalidate conditional headers once so trimmed feeds can be re-fetched.
	tx, e := DB.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	var version string
	e = tx.QueryRow("SELECT value FROM md_settings WHERE key='news_parser_version'").Scan(&version)
	if e != nil && !errors.Is(e, sql.ErrNoRows) {
		return e
	}
	if version != "3" {
		if _, e = tx.Exec("UPDATE md_news_sources SET etag='',modified=''"); e != nil {
			return e
		}
		if _, e = tx.Exec("INSERT INTO md_settings(key,value) VALUES('news_parser_version','3') ON CONFLICT(key) DO UPDATE SET value='3'"); e != nil {
			return e
		}
	}
	return tx.Commit()
}

type NewsSource struct {
	ID            int64  `json:"id"`
	URL           string `json:"url"`
	Name          string `json:"name"`
	Category      string `json:"category"`
	Language      string `json:"language"`
	Enabled       bool   `json:"enabled"`
	Edited        bool   `json:"edited"`
	LastAttempt   int64  `json:"lastAttempt"`
	LastSuccess   int64  `json:"lastSuccess"`
	LatestArticle int64  `json:"latestArticle"`
	Error         string `json:"error"`
	Failures      int    `json:"failures"`
	Removed       bool   `json:"removed"`
	Repositories  string `json:"repositories"`
	ETag          string `json:"-"`
	Modified      string `json:"-"`
}

func NewsSources(public bool) ([]NewsSource, error) {
	q := `SELECT s.id,s.url,s.name,s.category,s.language,s.enabled,s.edited,s.last_attempt,s.last_success,s.latest_article,s.error,s.failures,NOT EXISTS(SELECT 1 FROM md_news_membership m WHERE m.source_id=s.id AND m.present=1),COALESCE((SELECT group_concat(repo_key,' | ') FROM md_news_membership m WHERE m.source_id=s.id),''),s.etag,s.modified FROM md_news_sources s`
	if public {
		q += " WHERE s.enabled=1"
	}
	q += " ORDER BY s.name COLLATE NOCASE"
	rows, e := DB.Query(q)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := []NewsSource{}
	for rows.Next() {
		var s NewsSource
		if e = rows.Scan(&s.ID, &s.URL, &s.Name, &s.Category, &s.Language, &s.Enabled, &s.Edited, &s.LastAttempt, &s.LastSuccess, &s.LatestArticle, &s.Error, &s.Failures, &s.Removed, &s.Repositories, &s.ETag, &s.Modified); e != nil {
			return nil, e
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

type NewsArticle struct {
	ItemKey   string `json:"-"`
	ID        int64  `json:"id"`
	SourceID  int64  `json:"sourceId"`
	URL       string `json:"url"`
	Title     string `json:"title"`
	Summary   string `json:"summary"`
	Published int64  `json:"published"`
	Source    string `json:"source"`
	Category  string `json:"category"`
	Language  string `json:"language"`
	Initial   string `json:"initial"`
}

func ListNews(page int, keyword, category, language, source string) ([]NewsArticle, int64, error) {
	where := " WHERE s.enabled=1"
	args := []any{}
	if keyword != "" {
		where += ` AND (a.title LIKE ? ESCAPE '\' OR a.summary LIKE ? ESCAPE '\' OR s.name LIKE ? ESCAPE '\')`
		k := "%" + strings.NewReplacer("\\", "\\\\", "%", "\\%", "_", "\\_").Replace(keyword) + "%"
		args = append(args, k, k, k)
	}
	for _, f := range []struct{ v, col string }{{category, "s.category"}, {language, "s.language"}, {source, "s.id"}} {
		if f.v != "" {
			where += " AND " + f.col + "=?"
			args = append(args, f.v)
		}
	}
	from := ` FROM md_news_articles a JOIN md_news_sources s ON s.id=a.source_id`
	var total int64
	if e := DB.QueryRow("SELECT COUNT(*)"+from+where, args...).Scan(&total); e != nil {
		return nil, 0, e
	}
	args = append(args, 15, (page-1)*15)
	rows, e := DB.Query(`SELECT id,source_id,url,title,summary,published,name,category,language FROM (
 SELECT a.id,a.source_id,a.url,a.title,a.summary,a.published,s.name,s.category,s.language,
 ROW_NUMBER() OVER (PARTITION BY a.source_id ORDER BY a.published DESC,a.id DESC) AS source_position`+from+where+`
 ) ORDER BY (published>0) DESC,source_position,published DESC,id DESC LIMIT ? OFFSET ?`, args...)
	if e != nil {
		return nil, 0, e
	}
	defer rows.Close()
	out := []NewsArticle{}
	for rows.Next() {
		var a NewsArticle
		if e = rows.Scan(&a.ID, &a.SourceID, &a.URL, &a.Title, &a.Summary, &a.Published, &a.Source, &a.Category, &a.Language); e != nil {
			return nil, 0, e
		}
		r := []rune(a.Source)
		if len(r) > 0 {
			a.Initial = string(r[0])
		}
		out = append(out, a)
	}
	return out, total, rows.Err()
}

// TrimNewsCategories distributes the category cap in rounds across sources,
// keeping each source's newest articles. Active sources take priority.
// Bookmarks are separate records and are never deleted by this cap.
func TrimNewsCategories(limit int) error {
	if limit < 1 {
		return errors.New("invalid news category limit")
	}
	_, err := DB.Exec(`DELETE FROM md_news_articles WHERE id IN (
 SELECT id FROM (
 SELECT id,ROW_NUMBER() OVER (PARTITION BY category ORDER BY enabled DESC,(published>0) DESC,source_position,published DESC,id DESC) AS position FROM (
 SELECT a.id,a.published,s.category,s.enabled,
 ROW_NUMBER() OVER (PARTITION BY a.source_id ORDER BY a.published DESC,a.id DESC) AS source_position
 FROM md_news_articles a JOIN md_news_sources s ON s.id=a.source_id
 )) WHERE position > ?
 )`, limit)
	return err
}
