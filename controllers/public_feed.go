package controllers

import (
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"net/http"
	"net/url"
	"strconv"
)

type publicNavItem struct {
	Name, URL string
	Active    bool
}

func PublicFeedPage(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	data := commonData(c, "public")
	kind, order, label, keyword := c.Query("type"), c.Query("sort"), c.Query("label"), c.Query("keyword")
	if kind != "article" && kind != "note" && kind != "book" {
		kind = ""
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
	items, total, err := models.ListSharesPaged(page, 15, keyword, kind, models.PublicFeedOptions{Label: label, Sort: order})
	if err != nil {
		c.String(http.StatusInternalServerError, "Unable to load public content")
		return
	}
	labels, err := models.PublicFeedLabels()
	if err != nil {
		c.String(http.StatusInternalServerError, "Unable to load public categories")
		return
	}
	categories := []publicNavItem{{Name: "", URL: link(kind, order, "", 1), Active: label == ""}}
	for _, l := range labels {
		categories = append(categories, publicNavItem{Name: l, URL: link(kind, order, l, 1), Active: label == l})
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
