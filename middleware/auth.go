package middleware

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"

	"bookstark/conf"
	"bookstark/models"
)

// 角色常量
const (
	RoleAdmin  = 0
	RoleMember = 1
)

type Claims struct {
	MemberID    int64  `json:"member_id"`
	Account     string `json:"account"`
	Role        int    `json:"role"`
	AuthVersion int    `json:"auth_version,omitempty"`
	jwt.RegisteredClaims
}

func GenerateToken(memberID int64, account string, role int) (string, error) {
	expire := models.GetLoginSessionDuration()
	authVersion, err := models.GetMemberAuthVersion(memberID)
	if err != nil {
		return "", err
	}
	claims := Claims{
		MemberID:    memberID,
		Account:     account,
		Role:        role,
		AuthVersion: authVersion,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(expire)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(conf.App.JWTSecret))
}

func AuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenStr, err := c.Cookie("token")
		if err != nil || tokenStr == "" {
			auth := c.GetHeader("Authorization")
			if strings.HasPrefix(auth, "Bearer ") {
				tokenStr = strings.TrimPrefix(auth, "Bearer ")
			} else if strings.HasPrefix(auth, "Token ") {
				tokenStr = strings.TrimPrefix(auth, "Token ")
			}
		}

		if tokenStr == "" {
			if strings.HasPrefix(c.Request.URL.Path, "/api/") {
				c.JSON(http.StatusUnauthorized, gin.H{"code": http.StatusUnauthorized, "message": "未登录", "error": "未登录"})
				c.Abort()
				return
			}
			c.Redirect(http.StatusFound, "/login")
			c.Abort()
			return
		}

		// Try JWT first, then fall back to API Token
		claims, err := ParseToken(tokenStr)
		if err != nil {
			// Not a valid JWT, try as API Token (使用缓存避免每次请求 2 次 DB 查询)
			apiToken, member, err2 := models.GetApiTokenCached(tokenStr)
			if err2 != nil || apiToken == nil || member == nil {
				if strings.HasPrefix(c.Request.URL.Path, "/api/") {
					c.JSON(http.StatusUnauthorized, gin.H{"code": http.StatusUnauthorized, "message": "登录已过期", "error": "登录已过期"})
					c.Abort()
					return
				}
				c.Redirect(http.StatusFound, "/login")
				c.Abort()
				return
			}
			c.Set("memberID", member.MemberID)
			c.Set("account", member.Account)
			c.Set("role", member.Role)
			c.Next()
			return
		}
		current, versionErr := models.IsMemberAuthVersionCurrent(claims.MemberID, claims.AuthVersion)
		if versionErr != nil || !current {
			if strings.HasPrefix(c.Request.URL.Path, "/api/") {
				c.JSON(http.StatusUnauthorized, gin.H{"code": http.StatusUnauthorized, "message": "登录已过期", "error": "登录已过期"})
				c.Abort()
				return
			}
			c.Redirect(http.StatusFound, "/login")
			c.Abort()
			return
		}

		c.Set("claims", claims)
		c.Set("memberID", claims.MemberID)
		c.Set("account", claims.Account)
		c.Set("role", claims.Role)
		c.Next()
	}
}

func AdminRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, _ := c.Get("role")
		if r, ok := role.(int); !ok || r != RoleAdmin {
			if strings.HasPrefix(c.Request.URL.Path, "/api/") {
				c.JSON(http.StatusForbidden, gin.H{"code": http.StatusForbidden, "message": "需要管理员权限", "error": "需要管理员权限"})
				c.Abort()
				return
			}
			c.Redirect(http.StatusFound, "/")
			c.Abort()
			return
		}
		c.Next()
	}
}

func ParseToken(tokenStr string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(conf.App.JWTSecret), nil
	})
	if err != nil {
		return nil, err
	}
	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}
	return nil, jwt.ErrTokenInvalidClaims
}

func SetTokenCookie(c *gin.Context, token string) {
	expire := models.GetLoginSessionDuration()
	maxAge := int(expire.Seconds())
	c.SetCookie("token", token, maxAge, "/", "", false, true)
}

// OptionalAuth 尝试从 cookie/token 解析用户信息，不强制登录
// 用于公开页面但需要区分用户的场景（如书签页）
func OptionalAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 如果已经有 memberID（被其他中间件设置），跳过
		if _, exists := c.Get("memberID"); exists {
			c.Next()
			return
		}

		tokenStr, err := c.Cookie("token")
		if err != nil || tokenStr == "" {
			auth := c.GetHeader("Authorization")
			if strings.HasPrefix(auth, "Bearer ") {
				tokenStr = strings.TrimPrefix(auth, "Bearer ")
			} else if strings.HasPrefix(auth, "Token ") {
				tokenStr = strings.TrimPrefix(auth, "Token ")
			}
		}

		if tokenStr == "" {
			c.Next()
			return
		}

		// Try JWT first, then fall back to API Token
		claims, err := ParseToken(tokenStr)
		if err == nil {
			current, versionErr := models.IsMemberAuthVersionCurrent(claims.MemberID, claims.AuthVersion)
			if versionErr == nil && current {
				c.Set("claims", claims)
				c.Set("memberID", claims.MemberID)
				c.Set("account", claims.Account)
				c.Set("role", claims.Role)
			}
			c.Next()
			return
		}

		// Not a valid JWT, try as API Token (使用缓存避免每次请求 2 次 DB 查询)
		apiToken, member, err2 := models.GetApiTokenCached(tokenStr)
		if err2 == nil && apiToken != nil && member != nil {
			c.Set("memberID", member.MemberID)
			c.Set("account", member.Account)
			c.Set("role", member.Role)
		}
		c.Next()
	}
}

func GetMemberID(c *gin.Context) int64 {
	id, _ := c.Get("memberID")
	if v, ok := id.(int64); ok {
		return v
	}
	return 0
}

func GetAccount(c *gin.Context) string {
	acc, _ := c.Get("account")
	if v, ok := acc.(string); ok {
		return v
	}
	return ""
}

func ParseID(c *gin.Context, key string) (int64, bool) {
	s := c.Param(key)
	s = strings.TrimSuffix(s, "/")
	id, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, false
	}
	return id, true
}
