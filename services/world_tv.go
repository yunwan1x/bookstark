package services

import (
	"database/sql"
	"errors"
	"path/filepath"
	"sync"

	"bookstark/models"
	"bookstark/services/worldtv"
)

type worldTVStore struct{}

func (worldTVStore) Load() (string, error) {
	var s string
	e := models.DB.QueryRow("SELECT value FROM md_settings WHERE key = ?", worldtv.SettingKey).Scan(&s)
	if errors.Is(e, sql.ErrNoRows) {
		e = nil
	}
	return s, e
}
func (worldTVStore) Save(s string) error {
	return models.BatchUpdateSettings(map[string]string{worldtv.SettingKey: s})
}

var worldTVOnce sync.Once
var worldTVManager *worldtv.Manager

func WorldTV() *worldtv.Manager {
	worldTVOnce.Do(func() {
		worldTVManager = worldtv.New(worldTVStore{}, filepath.Join(models.UploadBaseDir, "worldtv", "channels.json"), nil)
	})
	return worldTVManager
}
