package models

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"
)

type sqlExecutor interface {
	Exec(string, ...any) (sql.Result, error)
}

var ErrAssistantBusy = errors.New("assistant busy or stale session")
var ErrAssistantDraft = errors.New("draft unavailable")
var ErrAssistantInput = errors.New("invalid assistant input")

type AssistantMessage struct {
	CreatedAt int64               `json:"created_at,omitempty"`
	Role      string              `json:"role"`
	Content   string              `json:"content"`
	Sources   []AssistantResource `json:"sources,omitempty"`
}
type AssistantPayload struct {
	Kind    string `json:"kind"`
	Title   string `json:"title"`
	Content string `json:"content"`
	DueDate string `json:"due_date"`
}
type AssistantDraft struct {
	ID        string           `json:"id"`
	Payload   AssistantPayload `json:"payload"`
	Status    string           `json:"status"`
	URL       string           `json:"url"`
	CreatedAt int64            `json:"created_at"`
}
type AssistantSession struct {
	ID       string             `json:"id"`
	Messages []AssistantMessage `json:"messages"`
	Drafts   []AssistantDraft   `json:"drafts"`
	Busy     bool               `json:"busy"`
}

func AssistantID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b[:])
}

func GetAssistantSession(ctx context.Context, member int64) (*AssistantSession, error) {
	if member <= 0 {
		return nil, ErrAssistantInput
	}
	_, err := DB.ExecContext(ctx, `INSERT INTO md_assistant_sessions(member_id,session_id) VALUES(?,?) ON CONFLICT(member_id) DO NOTHING`, member, AssistantID())
	if err != nil {
		return nil, err
	}
	s := &AssistantSession{Messages: []AssistantMessage{}, Drafts: []AssistantDraft{}}
	var raw string
	var busyUntil int64
	if err = DB.QueryRowContext(ctx, `SELECT session_id,busy_until FROM md_assistant_sessions WHERE member_id=?`, member).Scan(&s.ID, &busyUntil); err != nil {
		return nil, err
	}
	s.Busy = busyUntil > time.Now().Unix()
	rows, err := DB.QueryContext(ctx, `SELECT id,payload,status,result_url,created_at FROM md_assistant_drafts WHERE member_id=? AND session_id=? ORDER BY created_at,id`, member, s.ID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var d AssistantDraft
		if err = rows.Scan(&d.ID, &raw, &d.Status, &d.URL, &d.CreatedAt); err != nil {
			return nil, err
		}
		if err = json.Unmarshal([]byte(raw), &d.Payload); err != nil {
			return nil, err
		}
		if d.Status == "pending" && d.CreatedAt < time.Now().Add(-24*time.Hour).Unix() {
			d.Status = "expired"
		}
		s.Drafts = append(s.Drafts, d)
	}
	return s, rows.Err()
}

// A DB lease serializes turns across browser tabs and app instances. It expires
// after crashes; the controller's upstream deadline is shorter than the lease.
func LockAssistant(ctx context.Context, member int64, session, lease string) error {
	r, err := DB.ExecContext(ctx, `UPDATE md_assistant_sessions SET lease=?,busy_until=? WHERE member_id=? AND session_id=? AND busy_until<=?`, lease, time.Now().Add(3*time.Minute).Unix(), member, session, time.Now().Unix())
	if err != nil {
		return err
	}
	n, _ := r.RowsAffected()
	if n != 1 {
		return ErrAssistantBusy
	}
	return nil
}
func UnlockAssistant(member int64, lease string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, _ = DB.ExecContext(ctx, `UPDATE md_assistant_sessions SET lease='',busy_until=0 WHERE member_id=? AND lease=?`, member, lease)
}

func SaveAssistantTurn(ctx context.Context, member int64, session, lease string, messages []AssistantMessage, drafts []AssistantDraft) error {
	raw, err := json.Marshal(messages)
	if err != nil {
		return err
	}
	if len(raw) > 192*1024 || len(messages) > 40 || len(drafts) > 5 {
		return ErrAssistantInput
	}
	tx, err := DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	// Conversation text lives only in the browser. Persist only the lease and
	// draft receipts needed for authorized, idempotent confirmation.
	r, err := tx.ExecContext(ctx, `UPDATE md_assistant_sessions SET messages='[]',lease='',busy_until=0 WHERE member_id=? AND session_id=? AND lease=? AND busy_until>?`, member, session, lease, time.Now().Unix())
	if err != nil {
		return err
	}
	n, _ := r.RowsAffected()
	if n != 1 {
		return ErrAssistantBusy
	}
	for _, d := range drafts {
		if err = ValidateAssistantPayload(&d.Payload); err != nil {
			return err
		}
		data, _ := json.Marshal(d.Payload)
		if _, err = tx.ExecContext(ctx, `INSERT INTO md_assistant_drafts(id,member_id,session_id,payload,created_at) VALUES(?,?,?,?,?)`, d.ID, member, session, string(data), d.CreatedAt); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func ResetAssistant(ctx context.Context, member int64, session string) error {
	tx, err := DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	r, err := tx.ExecContext(ctx, `UPDATE md_assistant_sessions SET session_id=?,messages='[]' WHERE member_id=? AND session_id=? AND busy_until<=?`, AssistantID(), member, session, time.Now().Unix())
	if err != nil {
		return err
	}
	n, _ := r.RowsAffected()
	if n != 1 {
		return ErrAssistantBusy
	}
	_, err = tx.ExecContext(ctx, `UPDATE md_assistant_drafts SET status='cancelled',finished_at=? WHERE member_id=? AND session_id=? AND status='pending'`, time.Now().Unix(), member, session)
	if err != nil {
		return err
	}
	// Bound retention of old draft/audit payloads to 30 days, for this account only.
	_, err = tx.ExecContext(ctx, `DELETE FROM md_assistant_drafts WHERE member_id=? AND created_at<?`, member, time.Now().Add(-30*24*time.Hour).Unix())
	if err != nil {
		return err
	}
	return tx.Commit()
}

func ValidateAssistantPayload(p *AssistantPayload) error {
	p.Title = strings.TrimSpace(p.Title)
	p.Content = strings.TrimSpace(p.Content)
	if p.Content == "" || !utf8.ValidString(p.Content) || !utf8.ValidString(p.Title) {
		return ErrAssistantInput
	}
	switch p.Kind {
	case "note":
		if p.Title == "" || utf8.RuneCountInString(p.Title) > 200 || len(p.Content) > 20000 || p.DueDate != "" {
			return ErrAssistantInput
		}
	case "task":
		if utf8.RuneCountInString(p.Content) > 1000 || p.Title != "" {
			return ErrAssistantInput
		}
		if _, err := time.Parse("2006-01-02", p.DueDate); err != nil {
			return ErrAssistantInput
		}
	default:
		return ErrAssistantInput
	}
	return nil
}

// Confirmation is not a model tool. The authenticated user must confirm an
// immutable server-side draft. Claim, creation, and receipt commit atomically.
func ResolveAssistantDraft(ctx context.Context, member int64, session, id string, confirm bool) (*AssistantDraft, error) {
	tx, err := DB.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	// Acquire SQLite's writer before reading: no deferred-read upgrade races.
	r, err := tx.ExecContext(ctx, `UPDATE md_assistant_sessions SET session_id=session_id WHERE member_id=? AND session_id=? AND busy_until<=?`, member, session, time.Now().Unix())
	if err != nil {
		return nil, err
	}
	n, _ := r.RowsAffected()
	if n != 1 {
		return nil, ErrAssistantBusy
	}
	var raw string
	d := &AssistantDraft{ID: id}
	err = tx.QueryRowContext(ctx, `SELECT payload,status,result_url,created_at FROM md_assistant_drafts WHERE id=? AND member_id=? AND session_id=?`, id, member, session).Scan(&raw, &d.Status, &d.URL, &d.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrAssistantDraft
	}
	if err != nil {
		return nil, err
	}
	if err = json.Unmarshal([]byte(raw), &d.Payload); err != nil {
		return nil, err
	}
	if d.Status == "done" || d.Status == "cancelled" {
		return d, nil
	}
	if d.Status != "pending" || d.CreatedAt < time.Now().Add(-24*time.Hour).Unix() {
		return nil, ErrAssistantDraft
	}
	if err = ValidateAssistantPayload(&d.Payload); err != nil {
		return nil, err
	}
	d.Status = "cancelled"
	if confirm {
		switch d.Payload.Kind {
		case "note":
			b := &Blog{MemberID: member, BlogType: "note", EditorType: "markdown", Visibility: 0, BlogIdentify: "note-" + d.ID, BlogTitle: d.Payload.Title, BlogContent: d.Payload.Content}
			if err = b.insertWith(tx); err != nil {
				return nil, err
			}
			d.URL = fmt.Sprintf("/notes?tab=notes&id=%d", b.BlogID)
		case "task":
			t := &Task{MemberID: member, Content: d.Payload.Content, DueDate: d.Payload.DueDate}
			if err = createTaskWith(tx, t); err != nil {
				return nil, err
			}
			d.URL = fmt.Sprintf("/notes?tab=tasks&task_id=%d", t.TaskID)
		}
		d.Status = "done"
	}
	_, err = tx.ExecContext(ctx, `UPDATE md_assistant_drafts SET status=?,result_url=?,finished_at=? WHERE id=? AND member_id=?`, d.Status, d.URL, time.Now().Unix(), id, member)
	if err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, err
	}
	return d, nil
}

type AssistantResource struct {
	Kind      string `json:"kind"`
	ID        int64  `json:"id"`
	Title     string `json:"title"`
	Content   string `json:"content,omitempty"`
	URL       string `json:"url"`
	Truncated bool   `json:"truncated,omitempty"`
}

// Static SQL only; caller-supplied type/IDs never alter authorization. Even
// administrators are restricted to their own records. Protected and non-text
// editor contents, assets, credentials, and external URLs are never read.
var assistantQueries = map[string]string{
	"note":     `SELECT blog_id,blog_title,COALESCE(blog_content,''),'' FROM md_blogs WHERE member_id=? AND blog_type='note' AND password='' AND editor_type='markdown' AND COALESCE(blog_content,'') NOT LIKE 'ENC:%'`,
	"article":  `SELECT blog_id,blog_title,COALESCE(blog_content,''),'' FROM md_blogs WHERE member_id=? AND blog_type='article' AND password='' AND editor_type='markdown' AND COALESCE(blog_content,'') NOT LIKE 'ENC:%'`,
	"task":     `SELECT task_id,content,content || char(10) || due_date || CASE WHEN done=1 THEN ' [done]' ELSE ' [pending]' END,'' FROM md_tasks WHERE member_id=?`,
	"bookmark": `SELECT bookmark_id,title,description,'' FROM md_bookmark WHERE member_id=?`,
	"book":     `SELECT book_id,book_name,description,identify FROM md_books WHERE member_id=?`,
	"document": `SELECT d.document_id,d.document_name,COALESCE(d.markdown,''),b.identify FROM md_documents d JOIN md_books b ON b.book_id=d.book_id WHERE b.member_id=? AND d.doc_type='markdown' AND COALESCE(d.markdown,'') NOT LIKE 'ENC:%'`,
	"topic":    `SELECT topic_id,title,question,'' FROM md_topics WHERE member_id=?`,
}

func AssistantResources(ctx context.Context, member int64, kind, query string, id int64) ([]AssistantResource, error) {
	if member <= 0 || len(query) > 300 || id < 0 {
		return nil, ErrAssistantInput
	}
	kinds := []string{"note", "article", "task", "bookmark", "book", "document", "topic"}
	if kind != "" {
		if _, ok := assistantQueries[kind]; !ok {
			return nil, ErrAssistantInput
		}
		kinds = []string{kind}
	}
	if id > 0 && kind == "" {
		return nil, ErrAssistantInput
	}
	results := []AssistantResource{}
	for _, k := range kinds {
		// Wrap trusted projections to apply bounded matching/slicing in SQLite.
		q := `WITH owned(id,title,content,target) AS (` + assistantQueries[k] + `) SELECT id,substr(title,1,300),substr(content,1,?),target,length(content) FROM owned WHERE `
		limit := 700
		if id > 0 {
			limit = 12000
		}
		args := []any{member, limit}
		if id > 0 {
			q += `id=?`
			args = append(args, id)
		} else {
			q += `(title LIKE ? ESCAPE '\' OR content LIKE ? ESCAPE '\')`
			pattern := "%" + escapeLike(strings.TrimSpace(query)) + "%"
			args = append(args, pattern, pattern)
		}
		q += ` ORDER BY id DESC LIMIT ?`
		args = append(args, 20-len(results))
		rows, err := DB.QueryContext(ctx, q, args...)
		if err != nil {
			return nil, err
		}
		for rows.Next() {
			v := AssistantResource{Kind: k}
			var target string
			var size int
			if err = rows.Scan(&v.ID, &v.Title, &v.Content, &target, &size); err != nil {
				rows.Close()
				return nil, err
			}
			v.Truncated = size > limit
			switch k {
			case "note":
				v.URL = fmt.Sprintf("/notes?tab=notes&id=%d", v.ID)
			case "article":
				v.URL = fmt.Sprintf("/notes?tab=articles&id=%d", v.ID)
			case "task":
				v.URL = fmt.Sprintf("/notes?tab=tasks&task_id=%d", v.ID)
			case "bookmark":
				v.URL = fmt.Sprintf("/bookmarks?id=%d", v.ID)
			case "book":
				v.URL = "/books/" + url.PathEscape(target) + "/edit"
			case "document":
				v.URL = fmt.Sprintf("/books/%s/edit?doc=%d", url.PathEscape(target), v.ID)
			case "topic":
				v.URL = fmt.Sprintf("/topics?id=%d", v.ID)
			}
			results = append(results, v)
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return nil, err
		}
		if len(results) >= 20 {
			break
		}
	}
	return results, nil
}
