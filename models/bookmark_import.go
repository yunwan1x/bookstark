package models

import (
	"fmt"
	"io"
	"net/url"
	"strings"
	"time"

	"golang.org/x/net/html"
)

// ImportedBookmark 解析出的书签
type ImportedBookmark struct {
	Title  string   `json:"title"`
	URL    string   `json:"url"`
	Labels []string `json:"labels"`
}

// BookmarkImportResult 导入结果
type BookmarkImportResult struct {
	Total    int `json:"total"`
	Imported int `json:"imported"`
	Skipped  int `json:"skipped"`
}

// ParseBookmarkHTML 解析 Netscape Bookmark HTML 格式
func ParseBookmarkHTML(r io.Reader) ([]ImportedBookmark, error) {
	doc, err := html.Parse(r)
	if err != nil {
		return nil, fmt.Errorf("解析 HTML 失败: %w", err)
	}
	var bookmarks []ImportedBookmark
	var labelStack []string
	var parseNode func(*html.Node)
	parseNode = func(n *html.Node) {
		if n.Type == html.ElementNode {
			switch n.Data {
			case "h3":
				text := extractText(n)
				if text != "" && !isIgnoredFolderName(text) {
					labelStack = append(labelStack, text)
				}
			case "a":
				href := getAttr(n, "href")
				title := extractText(n)
				if href != "" && (strings.HasPrefix(href, "http://") || strings.HasPrefix(href, "https://")) {
					if title == "" {
						if u, err := url.Parse(href); err == nil {
							title = u.Host
						} else {
							title = href
						}
					}
					labels := make([]string, len(labelStack))
					copy(labels, labelStack)
					bookmarks = append(bookmarks, ImportedBookmark{
						Title:  title,
						URL:    href,
						Labels: labels,
					})
				}
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			parseNode(c)
		}
		// 离开 DL 时弹出标签栈
		if n.Type == html.ElementNode && n.Data == "dl" && len(labelStack) > 0 {
			labelStack = labelStack[:len(labelStack)-1]
		}
	}
	parseNode(doc)
	return bookmarks, nil
}

// ImportBookmarks 批量导入书签到指定用户，跳过重复 URL
// customTime 如果不为零值，则用作所有导入书签的 create_time 和 modify_time
func ImportBookmarks(bookmarks []ImportedBookmark, memberID int64, customTime time.Time) (*BookmarkImportResult, error) {
	result := &BookmarkImportResult{Total: len(bookmarks)}
	for _, bm := range bookmarks {
		existing, err := GetBookmarkByURLAndMember(bm.URL, memberID)
		if err != nil {
			return nil, fmt.Errorf("检查书签重复失败: %w", err)
		}
		if existing != nil {
			result.Skipped++
			continue
		}
		bookmark := &Bookmark{
			Title:    bm.Title,
			URL:      bm.URL,
			MemberID: memberID,
		}
		if !customTime.IsZero() {
			bookmark.CreateTime = customTime
			bookmark.ModifyTime = customTime
		}
		if err := bookmark.InsertWithTime(); err != nil {
			return nil, fmt.Errorf("插入书签失败: %w", err)
		}
		if len(bm.Labels) > 0 {
			labelsStr := strings.Join(bm.Labels, ",")
			_ = RebindLabels(bookmark.BookmarkID, "bookmark", labelsStr)
			_ = SyncResourceLabelField(bookmark.BookmarkID, "bookmark")
		}
		result.Imported++
	}
	return result, nil
}

// isIgnoredFolderName 过滤浏览器书签导出中的无意义文件夹名
func isIgnoredFolderName(name string) bool {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return true
	}
	// 浏览器分隔线常导出为 "/" 或 "---" 等文件夹
	switch trimmed {
	case "/", "\\", "|", "-", "--", "---":
		return true
	}
	return false
}

func extractText(n *html.Node) string {
	var sb strings.Builder
	var walk func(*html.Node)
	walk = func(node *html.Node) {
		if node.Type == html.TextNode {
			sb.WriteString(node.Data)
		}
		for c := node.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return strings.TrimSpace(sb.String())
}

func getAttr(n *html.Node, key string) string {
	for _, a := range n.Attr {
		if a.Key == key {
			return a.Val
		}
	}
	return ""
}