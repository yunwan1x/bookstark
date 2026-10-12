package controllers

import (
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"hash/fnv"
	"net/http"
	"net/url"
	"sort"
	"strconv"
)

type publicNavItem struct {
	Name, URL, Icon string
	Active          bool
}

// Distinct glyphs in the bundled Font Awesome solid font; excludes the All icon.
var publicLabelIcons = []string{
	"fa-leaf", "fa-lightbulb", "fa-compass", "fa-code", "fa-flask",
	"fa-book", "fa-globe", "fa-puzzle-piece", "fa-palette", "fa-music",
	"fa-camera", "fa-bolt", "fa-seedling", "fa-shapes", "fa-cube",
	"fa-star", "fa-heart", "fa-brain", "fa-atom", "fa-rocket",
	"fa-anchor", "fa-apple-whole", "fa-award", "fa-baby", "fa-bicycle",
	"fa-binoculars", "fa-briefcase", "fa-bug", "fa-building", "fa-bullseye",
	"fa-bus", "fa-calculator", "fa-calendar", "fa-car", "fa-carrot",
	"fa-cat", "fa-certificate", "fa-chess", "fa-cloud", "fa-clover",
	"fa-coffee", "fa-coins", "fa-comment", "fa-computer", "fa-cookie",
	"fa-crown", "fa-database", "fa-desktop", "fa-diamond", "fa-dice",
	"fa-dog", "fa-dragon", "fa-droplet", "fa-drum", "fa-earth-americas",
	"fa-envelope", "fa-eye", "fa-fan", "fa-feather", "fa-film",
	"fa-fire", "fa-fish", "fa-flag", "fa-frog", "fa-gamepad",
	"fa-gauge", "fa-gem", "fa-gift", "fa-graduation-cap", "fa-guitar",
	"fa-hammer", "fa-hand", "fa-handshake", "fa-headphones", "fa-helicopter",
	"fa-house", "fa-key", "fa-landmark", "fa-language", "fa-laptop",
	"fa-layer-group", "fa-lemon", "fa-life-ring", "fa-magnet", "fa-map",
	"fa-medal", "fa-microscope", "fa-moon", "fa-mountain", "fa-mug-hot",
	"fa-newspaper", "fa-paintbrush", "fa-paper-plane", "fa-paw", "fa-pen",
	"fa-pencil", "fa-phone", "fa-plane", "fa-plug", "fa-robot",
}

func assignPublicLabelIcons(labels []string) map[string]string {
	ordered := append([]string(nil), labels...)
	sort.Strings(ordered) // Reordering the same tags must not change their icons.
	assigned := make(map[string]string, len(labels))
	used := make(map[string]bool, len(labels))
	for _, name := range ordered {
		if _, ok := assigned[name]; ok {
			continue
		}
		h := fnv.New32a()
		_, _ = h.Write([]byte(name))
		start := int(h.Sum32()) % len(publicLabelIcons)
		for offset := 0; offset < len(publicLabelIcons); offset++ {
			icon := publicLabelIcons[(start+offset)%len(publicLabelIcons)]
			if !used[icon] {
				assigned[name] = icon
				used[icon] = true
				break
			}
		}
	}
	return assigned
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
	icons := assignPublicLabelIcons(labels)
	for _, l := range labels {
		categories = append(categories, publicNavItem{Name: l, URL: link(kind, order, l, 1), Icon: icons[l], Active: label == l})
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
