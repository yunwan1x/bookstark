package controllers

import (
	"bookstark/middleware"
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"net/http"
	"net/url"
	"strings"
)

type marketSettings struct {
	Enabled        bool   `json:"enabled"`
	Name           string `json:"name"`
	PublicURL      string `json:"public_url"`
	LoginRequired  bool   `json:"login_required"`
	MembersPublish bool   `json:"members_publish"`
	ReviewRequired bool   `json:"review_required"`
}

func readMarketSettings(c *gin.Context) marketSettings {
	base := models.GetSetting("tool_market_public_url")
	if base == "" {
		base = requestToolOrigin(c)
	}
	return marketSettings{models.GetSettingWithDefault("tool_market_enabled", "1") == "1", models.GetSettingWithDefault("tool_market_name", "BookStark 工具市场"), strings.TrimRight(base, "/") + "/market", models.GetSettingWithDefault("tool_market_login_required", "1") == "1", models.GetSettingWithDefault("tool_market_members_publish", "1") == "1", models.GetSettingWithDefault("tool_market_review_required", "1") == "1"}
}
func ToolMarketSettingsPage(c *gin.Context) {
	c.HTML(200, "tool_market_settings.html", commonData(c, "admin"))
}
func ToolMarketSettings(c *gin.Context) {
	if c.Request.Method == http.MethodGet {
		c.JSON(200, readMarketSettings(c))
		return
	}
	var p marketSettings
	if c.ShouldBindJSON(&p) != nil || strings.TrimSpace(p.Name) == "" || len(p.Name) > 100 {
		c.JSON(400, gin.H{"error": "invalid_settings"})
		return
	}
	base := strings.TrimSuffix(strings.TrimRight(p.PublicURL, "/"), "/market")
	u, err := url.Parse(base)
	if err != nil || u.Host == "" || u.User != nil || (u.Scheme != "https" && u.Scheme != "http") || u.RawQuery != "" || u.Fragment != "" || u.Path != "" {
		c.JSON(400, gin.H{"error": "invalid_market_url"})
		return
	}
	values := map[string]string{"tool_market_name": p.Name, "tool_market_public_url": base}
	for k, v := range map[string]bool{"tool_market_enabled": p.Enabled, "tool_market_login_required": p.LoginRequired, "tool_market_members_publish": p.MembersPublish, "tool_market_review_required": p.ReviewRequired} {
		if v {
			values[k] = "1"
		} else {
			values[k] = "0"
		}
	}
	if err := models.BatchUpdateSettings(values); err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, readMarketSettings(c))
}
func ToolMarketInfo(c *gin.Context) {
	p := readMarketSettings(c)
	if !p.Enabled {
		c.JSON(503, gin.H{"error": "market_disabled"})
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(200, gin.H{"name": p.Name, "url": p.PublicURL, "login_required": p.LoginRequired, "protocol": 1, "authenticated": marketMember(c) > 0})
}
func marketMember(c *gin.Context) int64 {
	auth := c.GetHeader("Authorization")
	if strings.HasPrefix(auth, "Market ") {
		return marketTokenMember(strings.TrimPrefix(auth, "Market "))
	}
	return middleware.GetMemberID(c)
}

func mayInstallTool(c *gin.Context, m models.ToolMetadata) bool {
	if !readMarketSettings(c).Enabled {
		c.JSON(503, gin.H{"error": "market_disabled"})
		return false
	}
	member := marketMember(c)
	if (m.Access == "login" || m.Access == "members" || readMarketSettings(c).LoginRequired) && member <= 0 {
		c.JSON(401, gin.H{"error": "market_login_required"})
		return false
	}
	if m.Access == "members" {
		for _, id := range m.Members {
			if id == member {
				return true
			}
		}
		c.JSON(403, gin.H{"error": "market_forbidden"})
		return false
	}
	return true
}
