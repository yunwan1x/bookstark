package models

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"time"

	"golang.org/x/crypto/bcrypt"
)

var ErrPasswordResetTokenInvalid = errors.New("password reset token is invalid or expired")

func CreatePasswordResetToken(memberID int64, createdIP string, ttl time.Duration) (string, time.Time, error) {
	rawBytes := make([]byte, 32)
	if _, err := rand.Read(rawBytes); err != nil {
		return "", time.Time{}, err
	}
	rawToken := base64.RawURLEncoding.EncodeToString(rawBytes)
	tokenHash := hashPasswordResetToken(rawToken)
	now := time.Now()
	expiresAt := now.Add(ttl)

	tx, err := DB.Begin()
	if err != nil {
		return "", time.Time{}, err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`
		UPDATE md_password_reset_tokens SET used_at = ?
		WHERE member_id = ? AND used_at IS NULL`, now, memberID); err != nil {
		return "", time.Time{}, err
	}
	if _, err := tx.Exec(`
		INSERT INTO md_password_reset_tokens
		(member_id, token_hash, expires_at, used_at, created_at, created_ip)
		VALUES (?, ?, ?, NULL, ?, ?)`, memberID, tokenHash, expiresAt, now, createdIP); err != nil {
		return "", time.Time{}, err
	}
	if _, err := tx.Exec(`
		DELETE FROM md_password_reset_tokens
		WHERE expires_at < ? OR (used_at IS NOT NULL AND used_at < ?)`, now.Add(-24*time.Hour), now.Add(-7*24*time.Hour)); err != nil {
		return "", time.Time{}, err
	}
	if err := tx.Commit(); err != nil {
		return "", time.Time{}, err
	}
	return rawToken, expiresAt, nil
}

func ResetPasswordWithToken(rawToken, newPassword string) error {
	tokenHash := hashPasswordResetToken(rawToken)
	now := time.Now()
	var candidate int
	err := DB.QueryRow(`
		SELECT 1
		FROM md_password_reset_tokens r
		JOIN md_members m ON m.member_id = r.member_id
		WHERE r.token_hash = ? AND r.used_at IS NULL AND r.expires_at > ? AND m.status = 1`, tokenHash, now).
		Scan(&candidate)
	if err == sql.ErrNoRows {
		return ErrPasswordResetTokenInvalid
	}
	if err != nil {
		return err
	}
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	now = time.Now()

	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var resetID, memberID int64
	var expiresAt time.Time
	err = tx.QueryRow(`
		SELECT r.reset_id, r.member_id, r.expires_at
		FROM md_password_reset_tokens r
		JOIN md_members m ON m.member_id = r.member_id
		WHERE r.token_hash = ? AND r.used_at IS NULL AND m.status = 1`, tokenHash).
		Scan(&resetID, &memberID, &expiresAt)
	if err == sql.ErrNoRows || (err == nil && !expiresAt.After(now)) {
		return ErrPasswordResetTokenInvalid
	}
	if err != nil {
		return err
	}

	result, err := tx.Exec(`
		UPDATE md_password_reset_tokens SET used_at = ?
		WHERE reset_id = ? AND used_at IS NULL AND expires_at > ?`, now, resetID, now)
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil || affected != 1 {
		return ErrPasswordResetTokenInvalid
	}
	result, err = tx.Exec("UPDATE md_members SET password = ? WHERE member_id = ?", string(passwordHash), memberID)
	if err != nil {
		return err
	}
	affected, err = result.RowsAffected()
	if err != nil || affected != 1 {
		return ErrPasswordResetTokenInvalid
	}
	if _, err := tx.Exec(`
		INSERT INTO md_member_auth_versions(member_id, auth_version, update_time)
		VALUES (?, 2, ?)
		ON CONFLICT(member_id) DO UPDATE SET
			auth_version = auth_version + 1,
			update_time = excluded.update_time`, memberID, now); err != nil {
		return err
	}
	if _, err := tx.Exec(`
		UPDATE md_password_reset_tokens SET used_at = ?
		WHERE member_id = ? AND used_at IS NULL`, now, memberID); err != nil {
		return err
	}
	return tx.Commit()
}

func hashPasswordResetToken(rawToken string) string {
	sum := sha256.Sum256([]byte(rawToken))
	return hex.EncodeToString(sum[:])
}
