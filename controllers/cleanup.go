package controllers

import (
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"bookstark/models"

	"github.com/gin-gonic/gin"
)

// CleanupState tracks the running bookmark cleanup background task.
type CleanupState struct {
	mu         sync.Mutex
	Running    bool   `json:"running"`
	Progress   int    `json:"progress"`
	Total      int    `json:"total"`
	Found      int    `json:"found"`
	Status     string `json:"status_text"`
	LastResult string `json:"last_result"`
	StartTime  string `json:"start_time"`
	EndTime    string `json:"end_time"`
	MemberID   int64  `json:"member_id"`
	cancel     chan struct{}
}

var bookmarkCleanup = &CleanupState{}

var parkedKeywords = []string{
	"domain for sale",
	"buy this domain",
	"domain is for sale",
	"此域名出售",
	"域名出售",
	"域名停靠",
	"domain parking",
	"parked domain",
	"this domain has expired",
	"域名已过期",
	"sedoparking",
	"hugedomains",
	"dan.com",
	"afternic",
}

// StartBookmarkCleanup starts a background task that checks all bookmarks
// (optionally filtered by member_id) and moves invalid ones to trash.
func StartBookmarkCleanup(c *gin.Context) {
	var req struct {
		MemberID    int64 `json:"member_id"`
		Timeout     int   `json:"timeout"`
		Concurrency int   `json:"concurrency"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "参数错误")
		return
	}
	if req.Timeout < 1 || req.Timeout > 30 {
		req.Timeout = 10
	}
	if req.Concurrency < 1 || req.Concurrency > 30 {
		req.Concurrency = 3
	}

	bookmarkCleanup.mu.Lock()
	if bookmarkCleanup.Running {
		bookmarkCleanup.mu.Unlock()
		apiError(c, http.StatusConflict, "清理任务已在运行中")
		return
	}
	bookmarkCleanup.Running = true
	bookmarkCleanup.Progress = 0
	bookmarkCleanup.Total = 0
	bookmarkCleanup.Found = 0
	bookmarkCleanup.Status = "正在初始化..."
	bookmarkCleanup.StartTime = time.Now().Format("2006-01-02 15:04:05")
	bookmarkCleanup.EndTime = ""
	bookmarkCleanup.MemberID = req.MemberID
	bookmarkCleanup.cancel = make(chan struct{})
	bookmarkCleanup.mu.Unlock()

	go runCleanup(req.MemberID, req.Timeout, req.Concurrency)

	apiSuccess(c, gin.H{"message": "清理任务已启动"})
}

// GetCleanupStatus returns the current cleanup task status.
func GetCleanupStatus(c *gin.Context) {
	loadCleanupStateFromDB()
	bookmarkCleanup.mu.Lock()
	defer bookmarkCleanup.mu.Unlock()
	apiSuccess(c, gin.H{
		"running":     bookmarkCleanup.Running,
		"progress":    bookmarkCleanup.Progress,
		"total":       bookmarkCleanup.Total,
		"found":       bookmarkCleanup.Found,
		"status_text": bookmarkCleanup.Status,
		"last_result": bookmarkCleanup.LastResult,
		"start_time":  bookmarkCleanup.StartTime,
		"end_time":    bookmarkCleanup.EndTime,
	})
}

// CancelCleanup cancels a running cleanup task.
func CancelCleanup(c *gin.Context) {
	bookmarkCleanup.mu.Lock()
	if !bookmarkCleanup.Running {
		bookmarkCleanup.mu.Unlock()
		apiError(c, http.StatusBadRequest, "没有运行中的清理任务")
		return
	}
	if bookmarkCleanup.cancel != nil {
		close(bookmarkCleanup.cancel)
		bookmarkCleanup.cancel = nil
	}
	bookmarkCleanup.Running = false
	bookmarkCleanup.Status = "已取消"
	bookmarkCleanup.LastResult = "已取消"
	bookmarkCleanup.EndTime = time.Now().Format("2006-01-02 15:04:05")
	startTime := bookmarkCleanup.StartTime
	endTime := bookmarkCleanup.EndTime
	bookmarkCleanup.mu.Unlock()
	persistCleanupState("已取消", startTime, endTime)
	apiSuccess(c, gin.H{"message": "清理任务已取消"})
}

const cleanupBatchSize = 100

func runCleanup(memberID int64, timeoutSec int, concurrency int) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("runCleanup: panic recovered: %v", r)
			setCleanupDone("任务异常终止")
		}
	}()

	var total int64
	countArgs := []interface{}{}
	countWhere := ""
	if memberID > 0 {
		countWhere = " WHERE member_id = ?"
		countArgs = append(countArgs, memberID)
	}
	err := models.DB.QueryRow("SELECT COUNT(*) FROM md_bookmark"+countWhere, countArgs...).Scan(&total)
	if err != nil {
		setCleanupDone("查询书签数量失败: " + err.Error())
		return
	}
	if total == 0 {
		setCleanupDone("没有需要检查的书签")
		return
	}

	client := &http.Client{
		Timeout: time.Duration(timeoutSec) * time.Second,
		Transport: &http.Transport{
			MaxIdleConns:    10,
			MaxConnsPerHost: 5,
			IdleConnTimeout: 30 * time.Second,
		},
	}

	fetchSem := make(chan struct{}, concurrency)

	bookmarkCleanup.mu.Lock()
	bookmarkCleanup.Total = int(total)
	bookmarkCleanup.Progress = 0
	bookmarkCleanup.Status = fmt.Sprintf("正在检查 %d 个书签...", total)
	bookmarkCleanup.mu.Unlock()

	var flushMu sync.Mutex
	var flushIDs []int64
	var cursor int64 = 0
	var wg sync.WaitGroup

batchLoop:
	for {
		bookmarkCleanup.mu.Lock()
		if !bookmarkCleanup.Running {
			bookmarkCleanup.mu.Unlock()
			break
		}
		bookmarkCleanup.mu.Unlock()

		select {
		case <-bookmarkCleanup.cancel:
			break batchLoop
		default:
		}

		batchArgs := []interface{}{cursor, cleanupBatchSize}
		batchWhere := " WHERE b.bookmark_id > ?"
		if memberID > 0 {
			batchWhere += " AND b.member_id = ?"
			batchArgs = []interface{}{cursor, memberID, cleanupBatchSize}
		}
		rows, err := models.DB.Query("SELECT b.bookmark_id, b.url FROM md_bookmark b"+batchWhere+" ORDER BY b.bookmark_id LIMIT ?", batchArgs...)
		if err != nil {
			log.Printf("runCleanup: query batch failed: %v", err)
			break
		}

		type bmEntry struct {
			id  int64
			url string
		}
		var batch []bmEntry
		for rows.Next() {
			var e bmEntry
			if err := rows.Scan(&e.id, &e.url); err != nil {
				continue
			}
			batch = append(batch, e)
		}
		rows.Close()

		if len(batch) == 0 {
			break
		}

		cursor = batch[len(batch)-1].id

		for _, e := range batch {
			select {
			case <-bookmarkCleanup.cancel:
				break batchLoop
			default:
			}

			fetchSem <- struct{}{}
			wg.Add(1)

			go func(entry bmEntry) {
				defer wg.Done()
				defer func() { <-fetchSem }()

				select {
				case <-bookmarkCleanup.cancel:
					return
				default:
				}

				if checkBookmarkInvalid(client, entry.url) {
					bookmarkCleanup.mu.Lock()
					bookmarkCleanup.Found++
					bookmarkCleanup.mu.Unlock()
					flushMu.Lock()
					flushIDs = append(flushIDs, entry.id)
					shouldFlush := len(flushIDs) >= 50
					flushMu.Unlock()
					if shouldFlush {
						flushMu.Lock()
						ids := flushIDs
						flushIDs = nil
						flushMu.Unlock()
						if err := models.BatchDeleteBookmarks(ids); err != nil {
							log.Printf("runCleanup: BatchDeleteBookmarks failed: %v", err)
						}
					}
				}
			}(e)
		}

		wg.Wait()

		bookmarkCleanup.mu.Lock()
		bookmarkCleanup.Progress += len(batch)
		if bookmarkCleanup.Progress > bookmarkCleanup.Total {
			bookmarkCleanup.Progress = bookmarkCleanup.Total
		}
		bookmarkCleanup.Status = fmt.Sprintf("正在检查 %d/%d，已发现 %d 个无效",
			bookmarkCleanup.Progress, bookmarkCleanup.Total, bookmarkCleanup.Found)
		bookmarkCleanup.mu.Unlock()
	}

	wg.Wait()

	flushMu.Lock()
	remaining := flushIDs
	flushIDs = nil
	flushMu.Unlock()
	if len(remaining) > 0 {
		if err := models.BatchDeleteBookmarks(remaining); err != nil {
			log.Printf("runCleanup: BatchDeleteBookmarks failed: %v", err)
		}
	}

	bookmarkCleanup.mu.Lock()
	found := bookmarkCleanup.Found
	bookmarkCleanup.mu.Unlock()

	if found > 0 {
		setCleanupDone(fmt.Sprintf("检查完成，共发现 %d 个无效书签已移至回收站", found))
	} else {
		setCleanupDone("检查完成，未发现无效书签")
	}
}

// checkBookmarkInvalid checks a single bookmark URL.
// Returns true only for high-confidence dead bookmarks:
// DNS NXDOMAIN, domain parking, or HTTP 404.
func checkBookmarkInvalid(client *http.Client, rawURL string) bool {
	u, err := url.Parse(rawURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		return false
	}
	hostname := u.Hostname()
	if hostname == "" {
		return false
	}

	// Step 1: DNS pre-check — only NXDOMAIN is conclusive
	_, err = net.LookupHost(hostname)
	if err != nil {
		var dnsErr *net.DNSError
		if errors.As(err, &dnsErr) && dnsErr.IsNotFound {
			return true
		}
		return false
	}

	// Step 2: HTTP GET
	req, err := http.NewRequest("GET", rawURL, nil)
	if err != nil {
		return false
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "text/html,application/xhtml+xml")

	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return true
	}

	if isCloudflareResponse(resp) {
		sc := resp.StatusCode
		if sc == 403 || sc == 429 || sc == 503 || (sc >= 520 && sc <= 529) {
			return false
		}
	}

	if resp.StatusCode != http.StatusOK {
		return false
	}

	// Step 3: Check for domain parking keywords
	body := io.LimitReader(resp.Body, 64*1024)
	data, _ := io.ReadAll(body)
	html := strings.ToLower(string(data))

	for _, kw := range parkedKeywords {
		if strings.Contains(html, strings.ToLower(kw)) {
			return true
		}
	}

	return false
}

func isCloudflareResponse(resp *http.Response) bool {
	if strings.Contains(strings.ToLower(resp.Header.Get("Server")), "cloudflare") {
		return true
	}
	return resp.Header.Get("Cf-Ray") != ""
}

func setCleanupDone(status string) {
	bookmarkCleanup.mu.Lock()
	bookmarkCleanup.Running = false
	bookmarkCleanup.Status = status
	bookmarkCleanup.LastResult = status
	bookmarkCleanup.EndTime = time.Now().Format("2006-01-02 15:04:05")
	startTime := bookmarkCleanup.StartTime
	endTime := bookmarkCleanup.EndTime
	bookmarkCleanup.mu.Unlock()
	persistCleanupState(status, startTime, endTime)
}

func persistCleanupState(lastResult, startTime, endTime string) {
	if err := models.BatchUpdateSettings(map[string]string{
		"cleanup_last_result": lastResult,
		"cleanup_start_time":  startTime,
		"cleanup_end_time":    endTime,
	}); err != nil {
		log.Printf("persistCleanupState: %v", err)
	}
}

func loadCleanupStateFromDB() {
	bookmarkCleanup.mu.Lock()
	defer bookmarkCleanup.mu.Unlock()
	if bookmarkCleanup.LastResult != "" {
		return
	}
	bookmarkCleanup.LastResult = models.GetSetting("cleanup_last_result")
	bookmarkCleanup.StartTime = models.GetSetting("cleanup_start_time")
	bookmarkCleanup.EndTime = models.GetSetting("cleanup_end_time")
}
