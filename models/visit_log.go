package models

import (
	"time"
)

type VisitLog struct {
	VisitID   int64     `json:"visit_id"`
	IP        string    `json:"ip"`
	Path      string    `json:"path"`
	MemberID  int64     `json:"member_id"`
	VisitTime time.Time `json:"visit_time"`
	Account   string    `json:"account"`
}

type VisitStats struct {
	TotalVisits int64 `json:"total_visits"`
	UniqueIPs   int64 `json:"unique_ips"`
}

type VisitTrendPoint struct {
	Time      string `json:"time"`
	PageViews int64  `json:"page_views"`
	UniqueIPs int64  `json:"unique_ips"`
}

var visitLogChan = make(chan VisitLog, 256)

func init() {
	go visitLogWriter()
}

func visitLogWriter() {
	batch := make([]VisitLog, 0, 32)
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case l := <-visitLogChan:
			batch = append(batch, l)
			if len(batch) >= 32 {
				flushVisitLogs(batch)
				batch = batch[:0]
			}
		case <-ticker.C:
			if len(batch) > 0 {
				flushVisitLogs(batch)
				batch = batch[:0]
			}
		}
	}
}

func flushVisitLogs(logs []VisitLog) {
	tx, err := DB.Begin()
	if err != nil {
		return
	}
	// Upsert visit_log
	logStmt, err := tx.Prepare("INSERT INTO md_visit_log (ip, path, member_id, visit_time) VALUES (?, ?, ?, ?) ON CONFLICT(ip, member_id) DO UPDATE SET path = excluded.path, visit_time = excluded.visit_time")
	if err != nil {
		tx.Rollback()
		return
	}
	defer logStmt.Close()

	// Upsert visit_daily (increment page_views)
	dailyStmt, err := tx.Prepare("INSERT INTO md_visit_daily (date, page_views, unique_ips) VALUES (?, 1, 0) ON CONFLICT(date) DO UPDATE SET page_views = page_views + 1")
	if err != nil {
		tx.Rollback()
		return
	}
	defer dailyStmt.Close()

	// Track daily unique IPs
	ipStmt, err := tx.Prepare("INSERT OR IGNORE INTO md_visit_daily_ip (date, ip) VALUES (?, ?)")
	if err != nil {
		tx.Rollback()
		return
	}
	defer ipStmt.Close()

	// Collect affected dates for unique_ips recalc
	dates := make(map[string]bool)

	for _, l := range logs {
		dateStr := l.VisitTime.Format("2006-01-02")
		logStmt.Exec(l.IP, l.Path, l.MemberID, l.VisitTime.Format("2006-01-02 15:04:05"))
		dailyStmt.Exec(dateStr)
		ipStmt.Exec(dateStr, l.IP)
		dates[dateStr] = true
	}

	if err := tx.Commit(); err != nil {
		return
	}

	// Recalculate unique_ips for affected dates
	for date := range dates {
		recalcDailyUniqueIPs(date)
	}
}

func recalcDailyUniqueIPs(date string) {
	DB.Exec(`UPDATE md_visit_daily SET unique_ips = (SELECT COUNT(*) FROM md_visit_daily_ip WHERE date = ?) WHERE date = ?`, date, date)
}

func AsyncCreateVisitLog(ip, path string, memberID int64) {
	select {
	case visitLogChan <- VisitLog{IP: ip, Path: path, MemberID: memberID, VisitTime: time.Now()}:
	default:
	}
}

func GetVisitStats(since time.Time) (*VisitStats, error) {
	stats := &VisitStats{}
	err := DB.QueryRow(`
		SELECT COALESCE(SUM(page_views), 0), COALESCE(SUM(unique_ips), 0)
		FROM md_visit_daily WHERE date >= ?
	`, since.Format("2006-01-02")).Scan(&stats.TotalVisits, &stats.UniqueIPs)
	if err != nil {
		return nil, err
	}
	return stats, nil
}

func GetVisitTrend(since time.Time, timeBin string) ([]VisitTrendPoint, error) {
	var groupExpr string
	switch timeBin {
	case "hour":
		groupExpr = "strftime('%Y-%m-%d %H:00', date || ' 00:00:00')"
	default:
		groupExpr = "date"
	}

	rows, err := DB.Query(`
		SELECT `+groupExpr+` AS time_bin, SUM(page_views) AS pv, SUM(unique_ips) AS uv
		FROM md_visit_daily
		WHERE date >= ?
		GROUP BY time_bin
		ORDER BY time_bin
	`, since.Format("2006-01-02"))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var points []VisitTrendPoint
	for rows.Next() {
		var p VisitTrendPoint
		if err := rows.Scan(&p.Time, &p.PageViews, &p.UniqueIPs); err != nil {
			return nil, err
		}
		points = append(points, p)
	}
	return points, nil
}

func ListVisitLogsPaged(page, pageSize int) ([]VisitLog, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 50
	}

	var total int64
	DB.QueryRow("SELECT COUNT(*) FROM md_visit_log").Scan(&total)

	offset := (page - 1) * pageSize
	rows, err := DB.Query(
		"SELECT v.visit_id, v.ip, v.path, v.member_id, v.visit_time, COALESCE(m.account, '') FROM md_visit_log v LEFT JOIN md_members m ON v.member_id = m.member_id ORDER BY v.visit_time DESC LIMIT ? OFFSET ?",
		pageSize, offset,
	)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var logs []VisitLog
	for rows.Next() {
		var l VisitLog
		if err := rows.Scan(&l.VisitID, &l.IP, &l.Path, &l.MemberID, &l.VisitTime, &l.Account); err != nil {
			return nil, 0, err
		}
		logs = append(logs, l)
	}
	return logs, total, nil
}

