package models

import (
	"database/sql"
	"errors"
	"fmt"
)

type BackgroundPreference struct {
	Mode      string `json:"mode"`
	Animated  bool   `json:"animated"`
	Fade      int    `json:"fade"`
	ImageHash string `json:"image_hash"`
}

func GetBackgroundPreference(id int64) (BackgroundPreference, error) {
	p := BackgroundPreference{Mode: "dynamic", Animated: true, Fade: 65}
	err := DB.QueryRow(`SELECT mode,animated,fade,image_hash FROM md_member_backgrounds WHERE member_id=?`, id).Scan(&p.Mode, &p.Animated, &p.Fade, &p.ImageHash)
	if errors.Is(err, sql.ErrNoRows) {
		return p, nil
	}
	return p, err
}

func SaveBackgroundPreference(id int64, p BackgroundPreference, image []byte, hash string, remove bool) error {
	if (p.Mode != "solid" && p.Mode != "dynamic" && p.Mode != "image") || p.Fade < 0 || p.Fade > 100 {
		return fmt.Errorf("invalid background settings")
	}
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var oldHash string
	err = tx.QueryRow(`SELECT image_hash FROM md_member_backgrounds WHERE member_id=?`, id).Scan(&oldHash)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if remove {
		oldHash = ""
	}
	if len(image) > 0 {
		oldHash = hash
		remove = false
	}
	if p.Mode == "image" && oldHash == "" {
		return fmt.Errorf("background image required")
	}
	_, err = tx.Exec(`INSERT INTO md_member_backgrounds(member_id,mode,animated,fade,image,image_hash) VALUES(?,?,?,?,?,?)
        ON CONFLICT(member_id) DO UPDATE SET mode=excluded.mode,animated=excluded.animated,fade=excluded.fade,
        image=CASE WHEN ? THEN NULL WHEN ? THEN excluded.image ELSE image END,image_hash=?`, id, p.Mode, p.Animated, p.Fade, image, oldHash, remove, len(image) > 0, oldHash)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func GetBackgroundImage(id int64) ([]byte, string, error) {
	var data []byte
	var hash string
	err := DB.QueryRow(`SELECT image,image_hash FROM md_member_backgrounds WHERE member_id=?`, id).Scan(&data, &hash)
	return data, hash, err
}
