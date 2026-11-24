package controllers

import (
	"bookstark/conf"
	"bookstark/middleware"
	"bookstark/models"
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

func marketTokenMember(token string) int64 {
	if len(token) > 200 {
		return 0
	}
	var member int64
	var version int
	_ = models.DB.QueryRow(`SELECT s.member_id,s.auth_version FROM md_tool_market_sessions s JOIN md_members m ON m.member_id=s.member_id WHERE s.token_hash=? AND s.expires>? AND m.status=1`, fmt.Sprintf("%x", sha256.Sum256([]byte(token))), time.Now().Unix()).Scan(&member, &version)
	if ok, err := models.IsMemberAuthVersionCurrent(member, version); err != nil || !ok {
		return 0
	}
	return member
}
func MarketLogin(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	var req struct {
		Account  string `json:"account"`
		Password string `json:"password"`
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 4096)
	if !readMarketSettings(c).Enabled {
		c.JSON(503, gin.H{"error": "market_disabled"})
		return
	}
	if c.ShouldBindJSON(&req) != nil || req.Account == "" || len(req.Password) > 72 {
		c.Status(400)
		return
	}
	if !loginLimiter.check("market:"+c.ClientIP(), 10, 5*time.Minute) {
		c.JSON(429, gin.H{"error": "market_rate_limit"})
		return
	}
	member, err := models.GetMemberByAccount(req.Account)
	if err != nil || member.Status != 1 || !member.VerifyPassword(req.Password) {
		c.JSON(401, gin.H{"error": "market_login_failed"})
		return
	}
	token := rand.Text() + rand.Text()
	_, err = models.DB.Exec("INSERT INTO md_tool_market_sessions(token_hash,member_id,expires,auth_version) VALUES(?,?,?,COALESCE((SELECT auth_version FROM md_member_auth_versions WHERE member_id=?),1))", fmt.Sprintf("%x", sha256.Sum256([]byte(token))), member.MemberID, time.Now().Add(30*24*time.Hour).Unix(), member.MemberID)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	loginLimiter.reset("market:" + c.ClientIP())
	c.JSON(200, gin.H{"token": token, "account": member.Account})
}
func normalizeMarketURL(raw string) (string, error) {
	u, err := url.Parse(strings.TrimRight(strings.TrimSpace(raw), "/"))
	if err != nil || u.Host == "" || u.User != nil || (u.Scheme != "http" && u.Scheme != "https") || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/market") {
		return "", fmt.Errorf("invalid market URL")
	}
	return u.Scheme + "://" + u.Host, nil
}
func ownMarketplace(c *gin.Context, origin string) bool {
	return origin == requestToolOrigin(c) || origin == strings.TrimSuffix(readMarketSettings(c).PublicURL, "/market")
}
func clientMarketToken(member int64, origin string) string {
	var stored string
	_ = models.DB.QueryRow("SELECT token FROM md_tool_market_credentials WHERE member_id=? AND url=?", member, origin+"/market").Scan(&stored)
	if stored == "" {
		return ""
	}
	token, err := models.DecryptContent(conf.App.JWTSecret, stored)
	if err != nil {
		return ""
	}
	return token
}
func requestMarket(ctx context.Context, origin, path, method string, body []byte, token string) ([]byte, int, error) {
	req, err := http.NewRequestWithContext(ctx, method, origin+path, bytes.NewReader(body))
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Market "+token)
	}
	client := marketplaceHTTPClient()
	defer client.CloseIdleConnections()
	client.CheckRedirect = func(r *http.Request, via []*http.Request) error { return http.ErrUseLastResponse }
	response, err := client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 350<<20))
	if err != nil {
		return nil, 0, err
	}
	if len(data) >= 350<<20 {
		return nil, 0, fmt.Errorf("market response too large")
	}
	return data, response.StatusCode, nil
}
func MarketClientSettings(c *gin.Context) {
	member := middleware.GetMemberID(c)
	if c.Request.Method == "PUT" || c.Request.Method == "POST" {
		if !isAdmin(c) {
			c.JSON(403, gin.H{"error": "market_config_forbidden"})
			return
		}
		var p struct {
			URL   string `json:"url"`
			Check bool   `json:"check_updates"`
			Auto  bool   `json:"auto_update"`
		}
		if c.ShouldBindJSON(&p) != nil {
			c.Status(400)
			return
		}
		origin, err := normalizeMarketURL(p.URL)
		if err != nil {
			c.JSON(400, gin.H{"error": "invalid_market_url"})
			return
		}
		data, _ := json.Marshal(gin.H{"protocol": 1, "name": readMarketSettings(c).Name})
		status, err := 200, error(nil)
		if ownMarketplace(c, origin) && !readMarketSettings(c).Enabled {
			c.JSON(503, gin.H{"error": "market_disabled"})
			return
		}
		if !ownMarketplace(c, origin) {
			data, status, err = requestMarket(c.Request.Context(), origin, "/market/index.json", "GET", nil, "")
		}
		if err != nil || status != 200 {
			c.JSON(502, gin.H{"error": "catalog_unavailable"})
			return
		}
		var info struct {
			Protocol int `json:"protocol"`
		}
		if json.Unmarshal(data, &info) != nil || info.Protocol != 1 {
			c.JSON(422, gin.H{"error": "invalid_market_url"})
			return
		}
		if c.Request.Method == "POST" {
			var info any
			json.Unmarshal(data, &info)
			c.JSON(200, gin.H{"connected": true, "url": origin + "/market", "market": info})
			return
		}
		_, err = models.DB.Exec(`INSERT INTO md_tool_market_clients(member_id,url,check_updates,auto_update) VALUES(?,?,?,?) ON CONFLICT(member_id) DO UPDATE SET url=excluded.url,check_updates=excluded.check_updates,auto_update=excluded.auto_update`, member, origin+"/market", p.Check, p.Auto)
		if err != nil {
			toolAPIError(c, err)
			return
		}
	}
	var address, account string
	check, auto := true, false
	err := models.DB.QueryRow("SELECT url,check_updates,auto_update FROM md_tool_market_clients WHERE member_id=?", member).Scan(&address, &check, &auto)
	configured := err == nil && strings.TrimSpace(address) != ""
	if !configured {
		address = models.DefaultToolMarketURL
	}
	accountURL := address
	if server := c.Query("server"); server != "" {
		origin, e := normalizeMarketURL(server)
		if e != nil {
			c.Status(400)
			return
		}
		accountURL = origin + "/market"
	}
	_ = models.DB.QueryRow("SELECT account FROM md_tool_market_credentials WHERE member_id=? AND url=?", member, accountURL).Scan(&account)
	c.Header("Cache-Control", "private, no-store")
	c.JSON(200, gin.H{"url": address, "configured": configured, "account": account, "check_updates": check, "auto_update": auto, "can_configure": isAdmin(c), "workspace_account": middleware.GetAccount(c)})
}
func MarketClientLogin(c *gin.Context) {
	var p struct {
		Server   string `json:"server"`
		Account  string `json:"account"`
		Password string `json:"password"`
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 8192)
	if c.ShouldBindJSON(&p) != nil {
		c.Status(400)
		return
	}
	origin, err := normalizeMarketURL(p.Server)
	if err != nil {
		c.Status(400)
		return
	}
	data, _ := json.Marshal(gin.H{"account": p.Account, "password": p.Password})
	var status int
	if ownMarketplace(c, origin) {
		if !loginLimiter.check("market-client:"+c.ClientIP(), 10, 5*time.Minute) {
			c.Status(429)
			return
		}
		m, e := models.GetMemberByAccount(p.Account)
		if e != nil || m.Status != 1 || !m.VerifyPassword(p.Password) {
			c.JSON(401, gin.H{"error": "market_login_failed"})
			return
		}
		token := rand.Text() + rand.Text()
		_, err = models.DB.Exec("INSERT INTO md_tool_market_sessions(token_hash,member_id,expires,auth_version) VALUES(?,?,?,COALESCE((SELECT auth_version FROM md_member_auth_versions WHERE member_id=?),1))", fmt.Sprintf("%x", sha256.Sum256([]byte(token))), m.MemberID, time.Now().Add(30*24*time.Hour).Unix(), m.MemberID)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		data, _ = json.Marshal(gin.H{"token": token, "account": m.Account})
		status = 200
	} else {
		data, status, err = requestMarket(c.Request.Context(), origin, "/market/login", "POST", data, "")
	}

	if err != nil {
		c.JSON(502, gin.H{"error": "catalog_unavailable"})
		return
	}
	if status != 200 {
		c.JSON(status, gin.H{"error": "market_login_failed"})
		return
	}
	var result struct {
		Token   string `json:"token"`
		Account string `json:"account"`
	}
	if json.Unmarshal(data, &result) != nil || result.Token == "" {
		c.Status(502)
		return
	}
	encrypted, err := models.EncryptContent(conf.App.JWTSecret, result.Token)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	_, err = models.DB.Exec(`INSERT INTO md_tool_market_credentials(member_id,url,account,token) VALUES(?,?,?,?) ON CONFLICT(member_id,url) DO UPDATE SET account=excluded.account,token=excluded.token`, middleware.GetMemberID(c), origin+"/market", result.Account, encrypted)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, gin.H{"account": result.Account})
}
func MarketClientLogout(c *gin.Context) {
	member := middleware.GetMemberID(c)
	var request struct {
		Server string `json:"server"`
	}
	_ = c.ShouldBindJSON(&request)
	if request.Server == "" {
		_ = models.DB.QueryRow("SELECT url FROM md_tool_market_clients WHERE member_id=?", member).Scan(&request.Server)
	}
	origin, err := normalizeMarketURL(request.Server)
	if err != nil {
		c.Status(400)
		return
	}
	token := clientMarketToken(member, origin)
	if ownMarketplace(c, origin) {
		_, _ = models.DB.Exec("DELETE FROM md_tool_market_sessions WHERE token_hash=?", fmt.Sprintf("%x", sha256.Sum256([]byte(token))))
	} else if token != "" {
		_, _, _ = requestMarket(c.Request.Context(), origin, "/market/login", "DELETE", nil, token)
	}
	_, err = models.DB.Exec("DELETE FROM md_tool_market_credentials WHERE member_id=? AND url=?", member, origin+"/market")
	if err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, gin.H{"ok": true})
}
func MarketLogout(c *gin.Context) {
	token := strings.TrimPrefix(c.GetHeader("Authorization"), "Market ")
	if token != "" {
		_, err := models.DB.Exec("DELETE FROM md_tool_market_sessions WHERE token_hash=?", fmt.Sprintf("%x", sha256.Sum256([]byte(token))))
		if err != nil {
			toolAPIError(c, err)
			return
		}
	}
	c.JSON(200, gin.H{"ok": true})
}
