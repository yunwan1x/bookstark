package models

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"log"
	"sync"
	"time"
)

type ApiToken struct {
	TokenID    int64     `json:"token_id"`
	MemberID   int64     `json:"member_id"`
	Token      string    `json:"-"`
	MaskedToken string   `json:"masked_token"`
	Name       string    `json:"name"`
	CreateTime time.Time `json:"create_time"`
}

func generateTokenString() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func CreateApiToken(memberID int64, name string) (*ApiToken, error) {
	tokenStr, err := generateTokenString()
	if err != nil {
		return nil, fmt.Errorf("generate token: %w", err)
	}
	if name == "" {
		name = "default"
	}
	now := time.Now()
	result, err := DB.Exec(
		"INSERT INTO md_api_tokens (member_id, token, name, create_time) VALUES (?, ?, ?, ?)",
		memberID, tokenStr, name, now,
	)
	if err != nil {
		return nil, fmt.Errorf("insert api token: %w", err)
	}
	id, _ := result.LastInsertId()
	if id == 0 {
		log.Printf("CreateApiToken: LastInsertId returned 0")
	}
	return &ApiToken{
		TokenID:     id,
		MemberID:    memberID,
		Token:       tokenStr,
		MaskedToken: maskToken(tokenStr),
		Name:        name,
		CreateTime:  now,
	}, nil
}

func GetApiToken(token string) (*ApiToken, error) {
	t := &ApiToken{}
	err := DB.QueryRow(
		"SELECT token_id, member_id, token, name, create_time FROM md_api_tokens WHERE token = ?",
		token,
	).Scan(&t.TokenID, &t.MemberID, &t.Token, &t.Name, &t.CreateTime)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return t, nil
}

func ListApiTokensByMember(memberID int64) ([]ApiToken, error) {
	rows, err := DB.Query(
		"SELECT token_id, member_id, token, name, create_time FROM md_api_tokens WHERE member_id = ? ORDER BY token_id LIMIT 100",
		memberID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []ApiToken
	for rows.Next() {
		var t ApiToken
		if err := rows.Scan(&t.TokenID, &t.MemberID, &t.Token, &t.Name, &t.CreateTime); err != nil {
			return nil, err
		}
		t.MaskedToken = maskToken(t.Token)
		tokens = append(tokens, t)
	}
	return tokens, nil
}

// GetApiTokenByID 根据 tokenID 和 memberID 查询 token 字符串，用于删除时清除缓存
func GetApiTokenByID(tokenID int64, memberID int64) (string, error) {
	var token string
	err := DB.QueryRow(
		"SELECT token FROM md_api_tokens WHERE token_id = ? AND member_id = ?",
		tokenID, memberID,
	).Scan(&token)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return token, nil
}

func DeleteApiToken(tokenID int64, memberID int64) error {
	_, err := DB.Exec("DELETE FROM md_api_tokens WHERE token_id = ? AND member_id = ?", tokenID, memberID)
	return err
}

// --- API Token 内存缓存 ---

var (
	apiTokenCache     = make(map[string]*apiTokenCacheEntry)
	apiTokenCacheLock sync.RWMutex
)

type apiTokenCacheEntry struct {
	token    *ApiToken
	member   *Member
	expireAt time.Time
}

const apiTokenCacheTTL = 60 * time.Second

// GetApiTokenCached 带 60 秒内存缓存的 Token 查询，同时返回关联的 Member，
// 避免每次 API 请求都查两次数据库。
func GetApiTokenCached(tokenStr string) (*ApiToken, *Member, error) {
	apiTokenCacheLock.RLock()
	if entry, ok := apiTokenCache[tokenStr]; ok {
		if time.Now().Before(entry.expireAt) {
			apiTokenCacheLock.RUnlock()
			return entry.token, entry.member, nil
		}
	}
	apiTokenCacheLock.RUnlock()

	// 缓存未命中，查询数据库
	apiToken, err := GetApiToken(tokenStr)
	if err != nil {
		return nil, nil, err
	}
	if apiToken == nil {
		return nil, nil, nil
	}

	member, err := GetMemberByID(apiToken.MemberID)
	if err != nil {
		return nil, nil, err
	}
	if member == nil {
		return nil, nil, nil
	}

	apiTokenCacheLock.Lock()
	apiTokenCache[tokenStr] = &apiTokenCacheEntry{
		token:    apiToken,
		member:   member,
		expireAt: time.Now().Add(apiTokenCacheTTL),
	}
	apiTokenCacheLock.Unlock()

	return apiToken, member, nil
}

// InvalidateApiTokenCache 使指定 token 的缓存失效（删除/更新 token 时调用）
func InvalidateApiTokenCache(tokenStr string) {
	apiTokenCacheLock.Lock()
	delete(apiTokenCache, tokenStr)
	apiTokenCacheLock.Unlock()
}

// maskToken returns a masked version of the token for display.
// If len > 8: first4 + **** + last4; otherwise: first2 + ****
func maskToken(token string) string {
	if len(token) > 8 {
		return token[:4] + "****" + token[len(token)-4:]
	}
	if len(token) >= 2 {
		return token[:2] + "****"
	}
	return "****"
}