package controllers_test

import (
	"bookstark/conf"
	"bookstark/models"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestHomeSummaryIsolationOrderAndLinks(t *testing.T) {
	router, token := initAssetControllerTest(t)
	admin, _ := models.GetMemberByAccount(conf.App.AdminAccount)
	other := &models.Member{Account: "home-other", Password: "test-only", Role: 1}
	if err := other.Insert(); err != nil {
		t.Fatal(err)
	}
	otherToken, err := models.CreateApiToken(other.MemberID, "home-test")
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 12; i++ {
		b := &models.Blog{BlogTitle: fmt.Sprintf("note-%02d", i), BlogIdentify: fmt.Sprintf("home-note-%d", i), BlogType: "note", MemberID: admin.MemberID, BlogContent: "NEVER_RETURN_CONTENT"}
		if err := b.Insert(); err != nil {
			t.Fatal(err)
		}
		created := time.Date(2026, 1, i+1, 12, 0, 0, 0, time.UTC)
		modified := time.Date(2026, 2, 12-i, 12, 0, 0, 0, time.UTC)
		if _, err := models.DB.Exec("UPDATE md_blogs SET create_time=?,modify_time=? WHERE blog_id=?", created, modified, b.BlogID); err != nil {
			t.Fatal(err)
		}
	}
	private := &models.Blog{BlogTitle: "OTHER_PRIVATE", BlogIdentify: "other-private", BlogType: "note", MemberID: other.MemberID}
	if err := private.Insert(); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct{ order, title string }{{"updated", "note-00"}, {"created", "note-11"}} {
		w := adminAssetRequest(router, token, "GET", "/api/home?start=2026-01-01&end=2026-02-28&order="+test.order, nil)
		if w.Code != 200 {
			t.Fatalf("summary: %d %s", w.Code, w.Body.String())
		}
		if !strings.Contains(w.Header().Get("Cache-Control"), "no-store") {
			t.Fatal("missing cache policy")
		}
		if strings.Contains(w.Body.String(), "OTHER_PRIVATE") || strings.Contains(w.Body.String(), "NEVER_RETURN_CONTENT") {
			t.Fatal("private content leaked")
		}
		var data struct {
			Sections []models.HomeSection `json:"sections"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &data); err != nil {
			t.Fatal(err)
		}
		if len(data.Sections) != 9 {
			t.Fatalf("admin sections %d", len(data.Sections))
		}
		notes := data.Sections[0]
		if notes.Total != 12 || len(notes.Items) != 10 || notes.Items[0].Title != test.title {
			t.Fatalf("bad pagination/sort: %+v", notes)
		}
		if !strings.HasPrefix(notes.Items[0].URL, "/notes?tab=notes&id=") || notes.Items[0].Date == "" {
			t.Fatalf("invalid row %+v", notes.Items[0])
		}
	}
	w := adminAssetRequest(router, otherToken.Token, "GET", "/api/home", nil)
	if w.Code != 200 || strings.Contains(w.Body.String(), `"key":"assets"`) || strings.Contains(w.Body.String(), "note-00") {
		t.Fatalf("nonadmin isolation: %d %s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, "GET", "/api/home?order=unsafe", nil)
	if w.Code != 400 {
		t.Fatal("invalid order accepted")
	}
	for path, want := range map[string]int{"/home": 302, "/api/home": 401} {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
		if w.Code != want {
			t.Fatalf("anonymous %s = %d", path, w.Code)
		}
	}
}

func TestHomeAssetsIncludeSSHAndWebDAV(t *testing.T) {
	router, token := initAssetControllerTest(t)
	for i := 1; i <= 6; i++ {
		created := fmt.Sprintf("2026-01-%02d", i)
		modified := fmt.Sprintf("2026-02-%02d", 7-i)
		if _, err := models.DB.Exec("INSERT INTO md_asset_ssh_hosts(name,host,credential_cipher,create_time,modify_time) VALUES(?,?,?,?,?)", fmt.Sprintf("SSH-%d", i), "PRIVATE_HOST", "PRIVATE_KEY", created, modified); err != nil {
			t.Fatal(err)
		}
		if _, err := models.DB.Exec("INSERT INTO md_asset_webdav_servers(name,url,create_time,modify_time) VALUES(?,?,?,?)", fmt.Sprintf("DAV-%d", i), "https://PRIVATE_DAV", created, modified); err != nil {
			t.Fatal(err)
		}
	}
	for _, order := range []string{"created", "updated"} {
		w := adminAssetRequest(router, token, "GET", "/api/home?start=2026-01-01&end=2026-02-28&order="+order, nil)
		if w.Code != 200 {
			t.Fatalf("summary failed: %s", w.Body.String())
		}
		if strings.Contains(w.Body.String(), "PRIVATE_") {
			t.Fatal("asset connection details leaked")
		}
		var data struct {
			Sections []models.HomeSection `json:"sections"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &data); err != nil {
			t.Fatal(err)
		}
		assets := data.Sections[len(data.Sections)-1]
		if assets.Key != "assets" || assets.Total != 12 || len(assets.Items) != 10 {
			t.Fatalf("wrong combined count: %+v", assets)
		}
		want := "SSH-6"
		if order == "updated" {
			want = "SSH-1"
		}
		if assets.Items[0].Title != want {
			t.Fatalf("wrong sort: %+v", assets.Items[0])
		}
		sshCount, davCount := 0, 0
		for _, item := range assets.Items {
			switch item.Badge {
			case "ssh":
				sshCount++
				if item.URL != fmt.Sprintf("/admin/assets/ssh-hosts/%d/files", item.ID) {
					t.Fatal(item.URL)
				}
			case "webdav":
				davCount++
				if item.URL != fmt.Sprintf("/admin/assets/webdav-servers/%d/files", item.ID) {
					t.Fatal(item.URL)
				}
			default:
				t.Fatal(item.Badge)
			}
		}
		if sshCount != 5 || davCount != 5 {
			t.Fatalf("missing asset type: ssh=%d dav=%d", sshCount, davCount)
		}
	}
}

func TestPersonalHomeEnglishTemplate(t *testing.T) {
	router, token := initAssetControllerTest(t)
	for _, path := range []string{"/books", "/notes", "/topics", "/labels", "/bookmarks", "/nav", "/shares", "/profile"} {
		req := httptest.NewRequest("GET", path, nil)
		req.Header.Set("Authorization", "Token "+token)
		req.AddCookie(&http.Cookie{Name: "lang", Value: "en"})
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)
		if w.Code != 200 || !strings.Contains(w.Body.String(), `<html lang="en">`) {
			t.Errorf("wrong language on %s (status %d)", path, w.Code)
		}
	}
	req := httptest.NewRequest("GET", "/home", nil)
	req.Header.Set("Authorization", "Token "+token)
	req.AddCookie(&http.Cookie{Name: "lang", Value: "en"})
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != 200 {
		t.Fatalf("home response: %d", w.Code)
	}
	for _, expected := range []string{`<html lang="en">`, `<h1 class="page-title">Personal Home</h1>`, `Recently updated`, `Customize sections`, `New Note`, `Mobile navigation`, `All sections`, `Capture an idea`, `Date range`, `Per section`, `Latest 10`} {
		if !strings.Contains(w.Body.String(), expected) {
			t.Errorf("missing translation: %s", expected)
		}
	}
	for _, old := range []string{`>个人首页<`, `>最近更新<`, `>新建笔记<`, `>全部模块<`, `>记录新想法<`} {
		if strings.Contains(w.Body.String(), old) {
			t.Errorf("untranslated text: %s", old)
		}
	}
}

func TestHomeStatsOwnerAndWeekBoundary(t *testing.T) {
	router, token := initAssetControllerTest(t)
	loc := time.FixedZone("test-east", 8*60*60)
	now := time.Date(2026, 10, 14, 12, 0, 0, 0, loc)
	start := time.Date(2026, 10, 12, 0, 0, 0, 0, loc)
	for i, created := range []time.Time{start, start.Add(-time.Second), now.Add(time.Hour)} {
		if _, err := models.DB.Exec(`INSERT INTO md_blogs(blog_title,blog_identify,blog_type,member_id,create_time,modify_time) VALUES(?,?,'note',1,?,?)`, "Note", fmt.Sprintf("stat-note-%d", i), created.Format("2006-01-02 15:04:05"), created.Format(time.RFC3339)); err != nil {
			t.Fatal(err)
		}
	}
	queries := []string{
		`INSERT INTO md_blogs(blog_title,blog_identify,blog_type,member_id,create_time,modify_time) VALUES('Article','stat-article','article',1,?,?)`,
		`INSERT INTO md_tasks(content,done,member_id,create_time,modify_time) VALUES('Open',0,1,?,?)`,
		`INSERT INTO md_tasks(content,done,member_id,create_time,modify_time) VALUES('Done',1,1,?,?)`,
		`INSERT INTO md_books(book_name,identify,member_id,create_time,modify_time) VALUES('Book','stat-book',1,?,?)`,
		`INSERT INTO md_bookmark(title,url,member_id,create_time,modify_time) VALUES('Link','https://example.com',1,?,?)`,
		`INSERT INTO md_topics(title,member_id,create_time,modify_time) VALUES('Topic',1,?,?)`,
		`INSERT INTO md_blogs(blog_title,blog_identify,blog_type,member_id,create_time,modify_time) VALUES('Other','stat-other','note',99,?,?)`,
		`INSERT INTO md_tasks(content,done,member_id,create_time,modify_time) VALUES('Other',0,99,?,?)`,
	}
	for i, q := range queries {
		var created any = start.UTC().Format(time.RFC3339)
		if i%2 == 0 {
			created = start
		}
		if _, err := models.DB.Exec(q, created, created); err != nil {
			t.Fatal(err)
		}
	}
	stats, err := models.GetHomeStats(1, now)
	if err != nil || stats != (models.HomeStats{Notes: 3, Articles: 1, PendingTasks: 1, CreatedThisWeek: 7}) {
		t.Fatalf("wrong stats %+v: %v", stats, err)
	}
	stats, err = models.GetHomeStats(1, start.AddDate(0, 0, 7))
	if err != nil || stats.CreatedThisWeek != 0 {
		t.Fatalf("week reset %+v: %v", stats, err)
	}
	stats, err = models.GetHomeStats(100, now)
	if err != nil || stats != (models.HomeStats{}) {
		t.Fatalf("empty account %+v: %v", stats, err)
	}
	w := adminAssetRequest(router, token, "GET", "/api/home", nil)
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), `"stats"`) {
		t.Fatal("calendar home must not query or expose statistics")
	}
	if dir := os.Getenv("HOME_SNAPSHOT_DIR"); dir != "" {
		for _, lang := range []string{"zh", "en"} {
			req := httptest.NewRequest("GET", "/home", nil)
			req.Header.Set("Authorization", "Token "+token)
			req.AddCookie(&http.Cookie{Name: "lang", Value: lang})
			w := httptest.NewRecorder()
			router.ServeHTTP(w, req)
			if w.Code != 200 {
				t.Fatal(w.Code)
			}
			if err := os.WriteFile(filepath.Join(dir, "home-b1-"+lang+".html"), w.Body.Bytes(), 0600); err != nil {
				t.Fatal(err)
			}
		}
	}
}

func TestHomeCalendarFilteringValidationAndDefaults(t *testing.T) {
	router, token := initAssetControllerTest(t)
	for i, day := range []string{"2026-10-01", "2026-10-15", "2026-10-15", "2026-10-16"} {
		_, err := models.DB.Exec(`INSERT INTO md_blogs(blog_title,blog_identify,blog_type,member_id,create_time,modify_time) VALUES(?,?,'note',1,?,?)`, fmt.Sprintf("Calendar %d", i), fmt.Sprintf("calendar-%d", i), day+" 10:00:00", day+" 11:00:00")
		if err != nil {
			t.Fatal(err)
		}
	}
	for _, order := range []string{"created", "updated"} {
		w := adminAssetRequest(router, token, "GET", "/api/home?start=2026-10-15&end=2026-10-15&month=2026-10&limit=5&order="+order, nil)
		var data struct {
			Sections   []models.HomeSection `json:"sections"`
			Start, End string
			Limit      int
		}
		if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &data) != nil {
			t.Fatal(w.Code, w.Body.String())
		}
		if data.Sections[0].Total != 2 || len(data.Sections[0].Items) != 2 || len(data.Sections[0].Dates) != 3 || data.Limit != 5 {
			t.Fatalf("unexpected filter: %+v", data)
		}
		for _, item := range data.Sections[0].Items {
			if item.Date != "2026-10-15" {
				t.Fatal(item)
			}
		}
	}
	w := adminAssetRequest(router, token, "GET", "/api/home", nil)
	var defaults struct {
		Start, End string
		Limit      int
	}
	if err := json.Unmarshal(w.Body.Bytes(), &defaults); err != nil {
		t.Fatal(err)
	}
	if defaults.Start != time.Now().Format("2006-01-02") || defaults.End != defaults.Start || defaults.Limit != 10 {
		t.Fatal(defaults)
	}
	for _, query := range []string{"start=bad", "start=2026-10-16&end=2026-10-15", "start=2024-01-01&end=2026-10-15", "limit=10000", "limit=abc", "month=bad", "start=2026-02-30"} {
		w := adminAssetRequest(router, token, "GET", "/api/home?"+query, nil)
		if w.Code != 400 {
			t.Fatalf("accepted %s: %d", query, w.Code)
		}
	}
}

func TestHomeLayoutPersistenceValidationAndIsolation(t *testing.T) {
	router, token := initAssetControllerTest(t)
	other := &models.Member{Account: "layout-other", Password: "test-only", Role: 1}
	if err := other.Insert(); err != nil {
		t.Fatal(err)
	}
	otherToken, err := models.CreateApiToken(other.MemberID, "layout-test")
	if err != nil {
		t.Fatal(err)
	}
	readLayout := func(token string) []models.HomeLayoutItem {
		t.Helper()
		w := adminAssetRequest(router, token, "GET", "/api/home", nil)
		if w.Code != 200 {
			t.Fatalf("read failed: %s", w.Body.String())
		}
		var result struct {
			Layout []models.HomeLayoutItem `json:"layout"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		return result.Layout
	}
	if readLayout(token) != nil {
		t.Fatal("new account should have no saved layout")
	}
	w := adminAssetRequest(router, token, "PUT", "/api/home/layout", map[string]any{"layout": []models.HomeLayoutItem{
		{Key: "articles", Width: 2}, {Key: "notes", Width: 3}, {Key: "tasks", Width: 1, Hidden: true},
	}})
	if w.Code != 200 {
		t.Fatalf("save failed: %s", w.Body.String())
	}
	saved := readLayout(token)
	if len(saved) != 9 || saved[0].Key != "articles" || saved[0].Width != 2 || saved[1].Width != 3 || !saved[2].Hidden {
		t.Fatalf("incorrect layout: %+v", saved)
	}
	if readLayout(otherToken.Token) != nil {
		t.Fatal("layout leaked to another account")
	}
	for _, input := range []any{
		nil,
		[]models.HomeLayoutItem{{Key: "unknown", Width: 1}},
		[]models.HomeLayoutItem{{Key: "notes", Width: 4}},
		[]models.HomeLayoutItem{{Key: "notes", Width: 0}},
		[]models.HomeLayoutItem{{Key: "notes", Width: 1}, {Key: "notes", Width: 2}},
	} {
		w = adminAssetRequest(router, token, "PUT", "/api/home/layout", map[string]any{"layout": input})
		if w.Code != 400 {
			t.Fatalf("invalid layout accepted: %v", input)
		}
	}
	if readLayout(token)[0].Key != "articles" {
		t.Fatal("invalid save overwrote preferences")
	}
	w = httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest("PUT", "/api/home/layout", strings.NewReader(`{"layout":[]}`)))
	if w.Code != 401 {
		t.Fatalf("anonymous save: %d", w.Code)
	}
}
