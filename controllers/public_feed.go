package controllers

import (
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"hash/fnv"
	"net/http"
	"net/url"
	"strconv"
)

type publicNavItem struct {
	Name, URL, Icon string
	Active          bool
}

func publicLabelIcon(name string) string {
	icons := []string{"fa-leaf", "fa-lightbulb", "fa-compass", "fa-code", "fa-flask", "fa-book", "fa-globe", "fa-puzzle-piece", "fa-palette", "fa-music", "fa-camera", "fa-bolt", "fa-seedling", "fa-shapes", "fa-cube", "fa-star"}
	h := fnv.New32a()
	_, _ = h.Write([]byte(name))
	return icons[int(h.Sum32())%len(icons)]
}

func PublicFeedPage(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	data := commonData(c, "public")
	kind, order, label, keyword := c.Query("type"), c.Query("sort"), c.Query("label"), c.Query("keyword")
	if kind != "article" && kind != "note" && kind != "book" && kind != "bookmark" {
		kind = "article"
	}
	if order != "updated" {
		order = "latest"
	}
	page, _ := strconv.Atoi(c.Query("page"))
	if page < 1 {
		page = 1
	}
	if page > 100000 {
		page = 100000
	}
	link := func(k, s, l string, p int) string {
		v := url.Values{"type": {k}, "sort": {s}, "page": {strconv.Itoa(p)}}
		if l != "" {
			v.Set("label", l)
		}
		if keyword != "" {
			v.Set("keyword", keyword)
		}
		return "/?" + v.Encode()
	}
	var items []models.ShareItem
	var total int64
	var err error
	if kind == "bookmark" {
		public := true
		query := models.BookmarkQuery{IsPublic: &public, WithAccount: true, Keyword: keyword, Page: page, PageSize: 15, PublicFeedSort: order}
		if label != "" {
			query.Labels = []string{label}
		}
		var result *models.BookmarkQueryResult
		result, err = models.QueryBookmarks(query)
		if err == nil {
			data["Bookmarks"] = result.Data
			total = int64(result.Total)
		}
	} else {
		items, total, err = models.ListSharesPaged(page, 15, keyword, kind, models.PublicFeedOptions{Label: label, Sort: order})
	}
	if err != nil {
		c.String(http.StatusInternalServerError, "Unable to load public content")
		return
	}
	labels, err := models.PublicFeedLabels(kind)
	if err != nil {
		c.String(http.StatusInternalServerError, "Unable to load public categories")
		return
	}
	categories := []publicNavItem{{Name: "", URL: link(kind, order, "", 1), Icon: "fa-border-all", Active: label == ""}}
	for _, l := range labels {
		categories = append(categories, publicNavItem{Name: l, URL: link(kind, order, l, 1), Icon: publicLabelIcon(l), Active: label == l})
	}
	books, _, _ := models.ListSharesPaged(1, 4, "", "book", models.PublicFeedOptions{Sort: "updated"})
	data["Items"], data["Categories"], data["PublicBooks"] = items, categories, books
	data["Type"], data["Sort"], data["Label"], data["Keyword"] = kind, order, label, keyword
	data["LatestURL"], data["UpdatedURL"] = link(kind, "latest", label, 1), link(kind, "updated", label, 1)
	data["Page"], data["Total"] = page, total
	if page > 1 {
		data["PrevURL"] = link(kind, order, label, page-1)
	}
	if int64(page*15) < total {
		data["NextURL"] = link(kind, order, label, page+1)
	}
	c.HTML(http.StatusOK, "public_feed.html", data)
}
