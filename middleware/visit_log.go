package middleware

import (
	"strings"

	"github.com/gin-gonic/gin"

	"bookstark/models"
)

var visitLogPrefixes = []string{
	"/shares",
	"/bookmarks",
}

func VisitLog() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path

		shouldLog := false
		for _, prefix := range visitLogPrefixes {
			if strings.HasPrefix(path, prefix) {
				shouldLog = true
				break
			}
		}
		if path == "/" {
			shouldLog = true
		}

		if shouldLog {
			ip := c.ClientIP()
			memberID := GetMemberID(c)
			models.AsyncCreateVisitLog(ip, path, memberID)
		}

		c.Next()
	}
}