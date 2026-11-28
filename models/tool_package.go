package models

import (
	"bookstark/internal/toolpackage"
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"time"
)

type ToolPackage struct {
	Token        string             `json:"token"`
	MemberID     int64              `json:"-"`
	Name         string             `json:"name"`
	Size         int64              `json:"size"`
	ExpandedSize int64              `json:"expanded_size"`
	Entry        string             `json:"entry"`
	Entries      []string           `json:"entries"`
	Files        []toolpackage.File `json:"files"`
	Config       json.RawMessage    `json:"config,omitempty"`
	Created      int64              `json:"created"`
}

func toolPackageRoot(token string) string { return "/BookStark/tool-packages/" + token }
func SaveToolPackage(member int64, name string, size int64, a toolpackage.Archive) (ToolPackage, error) {
	p := ToolPackage{MemberID: member, Name: name, Size: size, ExpandedSize: a.Size, Entry: a.Entry, Entries: a.Entries, Config: a.Config, Created: time.Now().UnixMilli()}
	token, err := toolNonce()
	if err != nil {
		return p, err
	}
	p.Token = token
	committed := false
	defer func() {
		if !committed && WebDAVDB != nil {
			_ = DeleteDAVNode(member, toolPackageRoot(token), true)
		}
	}()
	for _, f := range a.Files {
		if err = putToolResourceAt(member, toolPackageRoot(token)+"/"+f.Name, f.MIME, bytes.NewReader(f.Data)); err != nil {
			return p, err
		}
		p.Files = append(p.Files, toolpackage.File{Name: f.Name, MIME: f.MIME, Size: int64(len(f.Data)), Hash: fmt.Sprintf("%x", sha256.Sum256(f.Data))})
	}
	raw, err := json.Marshal(p)
	if err != nil {
		return p, err
	}
	if _, err = DB.Exec(`INSERT INTO md_tool_packages(token,member_id,metadata,created) VALUES(?,?,?,?)`, token, member, string(raw), p.Created); err != nil {
		return p, err
	}
	committed = true
	return p, nil
}
func GetToolPackage(token string) (ToolPackage, error) {
	var p ToolPackage
	var raw string
	var member int64
	err := DB.QueryRow(`SELECT member_id,metadata FROM md_tool_packages WHERE token=?`, token).Scan(&member, &raw)
	if err == nil {
		err = json.Unmarshal([]byte(raw), &p)
		p.MemberID = member
	}
	return p, err
}

// Replaced or interrupted uploads are collectible after a day. Published
// history and the current resumable upload are always retained.
func CleanupToolPackages(member int64) error {
	rows, err := DB.Query(`SELECT token FROM md_tool_packages p WHERE member_id=? AND created<? AND NOT EXISTS(SELECT 1 FROM md_tools s WHERE s.package_token=p.token) AND NOT EXISTS(SELECT 1 FROM md_tool_versions v WHERE json_extract(v.metadata,'$.package')=p.token) LIMIT 32`, member, time.Now().Add(-24*time.Hour).UnixMilli())
	if err != nil {
		return err
	}
	var tokens []string
	for rows.Next() {
		var token string
		if err = rows.Scan(&token); err != nil {
			rows.Close()
			return err
		}
		tokens = append(tokens, token)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, token := range tokens {
		if err = DiscardToolPackage(member, token); err != nil {
			return err
		}
	}
	return nil
}
func DiscardToolPackage(member int64, token string) error {
	p, err := GetToolPackage(token)
	if err != nil {
		return err
	}
	if p.MemberID != member {
		return ErrToolPermission
	}
	result, err := DB.Exec(`DELETE FROM md_tool_packages WHERE token=? AND member_id=? AND NOT EXISTS(SELECT 1 FROM md_tools WHERE package_token=?) AND NOT EXISTS(SELECT 1 FROM md_tool_versions WHERE json_extract(metadata,'$.package')=?)`, token, member, token, token)
	if err != nil {
		return err
	}
	n, err := result.RowsAffected()
	if err != nil || n == 0 {
		return err
	}
	if err = DeleteDAVNode(member, toolPackageRoot(token), true); err != nil && err != ErrDAVNotFound {
		raw, _ := json.Marshal(p)
		_, restore := DB.Exec(`INSERT OR IGNORE INTO md_tool_packages(token,member_id,metadata,created) VALUES(?,?,?,?)`, token, member, string(raw), p.Created)
		if restore != nil {
			return restore
		}
		return err
	}
	return nil
}

// PruneSupersededToolPackages removes older published package versions and their
// staged package files when a newer package version is published for the same tool,
// keeping only the active published package (and any in-flight pending versions).
func PruneSupersededToolPackages(toolID int64, keepRevision, keepPackage string) error {
	if toolID <= 0 || keepRevision == "" || keepPackage == "" {
		return nil
	}
	rows, err := DB.Query(`
		SELECT v.revision, json_extract(v.metadata,'$.package'), COALESCE(p.member_id, 0)
		FROM md_tool_versions v
		LEFT JOIN md_tool_packages p ON p.token = json_extract(v.metadata,'$.package')
		WHERE v.tool_id=? AND v.revision!=? AND v.status='published'
		  AND COALESCE(json_extract(v.metadata,'$.package'), '') != ''
		  AND json_extract(v.metadata,'$.package') != ?`,
		toolID, keepRevision, keepPackage)
	if err != nil {
		return err
	}
	type stale struct {
		revision string
		token    string
		memberID int64
	}
	var items []stale
	for rows.Next() {
		var s stale
		if err = rows.Scan(&s.revision, &s.token, &s.memberID); err != nil {
			rows.Close()
			return err
		}
		items = append(items, s)
	}
	err = rows.Err()
	rows.Close()
	if err != nil || len(items) == 0 {
		return err
	}
	seen := map[string]int64{}
	for _, item := range items {
		if _, err = DB.Exec(`
			DELETE FROM md_tool_versions
			WHERE tool_id=? AND revision=? AND status='published'
			  AND NOT EXISTS(SELECT 1 FROM md_tool_releases WHERE tool_id=? AND revision=?)`,
			toolID, item.revision, toolID, item.revision); err != nil {
			return err
		}
		if item.token != "" && item.memberID > 0 {
			seen[item.token] = item.memberID
		}
	}
	for token, memberID := range seen {
		if err = DiscardToolPackage(memberID, token); err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
	}
	return nil
}
func ReadToolPackageFile(p ToolPackage, name string) ([]byte, string, error) {
	for _, f := range p.Files {
		if f.Name == name {
			_, _, r, err := ReadDAVFileContext(context.Background(), p.MemberID, toolPackageRoot(p.Token)+"/"+name)
			if err != nil {
				return nil, "", err
			}
			defer r.Close()
			b, err := io.ReadAll(io.LimitReader(r, toolpackage.MaxFile+1))
			if err != nil {
				return nil, "", err
			}
			if int64(len(b)) != f.Size || fmt.Sprintf("%x", sha256.Sum256(b)) != f.Hash {
				return nil, "", fmt.Errorf("package_integrity_failed")
			}
			return b, f.MIME, nil
		}
	}
	return nil, "", ErrDAVNotFound
}
