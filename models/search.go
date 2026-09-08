package models

import (
	"strings"
	"sync"
)

// SearchResult holds the global search response.
type SearchResult struct {
	Counts    map[string]int `json:"counts"`
	Documents []DocHit       `json:"documents"`
	Blogs     []BlogHit      `json:"blogs"`
	Books     []BookHit      `json:"books"`
	Bookmarks []BookmarkHit  `json:"bookmarks"`
	Labels    []LabelHit     `json:"labels"`
	Tasks     []TaskHit      `json:"tasks"`
	Topics    []TopicHit     `json:"topics"`
}

// DocHit is a single document search result.
type DocHit struct {
	DocumentID   int64  `json:"id"`
	DocumentName string `json:"name"`
	Identify     string `json:"identify"`
	BookName     string `json:"book_name"`
	BookIdentify string `json:"book_identify"`
	Snippet      string `json:"snippet"`
}

// BlogHit is a single blog search result.
type BlogHit struct {
	BlogID   int64  `json:"id"`
	Title    string `json:"title"`
	Identify string `json:"identify"`
	Snippet  string `json:"snippet"`
	BlogType string `json:"blog_type"`
}

// BookmarkHit is a single bookmark search result.
type BookmarkHit struct {
	BookmarkID  int64  `json:"id"`
	Title       string `json:"title"`
	URL         string `json:"url"`
	Description string `json:"description"`
}

// BookHit is a single book search result.
type BookHit struct {
	BookID      int64  `json:"id"`
	BookName    string `json:"name"`
	Identify    string `json:"identify"`
	Description string `json:"description"`
	DocCount    int    `json:"doc_count"`
}

// LabelHit is a single label search result.
type LabelHit struct {
	LabelID   int64  `json:"id"`
	LabelName string `json:"name"`
}

// TaskHit is a single task search result.
type TaskHit struct {
	TaskID   int64  `json:"id"`
	Content  string `json:"content"`
	DueDate  string `json:"due_date"`
	Done     bool   `json:"done"`
	ParentID int64  `json:"parent_id"`
	Snippet  string `json:"snippet"`
}

// TopicHit is a single topic search result.
type TopicHit struct {
	TopicID   int64  `json:"id"`
	Title     string `json:"title"`
	Question  string `json:"question"`
	Snippet   string `json:"snippet"`
	ItemCount int    `json:"item_count"`
}

// escapeLike escapes special characters in LIKE patterns: %, _, \
func escapeLike(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `%`, `\%`)
	s = strings.ReplaceAll(s, `_`, `\_`)
	return s
}

const maxSnippetLen = 150

// extractSnippet finds keyword in text and returns surrounding context.
func extractSnippet(text, keyword string) string {
	if text == "" {
		return ""
	}
	lower := strings.ToLower(text)
	kwLower := strings.ToLower(keyword)
	runes := []rune(text)
	lowerRunes := []rune(lower)
	kwRunes := []rune(kwLower)
	kwLen := len(kwRunes)

	idx := -1
	for i := 0; i <= len(lowerRunes)-kwLen; i++ {
		if string(lowerRunes[i:i+kwLen]) == string(kwRunes) {
			idx = i
			break
		}
	}

	if idx < 0 {
		if len(runes) <= maxSnippetLen {
			return text
		}
		return string(runes[:maxSnippetLen]) + "..."
	}

	half := (maxSnippetLen - kwLen) / 2
	start := idx - half
	if start < 0 {
		start = 0
	}
	end := start + maxSnippetLen
	if end > len(runes) {
		end = len(runes)
		start = end - maxSnippetLen
		if start < 0 {
			start = 0
		}
	}

	snippet := string(runes[start:end])
	prefix := ""
	suffix := ""
	if start > 0 {
		prefix = "..."
	}
	if end < len(runes) {
		suffix = "..."
	}
	return prefix + snippet + suffix
}

// isASCIIWord returns true if keyword contains only ASCII letters, digits, hyphens, or underscores.
func isASCIIWord(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_') {
			return false
		}
	}
	return true
}

func isWordChar(r rune) bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_'
}

// matchWordBoundary checks if keyword appears in text with word boundaries on both sides.
func matchWordBoundary(text, keyword string) bool {
	lower := strings.ToLower(text)
	kwLower := strings.ToLower(keyword)
	lowerRunes := []rune(lower)
	kwRunes := []rune(kwLower)
	kwLen := len(kwRunes)
	textLen := len(lowerRunes)

	for i := 0; i <= textLen-kwLen; i++ {
		if string(lowerRunes[i:i+kwLen]) != string(kwRunes) {
			continue
		}
		leftOK := i == 0 || !isWordChar(lowerRunes[i-1])
		rightOK := i+kwLen >= textLen || !isWordChar(lowerRunes[i+kwLen])
		if leftOK && rightOK {
			return true
		}
	}
	return false
}

// GlobalSearch performs a global search across documents, blogs, books, bookmarks, tasks, topics, and labels.
// All queries are scoped to memberID (except labels which are global).
// The queries run in parallel via sync.WaitGroup.
func GlobalSearch(memberID int64, keyword string) (*SearchResult, error) {
	kw := "%" + escapeLike(keyword) + "%"
	wordMode := isASCIIWord(keyword)
	result := &SearchResult{
		Counts: make(map[string]int),
	}

	var (
		docs      []DocHit
		docsErr   error
		blogs     []BlogHit
		blogsErr  error
		books     []BookHit
		booksErr  error
		bms       []BookmarkHit
		bmsErr    error
		labels    []LabelHit
		labelsErr error
		tasks     []TaskHit
		tasksErr  error
		topics    []TopicHit
		topicsErr error
	)

	var wg sync.WaitGroup
	wg.Add(7)

	// Documents
	go func() {
		defer wg.Done()
		rows, err := DB.Query(`
			SELECT d.document_id, d.document_name, d.identify,
			       d.markdown, COALESCE(d.doc_type,'markdown'), b.book_name, b.identify
			FROM md_documents d
			JOIN md_books b ON b.book_id = d.book_id
			WHERE d.member_id = ?
			  AND (d.document_name LIKE ? ESCAPE '\' OR (COALESCE(d.doc_type,'markdown') != 'html' AND d.markdown LIKE ? ESCAPE '\'))
			ORDER BY d.modify_time DESC
			LIMIT 20`,
			memberID, kw, kw,
		)
		if err != nil {
			docsErr = err
			return
		}
		defer rows.Close()

		for rows.Next() {
			var h DocHit
			var markdown string
			var docType string
			if err := rows.Scan(&h.DocumentID, &h.DocumentName, &h.Identify, &markdown, &docType, &h.BookName, &h.BookIdentify); err != nil {
				docsErr = err
				return
			}
			contentMatches := docType != "html" && matchWordBoundary(markdown, keyword)
			if wordMode && !matchWordBoundary(h.DocumentName, keyword) && !contentMatches {
				continue
			}
			if docType != "html" {
				h.Snippet = extractSnippet(markdown, keyword)
			}
			docs = append(docs, h)
		}
	}()

	// Blogs (skip content LIKE for encrypted blogs)
	go func() {
		defer wg.Done()
		rows, err := DB.Query(`
			SELECT blog_id, blog_title, blog_identify, blog_content, COALESCE(blog_desc,''), COALESCE(blog_type,'article'), COALESCE(editor_type,'markdown')
			FROM md_blogs
			WHERE member_id = ?
			  AND (blog_title LIKE ? ESCAPE '\' OR COALESCE(blog_desc,'') LIKE ? ESCAPE '\' OR (COALESCE(editor_type,'markdown') != 'html' AND blog_content NOT LIKE 'ENC:v1:%' AND blog_content LIKE ? ESCAPE '\'))
			ORDER BY modify_time DESC
			LIMIT 20`,
			memberID, kw, kw, kw,
		)
		if err != nil {
			blogsErr = err
			return
		}
		defer rows.Close()

		for rows.Next() {
			var h BlogHit
			var content string
			var desc string
			var editorType string
			if err := rows.Scan(&h.BlogID, &h.Title, &h.Identify, &content, &desc, &h.BlogType, &editorType); err != nil {
				blogsErr = err
				return
			}
			descMatches := matchWordBoundary(desc, keyword)
			contentMatches := editorType != "html" && matchWordBoundary(content, keyword)
			if wordMode && !matchWordBoundary(h.Title, keyword) && !descMatches && !contentMatches {
				continue
			}
			if desc != "" {
				h.Snippet = extractSnippet(desc, keyword)
			} else if editorType != "html" && !strings.HasPrefix(content, encPrefix) {
				h.Snippet = extractSnippet(content, keyword)
			}
			blogs = append(blogs, h)
		}
	}()

	// Books
	go func() {
		defer wg.Done()
		rows, err := DB.Query(`
				SELECT book_id, book_name, identify, description, doc_count
				FROM md_books
				WHERE member_id = ?
				  AND (book_name LIKE ? ESCAPE '\' OR description LIKE ? ESCAPE '\')
				ORDER BY modify_time DESC
				LIMIT 20`,
			memberID, kw, kw,
		)
		if err != nil {
			booksErr = err
			return
		}
		defer rows.Close()

		for rows.Next() {
			var h BookHit
			if err := rows.Scan(&h.BookID, &h.BookName, &h.Identify, &h.Description, &h.DocCount); err != nil {
				booksErr = err
				return
			}
			if wordMode && !matchWordBoundary(h.BookName, keyword) && !matchWordBoundary(h.Description, keyword) {
				continue
			}
			books = append(books, h)
		}
	}()

	// Bookmarks
	go func() {
		defer wg.Done()
		rows, err := DB.Query(`
			SELECT bookmark_id, title, url, description
			FROM md_bookmark
			WHERE member_id = ?
			  AND (title LIKE ? ESCAPE '\' OR url LIKE ? ESCAPE '\' OR description LIKE ? ESCAPE '\')
			ORDER BY modify_time DESC
			LIMIT 20`,
			memberID, kw, kw, kw,
		)
		if err != nil {
			bmsErr = err
			return
		}
		defer rows.Close()

		for rows.Next() {
			var h BookmarkHit
			if err := rows.Scan(&h.BookmarkID, &h.Title, &h.URL, &h.Description); err != nil {
				bmsErr = err
				return
			}
			if wordMode && !matchWordBoundary(h.Title, keyword) && !matchWordBoundary(h.URL, keyword) && !matchWordBoundary(h.Description, keyword) {
				continue
			}
			bms = append(bms, h)
		}
	}()

	// Labels (global, no member_id filter)
	go func() {
		defer wg.Done()
		rows, err := DB.Query(`
			SELECT label_id, label_name
			FROM md_label
			WHERE label_name LIKE ? ESCAPE '\'
			ORDER BY label_name
			LIMIT 20`,
			kw,
		)
		if err != nil {
			labelsErr = err
			return
		}
		defer rows.Close()

		for rows.Next() {
			var h LabelHit
			if err := rows.Scan(&h.LabelID, &h.LabelName); err != nil {
				labelsErr = err
				return
			}
			if wordMode && !matchWordBoundary(h.LabelName, keyword) {
				continue
			}
			labels = append(labels, h)
		}
	}()

	// Tasks
	go func() {
		defer wg.Done()
		rows, err := DB.Query(`
			SELECT task_id, content, due_date, done, parent_id
			FROM md_tasks
			WHERE member_id = ?
			  AND content LIKE ? ESCAPE '\'
			ORDER BY modify_time DESC
			LIMIT 20`,
			memberID, kw,
		)
		if err != nil {
			tasksErr = err
			return
		}
		defer rows.Close()

		for rows.Next() {
			var h TaskHit
			var done int
			if err := rows.Scan(&h.TaskID, &h.Content, &h.DueDate, &done, &h.ParentID); err != nil {
				tasksErr = err
				return
			}
			if wordMode && !matchWordBoundary(h.Content, keyword) {
				continue
			}
			h.Done = done == 1
			h.Snippet = extractSnippet(h.Content, keyword)
			tasks = append(tasks, h)
		}
	}()

	// Topics
	go func() {
		defer wg.Done()
		rows, err := DB.Query(`
				SELECT t.topic_id, t.title, t.question,
					(SELECT COUNT(*) FROM md_topic_resources tr WHERE tr.topic_id = t.topic_id) AS item_count,
					COALESCE((
						SELECT GROUP_CONCAT(ts.content, char(10))
						FROM md_topic_summaries ts
						WHERE ts.topic_id = t.topic_id
					), '') AS summary_text,
					COALESCE((
						SELECT GROUP_CONCAT(tr.title_snapshot || char(10) || tr.desc_snapshot, char(10))
						FROM md_topic_resources tr
						WHERE tr.topic_id = t.topic_id
					), '') AS resource_text,
					COALESCE((
						SELECT GROUP_CONCAT(task.content, char(10))
						FROM md_tasks task
						WHERE task.topic_id = t.topic_id
					), '') AS task_text
				FROM md_topics t
				WHERE t.member_id = ?
				  AND (t.title LIKE ? ESCAPE '\' OR t.question LIKE ? ESCAPE '\'
					OR EXISTS (
						SELECT 1 FROM md_topic_summaries ts
						WHERE ts.topic_id = t.topic_id AND ts.content LIKE ? ESCAPE '\'
					)
					OR EXISTS (
						SELECT 1 FROM md_topic_resources tr
						WHERE tr.topic_id = t.topic_id
						  AND (tr.title_snapshot LIKE ? ESCAPE '\' OR tr.desc_snapshot LIKE ? ESCAPE '\')
					)
					OR EXISTS (
						SELECT 1 FROM md_tasks task
						WHERE task.topic_id = t.topic_id AND task.content LIKE ? ESCAPE '\'
					))
			ORDER BY t.modify_time DESC
			LIMIT 20`,
			memberID, kw, kw, kw, kw, kw, kw,
		)
		if err != nil {
			topicsErr = err
			return
		}
		defer rows.Close()

		for rows.Next() {
			var h TopicHit
			var summaryText, resourceText, taskText string
			if err := rows.Scan(&h.TopicID, &h.Title, &h.Question, &h.ItemCount, &summaryText, &resourceText, &taskText); err != nil {
				topicsErr = err
				return
			}
			combined := h.Question + "\n" + summaryText + "\n" + resourceText + "\n" + taskText
			if wordMode && !matchWordBoundary(h.Title, keyword) && !matchWordBoundary(combined, keyword) {
				continue
			}
			h.Snippet = extractSnippet(combined, keyword)
			topics = append(topics, h)
		}
	}()

	wg.Wait()

	// Check errors
	if docsErr != nil {
		return nil, docsErr
	}
	if blogsErr != nil {
		return nil, blogsErr
	}
	if booksErr != nil {
		return nil, booksErr
	}
	if bmsErr != nil {
		return nil, bmsErr
	}
	if labelsErr != nil {
		return nil, labelsErr
	}
	if tasksErr != nil {
		return nil, tasksErr
	}
	if topicsErr != nil {
		return nil, topicsErr
	}

	result.Documents = docs
	result.Blogs = blogs
	result.Books = books
	result.Bookmarks = bms
	result.Labels = labels
	result.Tasks = tasks
	result.Topics = topics

	result.Counts["documents"] = len(docs)
	result.Counts["blogs"] = len(blogs)
	result.Counts["books"] = len(books)
	result.Counts["bookmarks"] = len(bms)
	result.Counts["labels"] = len(labels)
	result.Counts["tasks"] = len(tasks)
	result.Counts["topics"] = len(topics)

	return result, nil
}
