package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"

	"bookstark/conf"
	"bookstark/models"
)

func TestPasswordChangeInvalidatesExistingJWT(t *testing.T) {
	conf.LoadDefaults()
	if models.DB != nil {
		_ = models.DB.Close()
	}
	if err := models.InitDB(filepath.Join(t.TempDir(), "auth-version.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = models.DB.Close()
		models.DB = nil
	})
	member, err := models.GetMemberByID(1)
	if err != nil {
		t.Fatal(err)
	}
	token, err := GenerateToken(member.MemberID, member.Account, member.Role)
	if err != nil {
		t.Fatal(err)
	}

	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/api/private", AuthRequired(), func(c *gin.Context) { c.Status(http.StatusNoContent) })
	request := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodGet, "/api/private", nil)
		req.AddCookie(&http.Cookie{Name: "token", Value: token})
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)
		return w
	}
	if w := request(); w.Code != http.StatusNoContent {
		t.Fatalf("fresh JWT status = %d, body=%s", w.Code, w.Body.String())
	}
	if err := models.UpdateMemberPassword(member.MemberID, "changed-password"); err != nil {
		t.Fatal(err)
	}
	if w := request(); w.Code != http.StatusUnauthorized {
		t.Fatalf("stale JWT status = %d, body=%s", w.Code, w.Body.String())
	}
	assertAuthError(t, request(), http.StatusUnauthorized, "登录已过期")
	token = "not-a-valid-token"
	assertAuthError(t, request(), http.StatusUnauthorized, "登录已过期")
	token = ""
	assertAuthError(t, request(), http.StatusUnauthorized, "未登录")
}

func assertAuthError(t *testing.T, w *httptest.ResponseRecorder, status int, message string) {
	t.Helper()
	var body struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
		Error   string `json:"error"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if w.Code != status || body.Code != status || body.Message != message || body.Error != message {
		t.Fatalf("unexpected auth response: HTTP %d %s", w.Code, w.Body.String())
	}
}

func TestAdminErrorIncludesMessage(t *testing.T) {
	router := gin.New()
	router.GET("/api/admin", AdminRequired(), func(c *gin.Context) { c.Status(http.StatusNoContent) })
	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/admin", nil))
	assertAuthError(t, w, http.StatusForbidden, "需要管理员权限")
}
