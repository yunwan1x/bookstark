package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"crypto/sha256"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"hash/fnv"
	"html/template"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
)

type publicNavItem struct {
	Name, URL, Icon string
	Active          bool
}

type publicFeedManagement struct {
	EditURL string
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
	c.Header("Vary", "X-BookStark-Feed")
	partial := c.GetHeader("X-BookStark-Feed") == "content"
	data := commonData(c, "shares")
	data["Background"] = nil
	data["ShareCommentsEnabled"] = models.ShareCommentsEnabled()
	data["ShareCommentMaxLength"] = models.ShareCommentMaxLength()
	data["ShareCommentGuestName"] = ""
	if middleware.GetMemberID(c) == 0 {
		data["ShareCommentGuestName"] = strings.TrimSpace(c.ClientIP())
	}
	returnURL := "/shares"
	if c.Request.URL.RawQuery != "" {
		returnURL += "?" + c.Request.URL.RawQuery
	}
	data["LoginURL"] = "/login?next=" + url.QueryEscape(returnURL)
	kind, order, label, keyword := c.Query("type"), c.Query("sort"), c.Query("label"), c.Query("keyword")
	if kind == "" {
		kind = c.Query("tab")
	}
	if kind != "article" && kind != "note" && kind != "book" && kind != "bookmark" && kind != "news" {
		kind = "news"
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
		if keyword != "" && k == kind {
			v.Set("keyword", keyword)
		}
		if k == "news" && kind == "news" {
			for _, key := range []string{"language", "source"} {
				if value := c.Query(key); value != "" {
					v.Set(key, value)
				}
			}
		}
		return "/shares?" + v.Encode()
	}
	var items []models.ShareItem
	var total int64
	var err error
	if kind == "news" {
		total, err = publicNewsData(c, data, page, keyword, label)
	} else if kind == "bookmark" {
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
	management := map[string]*publicFeedManagement{}
	notes := map[string]*models.ShareDetail{}
	memberID := middleware.GetMemberID(c)
	for _, item := range items {
		if item.BlogType == "note" && !item.HasPassword {
			if detail, err := models.GetShareDetailByIdentify(item.ShareIdentify); err == nil && !detail.HasPassword {
				notes[item.ShareIdentify] = detail
			}
		}
		if memberID <= 0 {
			continue
		}
		if item.ShareType == "blog" {
			var ownerID int64
			if err := models.DB.QueryRow("SELECT member_id FROM md_blogs WHERE blog_id=?", item.TargetID).Scan(&ownerID); err == nil && checkOwnership(c, ownerID) {
				tab := "articles"
				if item.BlogType == "note" {
					tab = "notes"
				}
				management[item.ShareIdentify] = &publicFeedManagement{EditURL: "/notes?tab=" + tab + "&id=" + strconv.FormatInt(item.TargetID, 10)}
			}
		} else if item.ShareType == "book" {
			if book, err := models.GetBookByID(item.TargetID); err == nil && checkOwnership(c, book.MemberID) {
				management[item.ShareIdentify] = &publicFeedManagement{EditURL: "/books/" + url.PathEscape(book.Identify) + "/edit"}
			}
		}
	}
	data["Management"] = management
	var labels []string
	if kind == "news" {
		labels = models.NewsCategories
	} else {
		labels, err = models.PublicFeedLabels(kind)
	}
	if err != nil {
		c.String(http.StatusInternalServerError, "Unable to load public categories")
		return
	}
	// Categories browse all sources; carrying a selected source into another
	// category produces an empty intersection. Keep source filters on pagination.
	categoryLink := func(category string) string {
		target := link(kind, order, category, 1)
		if kind == "news" {
			u, _ := url.Parse(target)
			query := u.Query()
			query.Del("source")
			u.RawQuery = query.Encode()
			return u.String()
		}
		return target
	}
	categories := []publicNavItem{{Name: "", URL: categoryLink(""), Icon: "fa-border-all", Active: label == ""}}
	icons := assignPublicLabelIcons(labels)
	if kind == "news" {
		icons = map[string]string{"ai-research": "fa-brain", "ai-tools": "fa-wand-magic-sparkles", "development": "fa-code", "design": "fa-palette", "finance": "fa-chart-line", "other": "fa-ellipsis"}
	}
	for _, l := range labels {
		display := l
		if kind == "news" {
			display = data["T"].(func(string) string)("news.cat_" + l)
		}
		categories = append(categories, publicNavItem{Name: display, URL: categoryLink(l), Icon: icons[l], Active: label == l})
	}
	data["SearchKey"] = "public.search_" + kind
	if !partial {
		data["VisitSummary"], _ = models.GetPublicVisitSummary(time.Now())
	}
	// Resolve the optional full player without loading/decompressing its HTML.
	var radioIdentify string
	if err := models.DB.QueryRow(`SELECT COALESCE(s.share_identify,b.blog_identify)
 FROM md_blogs b LEFT JOIN md_shares s ON s.share_type='blog' AND s.target_id=b.blog_id
 WHERE b.blog_identify=? AND b.visibility=1 AND COALESCE(b.password,'')='' LIMIT 1`, "radio-web").Scan(&radioIdentify); err == nil {
		data["RadioURL"] = "/shares/" + url.PathEscape(radioIdentify)
	}
	covers := map[string]struct {
		Theme, Title string
		Compact      bool
	}{}
	for _, item := range items {
		if item.ShareType != "book" {
			continue
		}
		title := strings.TrimSpace(item.Title)
		sum := sha256.Sum256([]byte(title))
		// Keep the main title on the cover; the adjacent heading retains the full name.
		short := strings.FieldsFunc(title, func(r rune) bool { return r == '—' || r == '·' || r == '：' || r == ':' })
		if len(short) > 0 {
			title = strings.TrimSpace(short[0])
		}
		compact := len([]rune(title)) <= 8
		for _, r := range title {
			if !unicode.Is(unicode.Han, r) {
				compact = false
				break
			}
		}
		covers[item.ShareIdentify] = struct {
			Theme, Title string
			Compact      bool
		}{[]string{"blue", "green", "amber", "indigo"}[sum[0]%4], title, compact}
	}
	data["BookCovers"] = covers
	if kind == "article" {
		data["EntryIcons"] = assignPublicArticleIcons(items)
	}
	data["Items"], data["Categories"] = items, categories
	typeURLs := map[string]string{}
	for _, k := range []string{"news", "article", "note", "book", "bookmark"} {
		l := ""
		if k == kind {
			l = label
		}
		typeURLs[k] = link(k, order, l, 1)
	}
	data["TypeURLs"] = typeURLs
	data["Type"], data["Sort"], data["Label"], data["Keyword"] = kind, order, label, keyword
	data["LatestURL"], data["UpdatedURL"] = link(kind, "latest", label, 1), link(kind, "updated", label, 1)
	data["Page"], data["Total"] = page, total
	if page > 1 {
		data["PrevURL"] = link(kind, order, label, page-1)
	}
	if int64(page*15) < total {
		data["NextURL"] = link(kind, order, label, page+1)
	}
	stateJSON, err := json.Marshal(gin.H{
		"notes": notes, "commentsEnabled": data["ShareCommentsEnabled"], "account": data["Account"],
		"guestName": data["ShareCommentGuestName"], "commentMaxLength": data["ShareCommentMaxLength"],
	})
	if err != nil {
		c.String(http.StatusInternalServerError, "Unable to load public content")
		return
	}
	data["PublicFeedStateJSON"] = template.JS(stateJSON)
	if partial {
		c.HTML(http.StatusOK, "public-feed-content", data)
		return
	}
	c.HTML(http.StatusOK, "public_feed.html", data)
}
