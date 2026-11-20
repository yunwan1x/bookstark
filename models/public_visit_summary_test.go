package models

import (
	"strings"
	"testing"
	"time"
)

func TestPublicVisitSummary(t *testing.T) {
	initAssetTestDB(t)
	now := time.Date(2026, 11, 20, 12, 0, 0, 0, time.UTC)
	for _, q := range []string{
		`INSERT INTO md_visit_daily(date,page_views,unique_ips) VALUES ('2026-11-18',4,1),('2026-11-20',9,2),('2026-10-01',7,1)`,
		`INSERT INTO md_visit_daily_ip(date,ip) VALUES ('2026-11-18','a'),('2026-11-20','a'),('2026-11-20','b'),('2026-10-01','a')`,
	} {
		if _, err := DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	s, err := GetPublicVisitSummary(now)
	if err != nil {
		t.Fatal(err)
	}
	if s.TodayViews != 9 || s.TodayVisitors != 2 || s.TotalViews != 20 || s.TotalVisitors != 2 {
		t.Fatalf("wrong aggregates: %+v", s)
	}
	pts := strings.Fields(s.TrendPoints)
	if len(pts) != 7 || pts[0] != "4.0,52.0" || pts[6] != "256.0,8.0" {
		t.Fatalf("bad seven-day chart %s", s.TrendPoints)
	}
	if _, err = DB.Exec(`DELETE FROM md_visit_daily`); err != nil {
		t.Fatal(err)
	}
	if _, err = DB.Exec(`DELETE FROM md_visit_daily_ip`); err != nil {
		t.Fatal(err)
	}
	s, err = GetPublicVisitSummary(now)
	if err != nil || s.TotalViews != 0 || s.TotalVisitors != 0 || strings.Contains(s.TrendPoints, "NaN") {
		t.Fatalf("empty state: %+v %v", s, err)
	}
}
