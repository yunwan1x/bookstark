package middleware

import (
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/conf"
	"bookstark/models"
)

func TestLoginSessionDaysControlsJWTAndCookie(t *testing.T) {
	conf.LoadDefaults()
	if models.DB != nil {
		_ = models.DB.Close()
	}
	if err := models.InitDB(filepath.Join(t.TempDir(), "login-session.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = models.DB.Close()
		models.DB = nil
	})

	if got := models.GetLoginSessionDuration(); got != 30*24*time.Hour {
		t.Fatalf("default login session duration = %s, want 30 days", got)
	}
	if err := models.BatchUpdateSettings(map[string]string{"login_session_days": "45"}); err != nil {
		t.Fatal(err)
	}

	member, err := models.GetMemberByID(1)
	if err != nil {
		t.Fatal(err)
	}
	token, err := GenerateToken(member.MemberID, member.Account, member.Role)
	if err != nil {
		t.Fatal(err)
	}
	claims, err := ParseToken(token)
	if err != nil {
		t.Fatal(err)
	}
	if got := claims.ExpiresAt.Time.Sub(claims.IssuedAt.Time); got != 45*24*time.Hour {
		t.Fatalf("JWT lifetime = %s, want 45 days", got)
	}

	recorder := httptest.NewRecorder()
	context, _ := gin.CreateTestContext(recorder)
	SetTokenCookie(context, token)
	cookies := recorder.Result().Cookies()
	if len(cookies) != 1 {
		t.Fatalf("cookie count = %d, want 1", len(cookies))
	}
	if got, want := cookies[0].MaxAge, int((45 * 24 * time.Hour).Seconds()); got != want {
		t.Fatalf("cookie MaxAge = %d, want %d", got, want)
	}
}

func TestLoginSessionDurationFallsBackForInvalidSetting(t *testing.T) {
	conf.LoadDefaults()
	if models.DB != nil {
		_ = models.DB.Close()
	}
	if err := models.InitDB(filepath.Join(t.TempDir(), "invalid-login-session.db")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = models.DB.Close()
		models.DB = nil
	})

	for _, value := range []string{"0", "366", "invalid"} {
		if err := models.BatchUpdateSettings(map[string]string{"login_session_days": value}); err != nil {
			t.Fatal(err)
		}
		if got := models.GetLoginSessionDuration(); got != 30*24*time.Hour {
			t.Fatalf("login session duration for %q = %s, want 30 days", value, got)
		}
	}
}
