package models

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"
)

func TestBookmarkInsertRetriesBusyWriter(t *testing.T) {
	initAssetTestDB(t)
	DB.SetMaxOpenConns(2)
	conn, err := DB.Conn(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if _, err := conn.ExecContext(context.Background(), "BEGIN IMMEDIATE"); err != nil {
		t.Fatal(err)
	}
	defer conn.ExecContext(context.Background(), "ROLLBACK")
	// The only remaining pooled connection fails fast while the writer is held.
	if _, err := DB.Exec("PRAGMA busy_timeout=1"); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	b := &Bookmark{Title: "retry", URL: "https://example.com/retry", MemberID: 1}
	go func() { done <- b.Insert() }()
	select {
	case err := <-done:
		t.Fatalf("insert finished before write lock released: %v", err)
	case <-time.After(80 * time.Millisecond):
	}
	if _, err := conn.ExecContext(context.Background(), "COMMIT"); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	var count int
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_bookmark WHERE url=?", b.URL).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("retry created %d bookmarks", count)
	}
}

func TestBookmarkAtomicInsertConcurrent(t *testing.T) {
	initAssetTestDB(t)
	const count = 80
	var wg sync.WaitGroup
	start := make(chan struct{})
	errs := make(chan error, count+1)
	// Simulate unrelated background writes while bookmarks allocate sort values.
	wg.Add(1)
	go func() {
		defer wg.Done()
		<-start
		for i := 0; i < count; i++ {
			if _, err := DB.Exec("UPDATE md_members SET account=account WHERE member_id=1"); err != nil {
				errs <- err
				return
			}
		}
	}()
	for i := 0; i < count; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			b := &Bookmark{Title: "test", URL: fmt.Sprintf("https://example.com/%d", i), MemberID: 1}
			var err error
			if i%2 == 0 {
				err = b.Insert()
			} else {
				err = b.InsertWithTime()
			}
			if err != nil {
				errs <- err
				return
			}
			if b.BookmarkID <= 0 || b.OrderSort <= 0 {
				errs <- fmt.Errorf("missing returned id/order: %d/%d", b.BookmarkID, b.OrderSort)
			}
		}(i)
	}
	close(start)
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	var total, distinct, min, max int
	if err := DB.QueryRow("SELECT COUNT(*), COUNT(DISTINCT order_sort), MIN(order_sort), MAX(order_sort) FROM md_bookmark WHERE member_id=1").Scan(&total, &distinct, &min, &max); err != nil {
		t.Fatal(err)
	}
	if total != count || distinct != count || min != 1 || max != count {
		t.Fatalf("unexpected ordering: %d %d %d %d", total, distinct, min, max)
	}
}

func TestBookmarkAtomicInsertImportAndConstraints(t *testing.T) {
	initAssetTestDB(t)
	ct := time.Date(2020, 1, 2, 3, 4, 5, 0, time.UTC)
	b := &Bookmark{Title: "import", URL: "https://example.com/import", MemberID: 1, OrderSort: 42, CreateTime: ct, ModifyTime: ct.Add(time.Hour), IsPublic: true, NavVisible: true}
	if err := b.InsertWithTime(); err != nil {
		t.Fatal(err)
	}
	var order int
	var created, modified time.Time
	var public, visible bool
	if err := DB.QueryRow("SELECT order_sort, create_time, modify_time, is_public, nav_visible FROM md_bookmark WHERE bookmark_id=?", b.BookmarkID).Scan(&order, &created, &modified, &public, &visible); err != nil {
		t.Fatal(err)
	}
	if order != 42 || !created.Equal(ct) || !modified.Equal(ct.Add(time.Hour)) || !public || !visible {
		t.Fatal("import metadata changed")
	}
	next := &Bookmark{Title: "next", URL: "https://example.com/next", MemberID: 1}
	if err := next.Insert(); err != nil {
		t.Fatal(err)
	}
	if next.OrderSort != 43 {
		t.Fatalf("order=%d", next.OrderSort)
	}
	duplicate := &Bookmark{Title: "duplicate", URL: b.URL, MemberID: 1}
	if err := duplicate.Insert(); err == nil || IsBookmarkBusyError(err) {
		t.Fatalf("expected permanent constraint error, got %v", err)
	}
}
