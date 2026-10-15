package models

import (
	"fmt"
	"net/url"
	"strconv"
	"time"
)

// HomeItem deliberately contains no content, passwords, tokens or credentials.
type HomeItem struct {
	ID    int64  `json:"id"`
	Title string `json:"title"`
	URL   string `json:"url"`
	Date  string `json:"date"`
	Badge string `json:"badge"`
}

type HomeSection struct {
	Key   string     `json:"key"`
	Total int        `json:"total"`
	Items []HomeItem `json:"items"`
	Dates []string   `json:"dates,omitempty"`
}

type HomeFilter struct {
	Start, End, Month string
	Limit             int
	Location          *time.Location
}

type HomeStats struct {
	Notes           int `json:"notes"`
	Articles        int `json:"articles"`
	PendingTasks    int `json:"pending_tasks"`
	CreatedThisWeek int `json:"created_this_week"`
}

// GetHomeStats counts owned records only, without content or duplicated nav/share entries.
// Weeks start on Monday in the application timezone; the upper bound excludes future dates.
func GetHomeStats(memberID int64, now time.Time) (HomeStats, error) {
	start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	start = start.AddDate(0, 0, -(int(start.Weekday())+6)%7)
	var stats HomeStats
	err := DB.QueryRow(`WITH raw AS (
		SELECT COALESCE(blog_type,'article') kind, 0 done, CAST(create_time AS TEXT) created FROM md_blogs WHERE member_id=?
		UNION ALL SELECT 'task', done, CAST(create_time AS TEXT) FROM md_tasks WHERE member_id=?
		UNION ALL SELECT 'book', 0, CAST(create_time AS TEXT) FROM md_books WHERE member_id=?
		UNION ALL SELECT 'bookmark', 0, CAST(create_time AS TEXT) FROM md_bookmark WHERE member_id=?
		UNION ALL SELECT 'topic', 0, CAST(create_time AS TEXT) FROM md_topics WHERE member_id=?
	), offsets AS (
		SELECT *, MAX(instr(created,' +'),instr(created,' -')) pos FROM raw
	), records AS (
		SELECT kind, done, CASE
		WHEN pos>0 THEN substr(created,1,pos-1)||substr(created,pos+1,3)||':'||substr(created,pos+4,2)
		WHEN length(created)=19 THEN created||?
		ELSE created END created FROM offsets
	) SELECT
		COALESCE(SUM(kind='note'),0), COALESCE(SUM(kind='article'),0),
		COALESCE(SUM(kind='task' AND done=0),0),
		COALESCE(SUM(julianday(created)>=julianday(?) AND julianday(created)<=julianday(?)),0)
		FROM records`, memberID, memberID, memberID, memberID, memberID, now.Format("-07:00"), start.Format(time.RFC3339), now.Format(time.RFC3339)).
		Scan(&stats.Notes, &stats.Articles, &stats.PendingTasks, &stats.CreatedThisWeek)
	return stats, err
}

// ListHomeSections is a personal view, including for administrators: knowledge
// records are always scoped to their owner. Asset inventory is admin-only.
func ListHomeSections(memberID int64, admin bool, order string, filters ...HomeFilter) ([]HomeSection, error) {
	column := "modified"
	if order == "created" {
		column = "created"
	}
	type source struct {
		key, query string
		args       []any
	}
	owned := []any{memberID}
	sources := []source{
		{"notes", `SELECT blog_id id, blog_title title, '' target, CASE WHEN password != '' THEN '加密' ELSE '' END badge, create_time created, modify_time modified FROM md_blogs WHERE member_id=? AND blog_type='note'`, owned},
		{"articles", `SELECT blog_id id, blog_title title, '' target, CASE WHEN password != '' THEN '加密' ELSE editor_type END badge, create_time created, modify_time modified FROM md_blogs WHERE member_id=? AND COALESCE(blog_type,'article')='article'`, owned},
		{"tasks", `SELECT task_id id, content title, '' target, CASE WHEN done=1 THEN '已完成' ELSE '待处理' END badge, create_time created, modify_time modified FROM md_tasks WHERE member_id=?`, owned},
		{"books", `SELECT book_id id, book_name title, identify target, '' badge, create_time created, modify_time modified FROM md_books WHERE member_id=?`, owned},
		{"bookmarks", `SELECT bookmark_id id, title, url target, '' badge, create_time created, modify_time modified FROM md_bookmark WHERE member_id=?`, owned},
		{"topics", `SELECT topic_id id, title, '' target, '' badge, create_time created, modify_time modified FROM md_topics WHERE member_id=?`, owned},
		{"nav", `SELECT bookmark_id id, title, '' target, '' badge, create_time created, modify_time modified FROM md_bookmark WHERE member_id=? AND nav_visible=1`, owned},
		{"shares", `SELECT s.share_id id, COALESCE(b.blog_title,k.book_name) title, s.share_identify target, s.share_type badge, s.share_time created, COALESCE(b.modify_time,k.modify_time,s.share_time) modified FROM md_shares s LEFT JOIN md_blogs b ON s.share_type='blog' AND s.target_id=b.blog_id AND b.member_id=s.member_id LEFT JOIN md_books k ON s.share_type='book' AND s.target_id=k.book_id AND k.member_id=s.member_id WHERE s.member_id=? AND ((b.blog_id IS NOT NULL AND b.visibility=1) OR k.book_id IS NOT NULL)`, owned},
	}
	if admin {
		sources = append(sources, source{"assets", `SELECT host_id id, name title, 'ssh' target, 'ssh' badge, create_time created, modify_time modified FROM md_asset_ssh_hosts UNION ALL SELECT server_id id, name title, 'webdav' target, 'webdav' badge, create_time created, modify_time modified FROM md_asset_webdav_servers`, nil})
	}
	sections := make([]HomeSection, 0, len(sources))
	for _, s := range sources {
		section := HomeSection{Key: s.key, Items: []HomeItem{}}
		query := "SELECT *, substr(CAST(COALESCE(" + column + ",created) AS TEXT),1,10) day, COALESCE(" + column + ",created) stamp FROM (" + s.query + ")"
		args := append([]any{}, s.args...)
		limit := 10
		where := ""
		if len(filters) > 0 {
			f := filters[0]
			if f.Limit >= 1 && f.Limit <= 50 {
				limit = f.Limit
			}
			loc := f.Location
			if loc == nil {
				loc = time.Local
			}
			offset := time.Now().In(loc).Format("-07:00")
			// SQLite accepts RFC3339, but Go time.Time values may include an
			// offset and zone suffix. Interpret legacy timezone-less values locally.
			query = `WITH raw AS (SELECT *, CAST(COALESCE(` + column + `,created) AS TEXT) value FROM (` + s.query + `)),
			 offsets AS (SELECT *, MAX(instr(value,' +'),instr(value,' -')) pos FROM raw),
			 normalized AS (SELECT *, CASE WHEN pos>0 THEN substr(value,1,pos-1)||substr(value,pos+1,3)||':'||substr(value,pos+4,2)
			 WHEN length(value)=19 THEN value||? WHEN length(value)=10 THEN value||'T00:00:00'||? ELSE value END moment FROM offsets)
			 SELECT *, date(moment,?) day, julianday(moment) stamp FROM normalized`
			args = append(args, offset, offset, offset)
			if f.Month != "" {
				monthRows, err := DB.Query("SELECT DISTINCT day FROM ("+query+") WHERE substr(day,1,7)=? ORDER BY day", append(append([]any{}, args...), f.Month)...)
				if err != nil {
					return nil, err
				}
				for monthRows.Next() {
					var day string
					if err := monthRows.Scan(&day); err != nil {
						monthRows.Close()
						return nil, err
					}
					section.Dates = append(section.Dates, day)
				}
				err = monthRows.Err()
				monthRows.Close()
				if err != nil {
					return nil, err
				}
			}
			if f.Start != "" && f.End != "" {
				where = " WHERE day>=? AND day<=?"
				args = append(args, f.Start, f.End)
			}
		}
		if err := DB.QueryRow("SELECT COUNT(*) FROM ("+query+")"+where, args...).Scan(&section.Total); err != nil {
			return nil, fmt.Errorf("home %s count: %w", s.key, err)
		}
		// The sort column is selected from constants above, never from raw input.
		rows, err := DB.Query("SELECT id, COALESCE(title,''), COALESCE(target,''), COALESCE(badge,''), COALESCE(day,'') FROM ("+query+")"+where+" ORDER BY stamp DESC, id DESC, target ASC LIMIT ?", append(args, limit)...)
		if err != nil {
			return nil, fmt.Errorf("home %s: %w", s.key, err)
		}
		for rows.Next() {
			var item HomeItem
			var target string
			if err = rows.Scan(&item.ID, &item.Title, &target, &item.Badge, &item.Date); err != nil {
				rows.Close()
				return nil, err
			}
			id := strconv.FormatInt(item.ID, 10)
			switch s.key {
			case "notes":
				item.URL = "/notes?tab=notes&id=" + id
			case "articles":
				item.URL = "/notes?tab=articles&id=" + id
			case "tasks":
				item.URL = "/notes?tab=tasks&task_id=" + id
			case "books":
				item.URL = "/books/" + url.PathEscape(target) + "/edit"
			case "bookmarks":
				item.URL = target
			case "nav":
				item.URL = "/bookmarks?id=" + id
			case "topics":
				item.URL = "/topics?id=" + id
			case "shares":
				item.URL = "/shares/" + url.PathEscape(target)
			case "assets":
				if target == "webdav" {
					item.URL = "/admin/assets/webdav-servers/" + id + "/files"
				} else {
					item.URL = "/admin/assets/ssh-hosts/" + id + "/files"
				}
			}
			section.Items = append(section.Items, item)
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return nil, err
		}
		sections = append(sections, section)
	}
	return sections, nil
}
