package middleware

import (
	"github.com/gin-gonic/gin"

	"bookstark/i18n"
)

// LangMiddleware reads the lang cookie and stores the validated language in context.
func LangMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		lang := i18n.GetLang(c)
		c.Set("lang", lang)
		c.Next()
	}
}

// GetLang retrieves the current language from gin context (set by LangMiddleware).
func GetLang(c *gin.Context) string {
	if lang, ok := c.Get("lang"); ok {
		if s, ok := lang.(string); ok {
			return s
		}
	}
	return i18n.DefaultLang
}
