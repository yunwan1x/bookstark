package models

import (
	"database/sql"
	"fmt"
	"net/url"
	"sort"
	"strings"
	"time"
)

type FriendLink struct {
	LinkID     int64     `json:"link_id"`
	LinkName   string    `json:"link_name"`
	LinkURL    string    `json:"link_url"`
	SortWeight int       `json:"sort_weight"`
	IsEnabled  int       `json:"is_enabled"`
	CreateTime time.Time `json:"create_time"`
	ModifyTime time.Time `json:"modify_time"`
	CreatedBy  int64     `json:"created_by"`
	UpdatedBy  int64     `json:"updated_by"`
}

func (f *FriendLink) Normalize() {
	f.LinkName = strings.TrimSpace(f.LinkName)
	f.LinkURL = strings.TrimSpace(f.LinkURL)
	if f.IsEnabled != 0 {
		f.IsEnabled = 1
	}
}

func (f FriendLink) Validate() error {
	if strings.TrimSpace(f.LinkName) == "" {
		return fmt.Errorf("链接名称不能为空")
	}
	if strings.TrimSpace(f.LinkURL) == "" {
		return fmt.Errorf("链接地址不能为空")
	}
	u, err := url.Parse(strings.TrimSpace(f.LinkURL))
	if err != nil || u.Scheme == "" || u.Host == "" {
		return fmt.Errorf("链接地址格式不正确")
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return fmt.Errorf("链接地址必须以 http:// 或 https:// 开头")
	}
	return nil
}

func ListFriendLinks() ([]FriendLink, error) {
	rows, err := DB.Query(`SELECT link_id, link_name, link_url, sort_weight, is_enabled, create_time, modify_time, created_by, updated_by FROM md_friend_links ORDER BY sort_weight ASC, link_id ASC LIMIT 200`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []FriendLink
	for rows.Next() {
		var item FriendLink
		if err := rows.Scan(&item.LinkID, &item.LinkName, &item.LinkURL, &item.SortWeight, &item.IsEnabled, &item.CreateTime, &item.ModifyTime, &item.CreatedBy, &item.UpdatedBy); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func ListEnabledFriendLinks() ([]FriendLink, error) {
	rows, err := DB.Query(`SELECT link_id, link_name, link_url, sort_weight, is_enabled, create_time, modify_time, created_by, updated_by FROM md_friend_links WHERE is_enabled = 1 ORDER BY sort_weight ASC, link_id ASC LIMIT 200`)
	if err != nil {
		if err == sql.ErrNoRows {
			return []FriendLink{}, nil
		}
		return nil, err
	}
	defer rows.Close()

	var items []FriendLink
	for rows.Next() {
		var item FriendLink
		if err := rows.Scan(&item.LinkID, &item.LinkName, &item.LinkURL, &item.SortWeight, &item.IsEnabled, &item.CreateTime, &item.ModifyTime, &item.CreatedBy, &item.UpdatedBy); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func ReplaceFriendLinks(items []FriendLink, operatorID int64) error {
	for i := range items {
		items[i].Normalize()
		if err := items[i].Validate(); err != nil {
			return err
		}
	}

	sort.SliceStable(items, func(i, j int) bool {
		if items[i].SortWeight == items[j].SortWeight {
			return i < j
		}
		return items[i].SortWeight < items[j].SortWeight
	})

	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`DELETE FROM md_friend_links`); err != nil {
		return err
	}

	now := time.Now()
	for _, item := range items {
		if _, err := tx.Exec(`INSERT INTO md_friend_links (link_name, link_url, sort_weight, is_enabled, create_time, modify_time, created_by, updated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, item.LinkName, item.LinkURL, item.SortWeight, item.IsEnabled, now, now, operatorID, operatorID); err != nil {
			return err
		}
	}

	return tx.Commit()
}
