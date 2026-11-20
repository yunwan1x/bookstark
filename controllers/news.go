package controllers

import (
	"bookstark/models"
	"bookstark/services"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func AdminNews(c *gin.Context) {
	cfg, e := models.LoadNewsConfig()
	if e != nil {
		apiError(c, 500, "Unable to load news configuration")
		return
	}
	sources, e := models.NewsSources(false)
	if e != nil {
		apiError(c, 500, "Unable to load sources")
		return
	}
	rows, e := models.DB.Query(`SELECT id,kind,started,finished,status,added,failed,details FROM md_news_runs ORDER BY id DESC LIMIT 20`)
	if e != nil {
		apiError(c, 500, "Unable to load task history")
		return
	}
	defer rows.Close()
	runs := []gin.H{}
	for rows.Next() {
		var id, start, end int64
		var kind, status, details string
		var added, failed int
		if e = rows.Scan(&id, &kind, &start, &end, &status, &added, &failed, &details); e != nil {
			apiError(c, 500, "Unable to load history")
			return
		}
		runs = append(runs, gin.H{"id": id, "kind": kind, "started": start, "finished": end, "status": status, "added": added, "failed": failed, "details": details})
	}
	c.Header("Cache-Control", "no-store")
	apiSuccess(c, gin.H{"config": cfg, "sources": sources, "runs": runs, "running": services.NewsRunning(), "nextSync": nextNewsRun("sync", cfg.SyncEnabled, cfg.SyncHours*3600), "nextFetch": nextNewsRun("fetch", cfg.FetchEnabled, cfg.FetchMinutes*60)})
}
func nextNewsRun(kind string, enabled bool, interval int) int64 {
	if !enabled {
		return 0
	}
	n := services.NewsLastRun(kind)
	if n == 0 {
		return time.Now().Unix()
	}
	return n + int64(interval)
}
func SaveNewsConfiguration(c *gin.Context) {
	var cfg models.NewsConfig
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 32768)
	if c.ShouldBindJSON(&cfg) != nil {
		apiError(c, 400, "Invalid configuration")
		return
	}
	if e := services.ValidateNewsConfig(cfg); e != nil {
		apiError(c, 400, e.Error())
		return
	}
	if !services.LockNewsChanges() {
		apiError(c, 409, "Wait for the current news task to finish")
		return
	}
	defer services.UnlockNewsChanges()
	if e := models.SaveNewsConfig(cfg); e != nil {
		apiError(c, 500, "Unable to save configuration")
		return
	}
	apiSuccess(c, cfg)
}
func RunNewsJob(c *gin.Context) {
	var req struct {
		Kind     string `json:"kind"`
		SourceID int64  `json:"sourceId"`
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 1024)
	if c.ShouldBindJSON(&req) != nil || (req.Kind != "sync" && req.Kind != "fetch") || req.SourceID < 0 {
		apiError(c, 400, "Invalid task")
		return
	}
	if req.SourceID > 0 {
		var n int
		if models.DB.QueryRow("SELECT COUNT(*) FROM md_news_sources WHERE id=?", req.SourceID).Scan(&n) != nil || n == 0 {
			apiError(c, 404, "Source not found")
			return
		}
	}
	if e := services.BeginNewsJob(req.Kind, req.SourceID); e != nil {
		apiError(c, 409, e.Error())
		return
	}
	apiSuccess(c, gin.H{"running": true})
}
func UpdateNewsSources(c *gin.Context) {
	var req struct {
		IDs      []int64 `json:"ids"`
		Enabled  *bool   `json:"enabled"`
		Category *string `json:"category"`
		Language *string `json:"language"`
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 16384)
	if c.ShouldBindJSON(&req) != nil || len(req.IDs) == 0 || len(req.IDs) > 500 {
		apiError(c, 400, "Invalid source selection")
		return
	}
	if req.Category != nil && !models.ValidNewsCategory(*req.Category) || req.Language != nil && *req.Language != "zh" && *req.Language != "en" && *req.Language != "" {
		apiError(c, 400, "Invalid category or language")
		return
	}
	if !services.LockNewsChanges() {
		apiError(c, 409, "Wait for the current news task to finish")
		return
	}
	defer services.UnlockNewsChanges()
	set := []string{}
	args := []any{}
	if req.Enabled != nil {
		set = append(set, "enabled=?")
		args = append(args, *req.Enabled)
	}
	if req.Category != nil {
		set = append(set, "category=?", "edited=1")
		args = append(args, *req.Category)
	}
	if req.Language != nil {
		set = append(set, "language=?", "edited=1")
		args = append(args, *req.Language)
	}
	if len(set) == 0 {
		apiError(c, 400, "No changes")
		return
	}
	marks := []string{}
	for _, id := range req.IDs {
		if id <= 0 {
			apiError(c, 400, "Invalid source")
			return
		}
		marks = append(marks, "?")
		args = append(args, id)
	}
	if _, e := models.DB.Exec("UPDATE md_news_sources SET "+strings.Join(set, ",")+" WHERE id IN ("+strings.Join(marks, ",")+")", args...); e != nil {
		apiError(c, 500, "Unable to update sources")
		return
	}
	apiSuccess(c, nil)
}
func PublicNewsSources(c *gin.Context) {
	sources, e := models.NewsSources(true)
	if e != nil {
		apiError(c, 500, "Unable to load sources")
		return
	}
	items := []gin.H{}
	for _, s := range sources {
		domain := ""
		if u, e := url.Parse(s.URL); e == nil {
			domain = u.Hostname()
		}
		items = append(items, gin.H{"domain": domain, "id": s.ID, "name": s.Name, "category": s.Category, "language": s.Language, "lastSuccess": s.LastSuccess, "latestArticle": s.LatestArticle, "unavailable": s.Error != "" || s.Removed})
	}
	c.Header("Cache-Control", "public, max-age=60")
	apiSuccess(c, items)
}
func publicNewsData(c *gin.Context, data gin.H, page int, keyword, label string) (int64, error) {
	language := c.Query("language")
	if language != "zh" && language != "en" {
		language = ""
	}
	source := c.Query("source")
	if n, e := strconv.ParseInt(source, 10, 64); e != nil || n < 1 {
		source = ""
	}
	items, total, e := models.ListNews(page, keyword, label, language, source)
	data["News"], data["NewsLanguage"], data["NewsSource"] = items, language, source
	return total, e
}
