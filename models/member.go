package models

import (
	"database/sql"
	"log"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
)

type Member struct {
	MemberID      int64      `json:"member_id"`
	Account       string     `json:"account"`
	Password      string     `json:"-"`
	Email         string     `json:"email"`
	Role          int        `json:"role"`
	Status        int        `json:"status"`
	DefaultHome   string     `json:"default_home"`
	CreateTime    time.Time  `json:"create_time"`
	CreateAt      int64      `json:"create_at"`
	LastLoginTime *time.Time `json:"last_login_time"`
}

const DefaultHomeNotes = "notes"

var defaultHomeRoutes = map[string]string{
	"home":      "/home",
	"notes":     "/notes",
	"tasks":     "/notes?tab=tasks",
	"articles":  "/notes?tab=articles",
	"books":     "/books",
	"bookmarks": "/bookmarks",
	"nav":       "/",
	"search":    "/search",
}

func NormalizeDefaultHome(home string) string {
	if _, ok := defaultHomeRoutes[home]; ok {
		return home
	}
	return "home"
}

func IsValidDefaultHome(home string) bool {
	_, ok := defaultHomeRoutes[home]
	return ok
}

func DefaultHomeRoute(home string) string {
	return defaultHomeRoutes[NormalizeDefaultHome(home)]
}

func (m *Member) Insert() error {
	hash, err := bcrypt.GenerateFromPassword([]byte(m.Password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	m.DefaultHome = NormalizeDefaultHome(m.DefaultHome)
	result, err := DB.Exec(
		"INSERT INTO md_members (account, password, email, role, status, default_home, create_time, create_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
		m.Account, string(hash), m.Email, m.Role, m.Status, m.DefaultHome, m.CreateTime, m.CreateAt,
	)
	if err != nil {
		return err
	}
	m.MemberID, _ = result.LastInsertId()
	if m.MemberID == 0 {
		log.Printf("Member.Insert: LastInsertId returned 0")
	}
	return nil
}

func (m *Member) VerifyPassword(plain string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(m.Password), []byte(plain))
	return err == nil
}

func GetMemberByAccount(account string) (*Member, error) {
	m := &Member{}
	err := DB.QueryRow(
		"SELECT member_id, account, password, email, role, status, default_home, create_time, create_at, last_login_time FROM md_members WHERE account = ?",
		account,
	).Scan(&m.MemberID, &m.Account, &m.Password, &m.Email, &m.Role, &m.Status, &m.DefaultHome, &m.CreateTime, &m.CreateAt, &m.LastLoginTime)
	if err != nil {
		return nil, err
	}
	m.DefaultHome = NormalizeDefaultHome(m.DefaultHome)
	return m, nil
}

func GetActiveMemberByAccountOrEmail(identity string) (*Member, error) {
	identity = strings.TrimSpace(identity)
	m := &Member{}
	err := DB.QueryRow(`
		SELECT member_id, account, password, email, role, status, default_home,
		       create_time, create_at, last_login_time
		FROM md_members
		WHERE status = 1 AND (account = ? OR lower(email) = lower(?))
		LIMIT 1`, identity, identity).Scan(
		&m.MemberID, &m.Account, &m.Password, &m.Email, &m.Role, &m.Status,
		&m.DefaultHome, &m.CreateTime, &m.CreateAt, &m.LastLoginTime)
	if err != nil {
		return nil, err
	}
	m.DefaultHome = NormalizeDefaultHome(m.DefaultHome)
	return m, nil
}

func GetMemberByID(id int64) (*Member, error) {
	m := &Member{}
	err := DB.QueryRow(
		"SELECT member_id, account, password, email, role, status, default_home, create_time, create_at, last_login_time FROM md_members WHERE member_id = ?",
		id,
	).Scan(&m.MemberID, &m.Account, &m.Password, &m.Email, &m.Role, &m.Status, &m.DefaultHome, &m.CreateTime, &m.CreateAt, &m.LastLoginTime)
	if err != nil {
		return nil, err
	}
	m.DefaultHome = NormalizeDefaultHome(m.DefaultHome)
	return m, nil
}

func UpdateMemberLoginTime(id int64) error {
	_, err := DB.Exec("UPDATE md_members SET last_login_time = ? WHERE member_id = ?", time.Now(), id)
	return err
}

func UpdateMemberProfile(id int64, email, defaultHome string) error {
	_, err := DB.Exec("UPDATE md_members SET email = ?, default_home = ? WHERE member_id = ?", email, NormalizeDefaultHome(defaultHome), id)
	return err
}

func UpdateMemberPassword(id int64, newPassword string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	result, err := tx.Exec("UPDATE md_members SET password = ? WHERE member_id = ?", string(hash), id)
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected != 1 {
		return sql.ErrNoRows
	}
	if _, err := tx.Exec(`
		INSERT INTO md_member_auth_versions(member_id, auth_version, update_time)
		VALUES (?, 2, ?)
		ON CONFLICT(member_id) DO UPDATE SET
			auth_version = auth_version + 1,
			update_time = excluded.update_time`, id, time.Now()); err != nil {
		return err
	}
	return tx.Commit()
}

func GetMemberAuthVersion(memberID int64) (int, error) {
	var version int
	err := DB.QueryRow("SELECT auth_version FROM md_member_auth_versions WHERE member_id = ?", memberID).Scan(&version)
	if err == sql.ErrNoRows {
		return 1, nil
	}
	if err != nil {
		return 0, err
	}
	if version < 1 {
		return 1, nil
	}
	return version, nil
}

func IsMemberAuthVersionCurrent(memberID int64, tokenVersion int) (bool, error) {
	if tokenVersion < 1 {
		tokenVersion = 1
	}
	var current, status int
	err := DB.QueryRow(`
		SELECT COALESCE(v.auth_version, 1), m.status
		FROM md_members m
		LEFT JOIN md_member_auth_versions v ON v.member_id = m.member_id
		WHERE m.member_id = ?`, memberID).Scan(&current, &status)
	if err != nil {
		return false, err
	}
	return status == 1 && current == tokenVersion, nil
}

func ListAllMembers(page, pageSize int) ([]Member, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	var total int64
	DB.QueryRow("SELECT COUNT(*) FROM md_members").Scan(&total)

	offset := (page - 1) * pageSize
	rows, err := DB.Query(
		"SELECT member_id, account, role, status, create_time, create_at, last_login_time FROM md_members ORDER BY member_id LIMIT ? OFFSET ?",
		pageSize, offset,
	)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var members []Member
	for rows.Next() {
		var m Member
		// 注意：不返回 email 字段
		if err := rows.Scan(&m.MemberID, &m.Account, &m.Role, &m.Status, &m.CreateTime, &m.CreateAt, &m.LastLoginTime); err != nil {
			return nil, 0, err
		}
		members = append(members, m)
	}
	return members, total, nil
}

func UpdateMemberStatus(id int64, status int) error {
	_, err := DB.Exec("UPDATE md_members SET status = ? WHERE member_id = ?", status, id)
	return err
}

func UpdateMemberRole(id int64, role int) error {
	_, err := DB.Exec("UPDATE md_members SET role = ? WHERE member_id = ?", role, id)
	return err
}
