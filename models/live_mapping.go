package models

import (
	"bookstark/services/cctvlive"
	"database/sql"
	"encoding/json"
	"errors"
	"time"
)

const LiveMappingSetting = "yangshipin_channel_ids"

func LiveMappings() (map[string]cctvlive.OfficialIDs, error) {
	var value string
	err := DB.QueryRow("SELECT value FROM md_settings WHERE key=?", LiveMappingSetting).Scan(&value)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var ids map[string]cctvlive.OfficialIDs
	err = json.Unmarshal([]byte(value), &ids)
	return ids, err
}

func LookupLiveIDs(key string) (cctvlive.OfficialIDs, error) {
	mapping, err := LiveMappings()
	if err != nil {
		return cctvlive.OfficialIDs{}, err
	}
	if ids, ok := mapping[key]; ok {
		return ids, nil
	}
	return cctvlive.DefaultIDs(key), nil
}

// JSON merge patch updates only this channel even if two admins save different channels concurrently.
func SaveLiveIDs(key string, ids *cctvlive.OfficialIDs) error {
	patch, err := json.Marshal(map[string]*cctvlive.OfficialIDs{key: ids})
	if err != nil {
		return err
	}
	_, err = DB.Exec(`INSERT INTO md_settings (key,value,description,update_time) VALUES (?,json_patch('{}',?), '',?)
 ON CONFLICT(key) DO UPDATE SET value=json_patch(md_settings.value,?), update_time=excluded.update_time`,
		LiveMappingSetting, string(patch), time.Now(), string(patch))
	return err
}

// Update lines and upstream identifiers together; JSON merge patches leave other channels alone.
func SaveTVChannel(id string, lines []string, key string, ids *cctvlive.OfficialIDs) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	patch := func(setting, entry string, value any) error {
		change, err := json.Marshal(map[string]any{entry: value})
		if err != nil {
			return err
		}
		_, err = tx.Exec(`INSERT INTO md_settings(key,value,description,update_time) VALUES (?,json_patch('{}',?), '',?)
    ON CONFLICT(key) DO UPDATE SET value=json_patch(COALESCE(NULLIF(trim(md_settings.value),''),'{}'),?), update_time=excluded.update_time`, setting, string(change), time.Now(), string(change))
		return err
	}
	if err = patch(cctvlive.LinesSetting, id, lines); err != nil {
		return err
	}
	var combined string
	if err = tx.QueryRow("SELECT value FROM md_settings WHERE key=?", cctvlive.LinesSetting).Scan(&combined); err != nil {
		return err
	}
	if _, err = cctvlive.Catalog(combined); err != nil {
		return err
	}
	if key != "" && ids != nil {
		if *ids == cctvlive.DefaultIDs(key) {
			ids = nil
		}
		if err = patch(LiveMappingSetting, key, ids); err != nil {
			return err
		}
	}
	return tx.Commit()
}
