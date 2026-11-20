package controllers

import (
	"bookstark/i18n"
	"bookstark/middleware"
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"log"
	"net/http"
	"strconv"
	"time"
)

func PersonalHomePage(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	data := commonData(c, "home")
	c.HTML(http.StatusOK, "home.html", data)
}

func HomeSummary(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	order := c.DefaultQuery("order", "updated")
	if order != "updated" && order != "created" {
		apiError(c, http.StatusBadRequest, "不支持的排序方式")
		return
	}
	start, end := c.Query("start"), c.Query("end")
	from, err1 := time.ParseInLocation("2006-01-02", start, time.Local)
	to, err2 := time.ParseInLocation("2006-01-02", end, time.Local)
	limit, err3 := strconv.Atoi(c.DefaultQuery("limit", "10"))
	month := c.DefaultQuery("month", time.Now().Format("2006-01"))
	calendarMonth, err4 := time.ParseInLocation("2006-01", month, time.Local)
	view := c.Query("view")
	// End alone means all content through that local date. Retain valid paired
	// ranges for existing API clients; the home UI only uses the upper bound.
	dateInvalid := (end != "" && err2 != nil) || (start != "" && (end == "" || err1 != nil || from.After(to) || to.Sub(from) > 366*24*time.Hour))
	if dateInvalid || err3 != nil || err4 != nil || (limit != 5 && limit != 10 && limit != 20 && limit != 50) || (view != "" && view != "day" && view != "week" && view != "month") {
		apiError(c, http.StatusBadRequest, i18n.T(i18n.GetLang(c), "home.invalid_filter"))
		return
	}
	now := time.Now()
	activityEnd := now.Format("2006-01-02")
	activityStart := now.AddDate(0, 0, -((int(now.Weekday())+6)%7)-11*7).Format("2006-01-02")
	// Explicit views fetch a bounded calendar window, independent of the
	// content cutoff/limit. Include complete Monday–Sunday weeks at month edges.
	if view == "month" {
		activityStart = time.Date(calendarMonth.Year(), 1, 1, 0, 0, 0, 0, time.Local).Format("2006-01-02")
		activityEnd = time.Date(calendarMonth.Year(), 12, 31, 0, 0, 0, 0, time.Local).Format("2006-01-02")
	} else if view != "" {
		first := calendarMonth.AddDate(0, 0, -((int(calendarMonth.Weekday()) + 6) % 7))
		last := calendarMonth.AddDate(0, 1, -1)
		last = last.AddDate(0, 0, (7-int(last.Weekday()))%7)
		activityStart, activityEnd = first.Format("2006-01-02"), last.Format("2006-01-02")
	}
	sections, err := models.ListHomeSections(middleware.GetMemberID(c), isAdmin(c), order, models.HomeFilter{Start: start, End: end, Month: month, Limit: limit, Location: time.Local, ActivityStart: activityStart, ActivityEnd: activityEnd})
	if err != nil {
		log.Printf("home summary: %v", err)
		apiError(c, http.StatusInternalServerError, "首页加载失败，请重试")
		return
	}
	activity := map[string]int{}
	for _, section := range sections {
		// Navigation and shares reference resources already counted above.
		if section.Key == "nav" || section.Key == "shares" {
			continue
		}
		for day, count := range section.Activity {
			activity[day] += count
		}
	}
	recent, err := models.ListRecentContent(middleware.GetMemberID(c), isAdmin(c))
	if err != nil {
		log.Printf("home recent content: %v", err)
		apiError(c, http.StatusInternalServerError, "首页加载失败，请重试")
		return
	}
	stats, err := models.GetHomeStats(middleware.GetMemberID(c), time.Now())
	if err != nil {
		log.Printf("home statistics: %v", err)
		apiError(c, http.StatusInternalServerError, "首页加载失败，请重试")
		return
	}
	c.JSON(http.StatusOK, gin.H{"stats": stats, "code": 0, "sections": sections, "start": start, "end": end, "limit": limit, "activity": activity, "activity_start": activityStart, "activity_end": activityEnd, "recent": recent})
}
