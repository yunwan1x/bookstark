package models

import (
	"fmt"
	"net/url"
	"strconv"
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
}

// ListHomeSections is a personal view, including for administrators: knowledge
// records are always scoped to their owner. Asset inventory is admin-only.
func ListHomeSections(memberID int64, admin bool, order string) ([]HomeSection, error) {
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
		if err := DB.QueryRow("SELECT COUNT(*) FROM ("+s.query+")", s.args...).Scan(&section.Total); err != nil {
			return nil, fmt.Errorf("home %s count: %w", s.key, err)
		}
		// The sort column is selected from constants above, never from raw input.
		rows, err := DB.Query("SELECT id, COALESCE(title,''), COALESCE(target,''), COALESCE(badge,''), COALESCE(substr(CAST(COALESCE("+column+",created) AS TEXT),1,10), '') FROM ("+s.query+") ORDER BY COALESCE("+column+",created) DESC, id DESC, target ASC LIMIT 10", s.args...)
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
