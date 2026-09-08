package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// GenerateCSRFToken 生成随机 CSRF token
func GenerateCSRFToken() string {
	b := make([]byte, 32)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// CSRFMiddleware 双重提交 Cookie 模式的 CSRF 防护中间件
// 对于 API 请求（/api/ 开头），验证 X-CSRF-Token 请求头
// 对于页面表单提交，验证 form 中的 csrf_token 字段或 X-CSRF-Token 请求头
// GET/HEAD/OPTIONS 请求跳过验证，仅生成并设置 token
// 使用 API Token（Authorization: Token xxx）认证的请求跳过 CSRF 验证
func CSRFMiddleware(skipPaths ...string) gin.HandlerFunc {
	skipMap := make(map[string]bool)
	for _, p := range skipPaths {
		skipMap[p] = true
	}

	return func(c *gin.Context) {
		path := c.Request.URL.Path

		// 跳过指定路径的 CSRF 验证（如登录、注册等公共端点）
		if skipMap[path] {
			c.Next()
			return
		}

		// 使用 API Token 认证的请求跳过 CSRF（API Token 不存在 cookie 中，不受 CSRF 攻击）
		auth := c.GetHeader("Authorization")
		if strings.HasPrefix(auth, "Token ") {
			c.Next()
			return
		}

		// GET/HEAD/OPTIONS 安全方法：复用已有 CSRF token 或生成新的
		if c.Request.Method == "GET" || c.Request.Method == "HEAD" || c.Request.Method == "OPTIONS" {
			token, _ := c.Cookie("csrf_token")
			if token == "" {
				token = GenerateCSRFToken()
				c.SetCookie("csrf_token", token, 86400, "/", "", false, false)
			}
			c.Set("CSRFToken", token)
			c.Next()
			return
		}

		// POST/PUT/PATCH/DELETE 等变更方法：验证 CSRF token
		cookieToken, err := c.Cookie("csrf_token")
		if err != nil || cookieToken == "" {
			c.JSON(http.StatusForbidden, gin.H{"error": "缺少 CSRF token"})
			c.Abort()
			return
		}

		// 从请求头或表单获取 token
		var requestToken string
		if strings.HasPrefix(path, "/api/") {
			requestToken = c.GetHeader("X-CSRF-Token")
		} else {
			requestToken = c.PostForm("csrf_token")
			if requestToken == "" {
				requestToken = c.GetHeader("X-CSRF-Token")
			}
		}

		if requestToken == "" || requestToken != cookieToken {
			c.JSON(http.StatusForbidden, gin.H{"error": "CSRF 验证失败"})
			c.Abort()
			return
		}

		c.Set("CSRFToken", cookieToken)
		c.Next()
	}
}

// GetCSRFToken 从 gin.Context 获取 CSRF token
func GetCSRFToken(c *gin.Context) string {
	if token, exists := c.Get("CSRFToken"); exists {
		if s, ok := token.(string); ok {
			return s
		}
	}
	return ""
}