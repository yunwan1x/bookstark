package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestCSRFCookieLifetimeAndErrors(t *testing.T) {
	r := gin.New()
	r.Use(CSRFMiddleware())
	r.GET("/page", func(c *gin.Context) { c.Status(http.StatusOK) })
	r.POST("/api/blogs", func(c *gin.Context) { c.Status(http.StatusNoContent) })
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/page", nil))
	cookies := w.Result().Cookies()
	if len(cookies) != 1 || cookies[0].Name != "csrf_token" || cookies[0].MaxAge != 604800 {
		t.Fatalf("expected csrf_token cookie with MaxAge=604800 (7 days), got %v", cookies)
	}
	for _, tc := range []struct {
		name, cookie, header, message string
		status                        int
	}{
		{"expired cookie", "", cookies[0].Value, "缺少 CSRF token", http.StatusForbidden},
		{"stale page", "new-token", "old-token", "CSRF 验证失败", http.StatusForbidden},
		{"valid submission", "current-token", "current-token", "", http.StatusNoContent},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/api/blogs", nil)
			if tc.cookie != "" {
				req.AddCookie(&http.Cookie{Name: "csrf_token", Value: tc.cookie})
			}
			req.Header.Set("X-CSRF-Token", tc.header)
			res := httptest.NewRecorder()
			r.ServeHTTP(res, req)
			if res.Code != tc.status {
				t.Fatalf("status = %d, want %d", res.Code, tc.status)
			}
			if tc.message == "" {
				return
			}
			var body struct {
				Code      int    `json:"code"`
				Message   string `json:"message"`
				Error     string `json:"error"`
				CSRFError bool   `json:"csrf_error"`
			}
			if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if body.Code != tc.status || body.Message != tc.message || body.Error != tc.message || !body.CSRFError {
				t.Fatalf("unexpected error response: %+v", body)
			}
		})
	}
}
