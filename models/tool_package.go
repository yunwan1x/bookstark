package models

import (
	"bookstark/internal/toolpackage"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
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
