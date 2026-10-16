package models

import (
	"testing"
	"time"
)

func TestHomeDateFilterTimezoneAndLimit(t *testing.T) {
	initAssetTestDB(t)
	loc := time.FixedZone("east", 8*60*60)
	for _, row := range []struct{ name, created, modified string }{
		{"before", "2026-10-14T15:59:59Z", "2026-10-14T15:59:59Z"},
		{"start", "2026-10-14T16:00:00Z", "2026-10-14T16:00:00Z"},
		{"local", "2026-10-15 12:00:00", "2026-10-15 12:00:00"},
		{"go-time", "2026-10-15 23:59:59 +0800 CST", "2026-10-15 23:59:59 +0800 CST"},
		{"end", "2026-10-15T16:00:00Z", "2026-10-15T16:00:00Z"},
		{"updated", "2026-10-01 10:00:00", "2026-10-15 18:00:00"},
	} {
		if _, err := DB.Exec(`INSERT INTO md_blogs(blog_title,blog_identify,blog_type,member_id,create_time,modify_time) VALUES(?,?,'note',1,?,?)`, row.name, row.name, row.created, row.modified); err != nil {
			t.Fatal(err)
		}
	}
	filter := HomeFilter{Start: "2026-10-15", End: "2026-10-15", Month: "2026-11", Limit: 2, Location: loc, ActivityStart: "2026-10-14", ActivityEnd: "2026-10-16"}
	for _, order := range []string{"created", "updated"} {
		sections, err := ListHomeSections(1, false, order, filter)
		if err != nil {
			t.Fatal(err)
		}
		want := 3
		if order == "updated" {
			want = 4
		}
		notes := sections[0]
		if notes.Activity["2026-10-15"] != want || notes.Activity["2026-10-14"] != 1 || notes.Activity["2026-10-16"] != 1 || len(notes.Dates) != 0 {
			t.Fatalf("activity must ignore item limit, date filter and displayed month: %+v", notes)
		}
		if notes.Total != want || len(notes.Items) != 2 || notes.Items[0].Title != "go-time" {
			t.Fatalf("%s: %+v", order, notes)
		}
		for _, item := range notes.Items {
			if item.Date != "2026-10-15" {
				t.Fatal(item)
			}
		}
	}
	sections, err := ListHomeSections(100, false, "updated", filter)
	if err != nil {
		t.Fatal(err)
	}
	for _, section := range sections {
		if section.Total != 0 || len(section.Dates) != 0 || len(section.Activity) != 0 {
			t.Fatalf("owner data leaked: %+v", section)
		}
	}
	// An upper bound includes all older content, not merely the selected day.
	cutoff := HomeFilter{End: "2026-10-15", Month: "2026-10", Limit: 50, Location: loc}
	for _, order := range []string{"updated", "created"} {
		sections, err = ListHomeSections(1, false, order, cutoff)
		if err != nil || sections[0].Total != 5 {
			t.Fatal(sections, err)
		}
		for _, item := range sections[0].Items {
			if item.Date > cutoff.End {
				t.Fatal("future item passed cutoff", item)
			}
		}
		if sections[0].Activity["2026-10-16"] != 1 {
			t.Fatal("calendar heatmap must be independent of cutoff", sections[0])
		}
	}
}
