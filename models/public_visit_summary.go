package models

import (
	"fmt"
	"strings"
	"time"
)

// PublicVisitSummary exposes aggregates only, never visitor identities or paths.
type PublicVisitSummary struct {
	TodayViews, TodayVisitors, TotalViews, TotalVisitors int64
	TrendPoints                                          string
}

func GetPublicVisitSummary(now time.Time) (*PublicVisitSummary, error) {
	s := &PublicVisitSummary{}
	today := now.Format("2006-01-02")
	err := DB.QueryRow(`SELECT
 COALESCE(SUM(CASE WHEN date=? THEN page_views ELSE 0 END),0),
 COALESCE(SUM(CASE WHEN date=? THEN unique_ips ELSE 0 END),0),
 COALESCE(SUM(page_views),0),
 (SELECT COUNT(DISTINCT ip) FROM md_visit_daily_ip WHERE date<=?)
 FROM md_visit_daily WHERE date<=?`, today, today, today, today).Scan(&s.TodayViews, &s.TodayVisitors, &s.TotalViews, &s.TotalVisitors)
	if err != nil {
		return nil, err
	}
	rows, err := DB.Query(`SELECT date,page_views FROM md_visit_daily WHERE date BETWEEN ? AND ? ORDER BY date`, now.AddDate(0, 0, -6).Format("2006-01-02"), today)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	days := map[string]int64{}
	var peak int64 = 1
	for rows.Next() {
		var date string
		var views int64
		if err = rows.Scan(&date, &views); err != nil {
			return nil, err
		}
		days[date] = views
		if views > peak {
			peak = views
		}
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	points := make([]string, 7)
	for i := 0; i < 7; i++ {
		value := days[now.AddDate(0, 0, i-6).Format("2006-01-02")]
		points[i] = fmt.Sprintf("%.1f,%.1f", 4+float64(i)*42, 52-float64(value)/float64(peak)*44)
	}
	s.TrendPoints = strings.Join(points, " ")
	return s, nil
}
