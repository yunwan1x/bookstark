package controllers

import (
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/models"
)

func DashboardPage(c *gin.Context) {
	data := commonData(c, "admin")
	c.HTML(http.StatusOK, "admin_dashboard.html", data)
}

func GetDashboardStats(c *gin.Context) {
	since, err := parseTimeRange(c.DefaultQuery("range", "7d"))
	if err != nil {
		apiError(c, http.StatusBadRequest, "无效的时间范围")
		return
	}

	stats, err := models.GetVisitStats(since)
	if err != nil {
		log.Printf("GetDashboardStats: %v", err)
		apiError(c, http.StatusInternalServerError, "获取统计失败")
		return
	}
	apiSuccess(c, stats)
}

func GetDashboardTrend(c *gin.Context) {
	since, err := parseTimeRange(c.DefaultQuery("range", "7d"))
	if err != nil {
		apiError(c, http.StatusBadRequest, "无效的时间范围")
		return
	}

	timeBin := "day"
	if r := c.DefaultQuery("range", "7d"); r == "24h" {
		timeBin = "hour"
	}

	points, err := models.GetVisitTrend(since, timeBin)
	if err != nil {
		log.Printf("GetDashboardTrend: %v", err)
		apiError(c, http.StatusInternalServerError, "获取趋势失败")
		return
	}
	apiSuccess(c, points)
}

func GetDashboardLogs(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("pageSize", "50"))

	logs, total, err := models.ListVisitLogsPaged(page, pageSize)
	if err != nil {
		log.Printf("GetDashboardLogs: %v", err)
		apiError(c, http.StatusInternalServerError, "获取访问记录失败")
		return
	}

	type logItem struct {
		models.VisitLog
		IPInfoURL string `json:"ip_info_url"`
	}
	items := make([]logItem, len(logs))
	for i, l := range logs {
		items[i] = logItem{
			VisitLog:  l,
			IPInfoURL: "https://ipinfo.io/" + l.IP,
		}
	}
	apiListSuccess(c, items, total, page, pageSize)
}

func parseTimeRange(r string) (time.Time, error) {
	switch r {
	case "24h":
		return time.Now().Add(-24 * time.Hour), nil
	case "7d":
		return time.Now().AddDate(0, 0, -7), nil
	case "30d":
		return time.Now().AddDate(0, 0, -30), nil
	case "90d":
		return time.Now().AddDate(0, 0, -90), nil
	default:
		return time.Now().AddDate(0, 0, -7), nil
	}
}