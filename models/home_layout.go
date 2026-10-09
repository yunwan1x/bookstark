package models

import (
	"database/sql"
	"encoding/json"
	"errors"
)

type HomeLayoutItem struct {
	Key    string `json:"key"`
	Width  int    `json:"width"`
	Hidden bool   `json:"hidden"`
}

var homeLayoutKeys = []string{"notes", "articles", "tasks", "books", "bookmarks", "topics", "nav", "shares", "assets"}

// Width 3 means full row on every multi-column screen. Missing modules use defaults.
func NormalizeHomeLayout(items []HomeLayoutItem) ([]HomeLayoutItem, error) {
	if len(items) > len(homeLayoutKeys) {
		return nil, errors.New("invalid home layout")
	}
	known := map[string]bool{}
	for _, key := range homeLayoutKeys {
		known[key] = true
	}
	seen := map[string]bool{}
	result := make([]HomeLayoutItem, 0, len(homeLayoutKeys))
	for _, item := range items {
		if !known[item.Key] || seen[item.Key] || item.Width < 1 || item.Width > 3 {
			return nil, errors.New("invalid home layout")
		}
		seen[item.Key] = true
		result = append(result, item)
	}
	for _, key := range homeLayoutKeys {
		if !seen[key] {
			result = append(result, HomeLayoutItem{Key: key, Width: 1})
		}
	}
	return result, nil
}

func GetHomeLayout(memberID int64) ([]HomeLayoutItem, error) {
	var raw string
	err := DB.QueryRow("SELECT layout FROM md_home_layouts WHERE member_id=?", memberID).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var items []HomeLayoutItem
	if err = json.Unmarshal([]byte(raw), &items); err != nil {
		return nil, err
	}
	return NormalizeHomeLayout(items)
}

func SaveHomeLayout(memberID int64, items []HomeLayoutItem) error {
	items, err := NormalizeHomeLayout(items)
	if err != nil {
		return err
	}
	raw, err := json.Marshal(items)
	if err != nil {
		return err
	}
	_, err = DB.Exec("INSERT INTO md_home_layouts(member_id,layout) VALUES(?,?) ON CONFLICT(member_id) DO UPDATE SET layout=excluded.layout", memberID, string(raw))
	return err
}
