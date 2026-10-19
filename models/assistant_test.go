package models

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"
)

func assistantTestDraft(t *testing.T, member int64, p AssistantPayload) (*AssistantSession, AssistantDraft) {
	t.Helper()
	ctx := context.Background()
	s, err := GetAssistantSession(ctx, member)
	if err != nil {
		t.Fatal(err)
	}
	lease := AssistantID()
	if err = LockAssistant(ctx, member, s.ID, lease); err != nil {
		t.Fatal(err)
	}
	d := AssistantDraft{ID: AssistantID(), Payload: p, Status: "pending", CreatedAt: time.Now().Unix()}
	if err = SaveAssistantTurn(ctx, member, s.ID, lease, []AssistantMessage{{Role: "user", Content: "please create"}}, []AssistantDraft{d}); err != nil {
		t.Fatal(err)
	}
	return s, d
}

func TestAssistantConversationsAreNotPersisted(t *testing.T) {
	initAssetTestDB(t)
	ctx := context.Background()
	s, err := GetAssistantSession(ctx, 1)
	if err != nil {
		t.Fatal(err)
	}
	lease := AssistantID()
	if err = LockAssistant(ctx, 1, s.ID, lease); err != nil {
		t.Fatal(err)
	}
	if err = SaveAssistantTurn(ctx, 1, s.ID, lease, []AssistantMessage{{Role: "user", Content: "PRIVATE_CHAT"}}, nil); err != nil {
		t.Fatal(err)
	}
	var raw string
	if err = DB.QueryRow(`SELECT messages FROM md_assistant_sessions WHERE member_id=1`).Scan(&raw); err != nil || raw != "[]" {
		t.Fatalf("stored transcript: %q %v", raw, err)
	}
	if _, err = DB.Exec(`UPDATE md_assistant_sessions SET messages='[{"role":"user","content":"LEGACY_CHAT"}]'`); err != nil {
		t.Fatal(err)
	}
	s, err = GetAssistantSession(ctx, 1)
	if err != nil || len(s.Messages) != 0 {
		t.Fatal("legacy history returned", err)
	}
	if err = createTables(); err != nil {
		t.Fatal(err)
	}
	if err = DB.QueryRow(`SELECT messages FROM md_assistant_sessions WHERE member_id=1`).Scan(&raw); err != nil || raw != "[]" {
		t.Fatalf("legacy transcript not purged: %q %v", raw, err)
	}
}

func TestAssistantStrictOwnedSearch(t *testing.T) {
	initAssetTestDB(t)
	ctx := context.Background()
	for _, b := range []Blog{
		{MemberID: 1, BlogTitle: "owned", BlogContent: "needle body", BlogType: "note", BlogIdentify: "own"},
		{MemberID: 2, BlogTitle: "other", BlogContent: "needle private", BlogType: "note", BlogIdentify: "other", Visibility: 1},
		{MemberID: 1, BlogTitle: "protected needle", BlogContent: "needle password", BlogType: "note", BlogIdentify: "pwd", Password: "test-only"},
		{MemberID: 1, BlogTitle: "html needle", BlogContent: "<b>needle</b>", BlogType: "note", BlogIdentify: "html", EditorType: "html"},
		{MemberID: 1, BlogTitle: "encrypted needle", BlogContent: "ENC:v1:opaque", BlogType: "note", BlogIdentify: "enc"},
	} {
		if err := b.Insert(); err != nil {
			t.Fatal(err)
		}
	}
	items, err := AssistantResources(ctx, 1, "", "needle", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].Title != "owned" {
		t.Fatalf("scope leak: %+v", items)
	}
	items, err = AssistantResources(ctx, 1, "note", "", 2)
	if err != nil || len(items) != 0 {
		t.Fatalf("cross-account read: %v %+v", err, items)
	}
	items, err = AssistantResources(ctx, 1, "note", "%", 0)
	if err != nil || len(items) != 0 {
		t.Fatalf("LIKE wildcard not escaped: %v %+v", err, items)
	}
	if _, err = AssistantResources(ctx, 1, "md_asset_credentials", "", 0); !errors.Is(err, ErrAssistantInput) {
		t.Fatal("unsafe kind accepted")
	}
	for _, q := range []string{
		`INSERT INTO md_tasks(content,due_date,member_id,create_time,modify_time) VALUES('needle task','2026-10-20',1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)`,
		`INSERT INTO md_bookmark(title,description,member_id,create_time,modify_time) VALUES('needle bookmark','description',1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)`,
		`INSERT INTO md_topics(title,question,member_id,create_time,modify_time) VALUES('needle topic','question',1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)`,
		`INSERT INTO md_books(book_id,book_name,identify,member_id,create_time) VALUES(100,'needle book','owned-book',1,CURRENT_TIMESTAMP),(101,'needle other book','other-book',2,CURRENT_TIMESTAMP)`,
		`INSERT INTO md_documents(document_name,book_id,markdown,create_time) VALUES('needle doc',100,'document body',CURRENT_TIMESTAMP),('needle other doc',101,'other body',CURRENT_TIMESTAMP)`,
	} {
		if _, err = DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	for _, kind := range []string{"task", "bookmark", "topic", "book", "document"} {
		items, err = AssistantResources(ctx, 1, kind, "needle", 0)
		if err != nil || len(items) != 1 {
			t.Fatalf("%s query: %+v %v", kind, items, err)
		}
		if kind == "document" && !strings.Contains(items[0].URL, "?doc=") {
			t.Fatal(items[0].URL)
		}
	}
	b := &Blog{MemberID: 1, BlogTitle: "long", BlogContent: strings.Repeat("字", 13000), BlogType: "article", BlogIdentify: "long"}
	if err = b.Insert(); err != nil {
		t.Fatal(err)
	}
	items, err = AssistantResources(ctx, 1, "article", "", b.BlogID)
	if err != nil || len(items) != 1 || !items[0].Truncated || len([]rune(items[0].Content)) != 12000 {
		t.Fatalf("read bounds: %v", err)
	}
}

func TestAssistantConfirmationAtomicAndIdempotent(t *testing.T) {
	initAssetTestDB(t)
	ctx := context.Background()
	s, d := assistantTestDraft(t, 1, AssistantPayload{Kind: "note", Title: "draft", Content: "private content"})
	var n int
	if err := DB.QueryRow(`SELECT count(*) FROM md_blogs`).Scan(&n); err != nil || n != 0 {
		t.Fatal("draft created resource early", err)
	}
	other, err := GetAssistantSession(ctx, 2)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = ResolveAssistantDraft(ctx, 2, other.ID, d.ID, true); !errors.Is(err, ErrAssistantDraft) {
		t.Fatal("foreign draft accessible", err)
	}
	var wg sync.WaitGroup
	errs := make(chan error, 12)
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r, e := ResolveAssistantDraft(ctx, 1, s.ID, d.ID, true)
			if e == nil && (r.Status != "done" || r.URL == "") {
				e = errors.New("bad receipt")
			}
			errs <- e
		}()
	}
	wg.Wait()
	close(errs)
	for err = range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if err = DB.QueryRow(`SELECT count(*) FROM md_blogs WHERE member_id=1 AND visibility=0 AND blog_type='note' AND editor_type='markdown'`).Scan(&n); err != nil || n != 1 {
		t.Fatalf("expected one private note, got %d %v", n, err)
	}
	if _, err = ResolveAssistantDraft(ctx, 1, s.ID, d.ID, false); err != nil {
		t.Fatal(err)
	}
	s, d = assistantTestDraft(t, 1, AssistantPayload{Kind: "task", Content: "task", DueDate: "2026-10-20"})
	if _, err = ResolveAssistantDraft(ctx, 1, s.ID, d.ID, false); err != nil {
		t.Fatal(err)
	}
	r, err := ResolveAssistantDraft(ctx, 1, s.ID, d.ID, true)
	if err != nil || r.Status != "cancelled" {
		t.Fatal("cancelled draft resurrected", err)
	}
	s, d = assistantTestDraft(t, 1, AssistantPayload{Kind: "task", Content: "task", DueDate: "2026-10-20"})
	// A failure during resource insertion must roll back the receipt too.
	if _, err = DB.Exec(`CREATE TRIGGER reject_assistant_task BEFORE INSERT ON md_tasks BEGIN SELECT RAISE(ABORT,'test rejection'); END`); err != nil {
		t.Fatal(err)
	}
	if _, err = ResolveAssistantDraft(ctx, 1, s.ID, d.ID, true); err == nil {
		t.Fatal("expected insert error")
	}
	var status string
	if err = DB.QueryRow(`SELECT status FROM md_assistant_drafts WHERE id=?`, d.ID).Scan(&status); err != nil || status != "pending" {
		t.Fatal("receipt not rolled back", err)
	}
	if _, err = DB.Exec(`DROP TRIGGER reject_assistant_task`); err != nil {
		t.Fatal(err)
	}
	if _, err = ResolveAssistantDraft(ctx, 1, s.ID, d.ID, true); err != nil {
		t.Fatal(err)
	}
	if err = DB.QueryRow(`SELECT count(*) FROM md_tasks`).Scan(&n); err != nil || n != 1 {
		t.Fatal("wrong task count", n, err)
	}
}

func TestAssistantLeaseResetExpiry(t *testing.T) {
	initAssetTestDB(t)
	ctx := context.Background()
	s, d := assistantTestDraft(t, 1, AssistantPayload{Kind: "note", Title: "draft", Content: "body"})
	lease := AssistantID()
	if err := LockAssistant(ctx, 1, s.ID, lease); err != nil {
		t.Fatal(err)
	}
	if err := LockAssistant(ctx, 1, s.ID, AssistantID()); !errors.Is(err, ErrAssistantBusy) {
		t.Fatal(err)
	}
	if err := ResetAssistant(ctx, 1, s.ID); !errors.Is(err, ErrAssistantBusy) {
		t.Fatal(err)
	}
	if _, err := ResolveAssistantDraft(ctx, 1, s.ID, d.ID, true); !errors.Is(err, ErrAssistantBusy) {
		t.Fatal(err)
	}
	UnlockAssistant(1, "wrong lease")
	if err := LockAssistant(ctx, 1, s.ID, AssistantID()); !errors.Is(err, ErrAssistantBusy) {
		t.Fatal("wrong lease unlocked")
	}
	UnlockAssistant(1, lease)
	if _, err := DB.Exec(`UPDATE md_assistant_drafts SET created_at=? WHERE id=?`, time.Now().Add(-25*time.Hour).Unix(), d.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := ResolveAssistantDraft(ctx, 1, s.ID, d.ID, true); !errors.Is(err, ErrAssistantDraft) {
		t.Fatal("expired accepted", err)
	}
	if err := ResetAssistant(ctx, 1, s.ID); err != nil {
		t.Fatal(err)
	}
	next, err := GetAssistantSession(ctx, 1)
	if err != nil || next.ID == s.ID || len(next.Messages) != 0 || len(next.Drafts) != 0 {
		t.Fatal("reset failed", err)
	}
	if err := SaveAssistantTurn(ctx, 1, s.ID, lease, nil, nil); !errors.Is(err, ErrAssistantBusy) {
		t.Fatal("stale turn committed", err)
	}
}
