package models

import (
	"fmt"
	"net/url"
	"path"
	"sort"
	"strings"
	"time"
)

type FriendLink struct {
	GroupName   string    `json:"group_name"`
	GroupOrder  int       `json:"group_order"`
	QRCode      string    `json:"qr_code"`
	Description string    `json:"description"`
	LinkID      int64     `json:"link_id"`
	LinkName    string    `json:"link_name"`
	LinkURL     string    `json:"link_url"`
	SortWeight  int       `json:"sort_weight"`
	IsEnabled   int       `json:"is_enabled"`
	CreateTime  time.Time `json:"create_time"`
	ModifyTime  time.Time `json:"modify_time"`
	CreatedBy   int64     `json:"created_by"`
	UpdatedBy   int64     `json:"updated_by"`
}

func (f *FriendLink) Normalize() {
	f.LinkName = strings.TrimSpace(f.LinkName)
	f.LinkURL = strings.TrimSpace(f.LinkURL)
	f.GroupName = strings.TrimSpace(f.GroupName)
	f.QRCode = strings.TrimSpace(f.QRCode)
	f.Description = strings.TrimSpace(f.Description)
	if f.IsEnabled != 0 {
		f.IsEnabled = 1
	}
}

func (f FriendLink) Validate() error {
	if len(f.LinkName) > 100 || len(f.LinkURL) > 2048 || len(f.GroupName) > 100 || len(f.Description) > 1000 || len(f.QRCode) > 2048 {
		return fmt.Errorf("名称、地址或说明超出长度限制")
	}
	if f.QRCode != "" {
		u, err := url.Parse(f.QRCode)
		if err != nil || u.IsAbs() || u.Host != "" || u.RawQuery != "" || u.Fragment != "" || u.RawPath != "" || !strings.HasPrefix(u.Path, "/upload-files/") || strings.Contains(u.Path, "\\") || path.Clean(u.Path) != u.Path {
			return fmt.Errorf("二维码必须使用本站上传的图片")
		}
		switch strings.ToLower(path.Ext(u.Path)) {
		case ".png", ".jpg", ".jpeg", ".webp", ".gif":
		default:
			return fmt.Errorf("二维码图片格式不支持")
		}
	}
	if strings.TrimSpace(f.LinkName) == "" {
		return fmt.Errorf("链接名称不能为空")
	}
	if strings.TrimSpace(f.LinkURL) == "" {
		if f.QRCode != "" {
			return nil
		}
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

const friendLinkSelect = `SELECT f.link_id, f.link_name, f.link_url, f.sort_weight, f.is_enabled, f.create_time, f.modify_time, f.created_by, f.updated_by, COALESCE(d.group_name,''), COALESCE(d.group_order,0), COALESCE(d.qr_code,''), COALESCE(d.description,'') FROM md_friend_links f LEFT JOIN md_friend_link_details d ON f.link_id=d.link_id `

func ListFriendLinks() ([]FriendLink, error) {
	return listFriendLinks(false)
}

func listFriendLinks(enabled bool) ([]FriendLink, error) {
	query := friendLinkSelect
	if enabled {
		query += " WHERE f.is_enabled=1 "
	}
	rows, err := DB.Query(query + " ORDER BY COALESCE(d.group_order,0), f.sort_weight, f.link_id LIMIT 200")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []FriendLink
	for rows.Next() {
		var item FriendLink
		if err := rows.Scan(&item.LinkID, &item.LinkName, &item.LinkURL, &item.SortWeight, &item.IsEnabled, &item.CreateTime, &item.ModifyTime, &item.CreatedBy, &item.UpdatedBy, &item.GroupName, &item.GroupOrder, &item.QRCode, &item.Description); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func ListEnabledFriendLinks() ([]FriendLink, error) { return listFriendLinks(true) }

func ReplaceFriendLinks(items []FriendLink, operatorID int64) error {
	if len(items) > 200 {
		return fmt.Errorf("页脚最多支持200个条目")
	}
	for i := range items {
		items[i].Normalize()
		if err := items[i].Validate(); err != nil {
			return err
		}
	}

	sort.SliceStable(items, func(i, j int) bool {
		if items[i].SortWeight == items[j].SortWeight {
			return false
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
		result, err := tx.Exec(`INSERT INTO md_friend_links (link_name, link_url, sort_weight, is_enabled, create_time, modify_time, created_by, updated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, item.LinkName, item.LinkURL, item.SortWeight, item.IsEnabled, now, now, operatorID, operatorID)
		if err != nil {
			return err
		}
		id, err := result.LastInsertId()
		if err != nil {
			return err
		}
		if _, err = tx.Exec(`INSERT INTO md_friend_link_details(link_id,group_name,group_order,qr_code,description) VALUES(?,?,?,?,?)`, id, item.GroupName, item.GroupOrder, item.QRCode, item.Description); err != nil {
			return err
		}
	}

	return tx.Commit()
}

type FooterGroup struct {
	HasQR bool
	Name  string
	Order int
	Links []FriendLink
}

// Group already-filtered links without additional database queries.
func GroupFriendLinks(items []FriendLink) []FooterGroup {
	groups := []FooterGroup{}
	indexes := map[string]int{}
	for _, item := range items {
		if item.IsEnabled != 1 {
			continue
		}
		index, ok := indexes[item.GroupName]
		if !ok {
			index = len(groups)
			indexes[item.GroupName] = index
			groups = append(groups, FooterGroup{Name: item.GroupName, Order: item.GroupOrder})
		}
		groups[index].Links = append(groups[index].Links, item)
		groups[index].HasQR = groups[index].HasQR || item.QRCode != ""
	}
	sort.SliceStable(groups, func(i, j int) bool { return groups[i].Order < groups[j].Order })
	return groups
}
