package controllers

import (
	"compress/gzip"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"path"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"golang.org/x/net/webdav"

	"bookstark/middleware"
	"bookstark/models"
	"bookstark/services"
)

const (
	davAuthFailureLimit    = 20
	davAuthIPFailureLimit  = 100
	davAuthFailureWindow   = 5 * time.Minute
	davAuthLimiterKeySplit = "\x00"
)

var (
	localDAVHandlers sync.Map
	davAuthLimiter   = &rateLimiter{
		attempts: make(map[string]*attemptInfo),
		maxIPs:   5000,
	}
)

type davFileActionRequest struct {
	Path        string `json:"path"`
	NewPath     string `json:"new_path"`
	Name        string `json:"name"`
	Content     string `json:"content"`
	PublicPath  string `json:"public_path"`
	ContentType string `json:"content_type"`
}

type davDedupRequest struct {
	Path        string   `json:"path"`
	Hash        string   `json:"hash"`
	Size        int64    `json:"size"`
	ContentType string   `json:"content_type"`
	Token       string   `json:"token"`
	ChunkHashes []string `json:"chunk_hashes"`
}

type davAppPasswordRequest struct {
	Password string `json:"password"`
}

type davProofChallenge struct {
	MemberID    int64
	BlobID      int64
	Path        string
	ContentType string
	Indices     []int
	Nonce       []byte
	ExpiresAt   time.Time
}

type davTrackedRequestBody struct {
	io.ReadCloser
	state *services.DAVRequestState
}

func (b *davTrackedRequestBody) Read(buffer []byte) (int, error) {
	n, err := b.ReadCloser.Read(buffer)
	if err != nil && err != io.EOF {
		b.state.Fail(err)
	}
	return n, err
}

var davProofChallenges sync.Map

func WebDAVPage(c *gin.Context) {
	data := commonData(c, "assets")
	c.HTML(http.StatusOK, "webdav.html", data)
}

func LocalDAVProfile(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	if _, err := models.EnsureDAVRoot(memberID); err != nil {
		apiError(c, http.StatusInternalServerError, "初始化 WebDAV 空间失败")
		return
	}
	member, err := models.GetMemberByID(memberID)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取账号失败")
		return
	}
	settings := models.GetWebDAVSettings()
	usage, err := models.GetDAVUsage(memberID, settings.UserQuotaBytes)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取空间用量失败")
		return
	}
	hasPassword, _ := models.HasDAVAppPassword(memberID)
	apiSuccess(c, gin.H{
		"name":             "BookStark 内置 WebDAV",
		"built_in":         true,
		"account":          member.Account,
		"endpoint":         absoluteRequestURL(c, "/dav"),
		"has_app_password": hasPassword,
		"usage":            usage,
		"file_max_bytes":   settings.FileMaxBytes,
		"public_max_bytes": settings.PublicFileMaxBytes,
		"public_base_url":  davPublicBaseURL(c, member.Account),
	})
}

func ResetLocalDAVPassword(c *gin.Context) {
	var (
		req      davAppPasswordRequest
		password string
		err      error
	)
	if c.Request.ContentLength == 0 {
		password, err = models.ResetDAVAppPassword(middleware.GetMemberID(c))
	} else {
		if bindErr := c.ShouldBindJSON(&req); bindErr != nil {
			apiError(c, http.StatusBadRequest, "请输入有效的应用密码")
			return
		}
		password = req.Password
		passwordLength := utf8.RuneCountInString(password)
		if passwordLength < 8 || passwordLength > 64 || len(password) > 72 || strings.TrimSpace(password) == "" {
			apiError(c, http.StatusBadRequest, "应用密码需为 8-64 个字符，且编码后不超过 72 字节")
			return
		}
		err = models.SetDAVAppPassword(middleware.GetMemberID(c), password)
	}
	if err != nil {
		apiError(c, http.StatusInternalServerError, "设置应用密码失败")
		return
	}
	apiSuccess(c, gin.H{"app_password": password})
}

func RevokeLocalDAVPassword(c *gin.Context) {
	if err := models.RevokeDAVAppPassword(middleware.GetMemberID(c)); err != nil {
		apiError(c, http.StatusInternalServerError, "撤销应用密码失败")
		return
	}
	apiSuccessMsg(c, "应用密码已撤销")
}

func BackupLocalDAVDatabase(c *gin.Context) {
	temp, err := os.CreateTemp("", "bookstark-webdav-backup-*.db")
	if err != nil {
		apiError(c, http.StatusInternalServerError, "创建备份失败")
		return
	}
	name := temp.Name()
	_ = temp.Close()
	_ = os.Remove(name)
	defer os.Remove(name)
	if err := models.BackupWebDAVDatabase(name); err != nil {
		apiError(c, http.StatusInternalServerError, "备份 WebDAV 数据库失败")
		return
	}
	c.FileAttachment(name, "bookstark-webdav.db")
}

func ListLocalDAVFiles(c *gin.Context) {
	files, err := models.ListDAVNodes(middleware.GetMemberID(c), c.Query("path"))
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	apiSuccess(c, files)
}

func DownloadLocalDAVFile(c *gin.Context) {
	node, _, reader, err := models.ReadDAVFileContext(c.Request.Context(), middleware.GetMemberID(c), c.Query("path"))
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	defer reader.Close()
	c.Header("Content-Type", node.MIMEType)
	c.Header("ETag", `"`+node.ETag+`"`)
	c.Header("Content-Disposition", "attachment; filename*=UTF-8''"+url.PathEscape(node.Name))
	http.ServeContent(c.Writer, c.Request, node.Name, node.ModifyTime, reader)
}

func PreviewLocalDAVFile(c *gin.Context) {
	node, _, reader, err := models.ReadDAVFileContext(c.Request.Context(), middleware.GetMemberID(c), c.Query("path"))
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	defer reader.Close()
	c.Header("Content-Type", node.MIMEType)
	c.Header("Cache-Control", "private, no-store")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Header("Content-Security-Policy", "default-src 'none'; img-src 'self' data:; media-src 'self'; style-src 'none'; script-src 'none'; sandbox")
	http.ServeContent(c.Writer, c.Request, node.Name, node.ModifyTime, reader)
}

func ReadLocalDAVFile(c *gin.Context) {
	node, _, reader, err := models.ReadDAVFileContext(c.Request.Context(), middleware.GetMemberID(c), c.Query("path"))
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	defer reader.Close()
	settings := models.GetWebDAVSettings()
	if node.Size > settings.FileMaxBytes {
		apiError(c, http.StatusRequestEntityTooLarge, "文件过大")
		return
	}
	content, err := io.ReadAll(reader)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取文件失败")
		return
	}
	apiSuccess(c, gin.H{"path": node.Path, "content": string(content), "etag": node.ETag, "mime_type": node.MIMEType})
}

func SaveLocalDAVFile(c *gin.Context) {
	settings := models.GetWebDAVSettings()
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, settings.FileMaxBytes*2+(1<<20))
	var req davFileActionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "request body too large") {
			localDAVAPIError(c, models.ErrDAVFileTooLarge)
		} else {
			apiError(c, http.StatusBadRequest, "请求参数无效")
		}
		return
	}
	node, deduplicated, err := models.PutDAVFileContext(
		c.Request.Context(),
		middleware.GetMemberID(c), req.Path, req.ContentType,
		strings.NewReader(req.Content), settings.FileMaxBytes, settings.UserQuotaBytes,
	)
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	apiSuccess(c, gin.H{"file": node, "deduplicated": deduplicated})
}

func UploadLocalDAVFile(c *gin.Context) {
	settings := models.GetWebDAVSettings()
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, settings.FileMaxBytes+(1<<20))
	file, err := c.FormFile("file")
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "request body too large") {
			localDAVAPIError(c, models.ErrDAVFileTooLarge)
			return
		}
		apiError(c, http.StatusBadRequest, "请选择文件")
		return
	}
	if file.Size > settings.FileMaxBytes {
		localDAVAPIError(c, models.ErrDAVFileTooLarge)
		return
	}
	if !validDAVEntryName(file.Filename) {
		apiError(c, http.StatusBadRequest, "文件名无效")
		return
	}
	source, err := file.Open()
	if err != nil {
		apiError(c, http.StatusBadRequest, "读取上传文件失败")
		return
	}
	defer source.Close()
	parentPath, err := models.NormalizeDAVPath(c.PostForm("path"))
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	target := path.Join(parentPath, file.Filename)
	node, deduplicated, err := models.PutDAVFileContext(
		c.Request.Context(),
		middleware.GetMemberID(c), target, file.Header.Get("Content-Type"),
		source, settings.FileMaxBytes, settings.UserQuotaBytes,
	)
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	apiSuccess(c, gin.H{"file": node, "deduplicated": deduplicated})
}

func MkdirLocalDAVFile(c *gin.Context) {
	var req davFileActionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	target := req.Path
	if req.Name != "" {
		if !validDAVEntryName(req.Name) {
			apiError(c, http.StatusBadRequest, "目录名称无效")
			return
		}
		parentPath, err := models.NormalizeDAVPath(req.Path)
		if err != nil {
			localDAVAPIError(c, err)
			return
		}
		target = path.Join(parentPath, req.Name)
	}
	node, err := models.CreateDAVDirectory(middleware.GetMemberID(c), target)
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	apiSuccess(c, node)
}

func RenameLocalDAVFile(c *gin.Context) {
	var req davFileActionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	if err := models.RenameDAVNode(middleware.GetMemberID(c), req.Path, req.NewPath); err != nil {
		localDAVAPIError(c, err)
		return
	}
	apiSuccessMsg(c, "已重命名")
}

func CopyLocalDAVFile(c *gin.Context) {
	var req davFileActionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	if err := models.CopyDAVNode(middleware.GetMemberID(c), req.Path, req.NewPath, models.GetWebDAVSettings().UserQuotaBytes); err != nil {
		localDAVAPIError(c, err)
		return
	}
	apiSuccessMsg(c, "已复制")
}

func DeleteLocalDAVFile(c *gin.Context) {
	if err := models.DeleteDAVNode(middleware.GetMemberID(c), c.Query("path"), true); err != nil {
		localDAVAPIError(c, err)
		return
	}
	apiSuccessMsg(c, "已删除")
}

func CheckLocalDAVUpload(c *gin.Context) {
	cleanupDAVProofChallenges()
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 64<<10)
	var req davDedupRequest
	if err := c.ShouldBindJSON(&req); err != nil || !validDAVHash(req.Hash) || req.Size < 0 {
		apiError(c, http.StatusBadRequest, "文件摘要参数无效")
		return
	}
	settings := models.GetWebDAVSettings()
	if req.Size > settings.FileMaxBytes {
		localDAVAPIError(c, models.ErrDAVFileTooLarge)
		return
	}
	blob, err := models.FindDAVBlob(req.Hash, req.Size)
	if errors.Is(err, models.ErrDAVNotFound) {
		apiSuccess(c, gin.H{"action": "upload"})
		return
	}
	if err != nil {
		apiError(c, http.StatusInternalServerError, "检查文件失败")
		return
	}
	memberID := middleware.GetMemberID(c)
	owned, _ := models.MemberReferencesDAVBlob(memberID, blob.BlobID)
	if owned {
		node, err := models.LinkDAVBlob(memberID, req.Path, blob.BlobID, req.ContentType, settings.UserQuotaBytes)
		if err != nil {
			localDAVAPIError(c, err)
			return
		}
		apiSuccess(c, gin.H{"action": "linked", "file": node})
		return
	}
	indices := davProofIndices(blob.ChunkCount)
	if len(indices) == 0 {
		apiSuccess(c, gin.H{"action": "upload"})
		return
	}
	token := randomDAVToken()
	nonce := make([]byte, 24)
	_, _ = rand.Read(nonce)
	davProofChallenges.Store(token, davProofChallenge{
		MemberID: memberID, BlobID: blob.BlobID, Path: req.Path,
		ContentType: req.ContentType, Indices: indices, Nonce: nonce, ExpiresAt: time.Now().Add(5 * time.Minute),
	})
	apiSuccess(c, gin.H{
		"action": "prove", "token": token, "nonce": hex.EncodeToString(nonce),
		"chunk_size": blob.ChunkSize, "chunk_indices": indices,
	})
}

func ProveLocalDAVUpload(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 64<<10)
	var req davDedupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "证明参数无效")
		return
	}
	value, ok := davProofChallenges.LoadAndDelete(req.Token)
	if !ok {
		apiError(c, http.StatusBadRequest, "证明已失效，请重新检查文件")
		return
	}
	challenge := value.(davProofChallenge)
	if challenge.MemberID != middleware.GetMemberID(c) || time.Now().After(challenge.ExpiresAt) || len(req.ChunkHashes) != len(challenge.Indices) {
		apiError(c, http.StatusBadRequest, "文件持有证明无效")
		return
	}
	blob, err := models.FindDAVBlobByID(challenge.BlobID)
	if err != nil {
		apiError(c, http.StatusConflict, "源文件已不存在")
		return
	}
	for i, index := range challenge.Indices {
		if index < 0 || index >= blob.ChunkCount {
			apiError(c, http.StatusForbidden, "文件持有证明不匹配")
			return
		}
		chunk, readErr := models.ReadDAVBlobChunkContext(c.Request.Context(), blob, index)
		if readErr != nil {
			apiError(c, http.StatusInternalServerError, "校验文件失败")
			return
		}
		digestInput := make([]byte, 0, len(challenge.Nonce)+len(chunk))
		digestInput = append(digestInput, challenge.Nonce...)
		digestInput = append(digestInput, chunk...)
		expected := sha256.Sum256(digestInput)
		if !strings.EqualFold(hex.EncodeToString(expected[:]), req.ChunkHashes[i]) {
			apiError(c, http.StatusForbidden, "文件持有证明不匹配")
			return
		}
	}
	node, err := models.LinkDAVBlob(challenge.MemberID, challenge.Path, challenge.BlobID, challenge.ContentType, models.GetWebDAVSettings().UserQuotaBytes)
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	apiSuccess(c, gin.H{"action": "linked", "file": node})
}

func PublishLocalDAVFile(c *gin.Context) {
	var req davFileActionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	memberID := middleware.GetMemberID(c)
	node, err := models.GetDAVNode(memberID, req.Path)
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	if node.Size > models.GetWebDAVSettings().PublicFileMaxBytes {
		apiError(c, http.StatusRequestEntityTooLarge, "文件超过公开静态资源大小上限")
		return
	}
	publicPath := strings.TrimSpace(req.PublicPath)
	if publicPath == "" {
		publicPath = node.Name
	}
	asset, err := models.CreateOrUpdateDAVPublicAsset(memberID, node.NodeID, publicPath)
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	member, _ := models.GetMemberByID(memberID)
	apiSuccess(c, gin.H{"asset": asset, "url": davPublicAssetURL(c, member.Account, asset.PublicPath)})
}

func UnpublishLocalDAVFile(c *gin.Context) {
	node, err := models.GetDAVNode(middleware.GetMemberID(c), c.Query("path"))
	if err != nil {
		localDAVAPIError(c, err)
		return
	}
	if err := models.DeleteDAVPublicAsset(middleware.GetMemberID(c), node.NodeID); err != nil {
		localDAVAPIError(c, err)
		return
	}
	apiSuccessMsg(c, "已取消公开")
}

func ServeDAVPublicAsset(c *gin.Context) {
	member, err := models.GetMemberByAccount(c.Param("account"))
	if err != nil || member.Status != 1 {
		c.Status(http.StatusNotFound)
		return
	}
	node, blob, err := models.ResolveDAVPublicAsset(member.MemberID, c.Param("filepath"))
	if err != nil {
		c.Status(http.StatusNotFound)
		return
	}
	c.Header("Content-Type", node.MIMEType)
	c.Header("ETag", `"`+node.ETag+`"`)
	c.Header("Cache-Control", davPublicAssetCacheControl(c.Param("filepath")))
	c.Header("X-Content-Type-Options", "nosniff")
	canGzip := blob.StoredSize < blob.OriginalSize
	if canGzip {
		c.Header("Vary", "Accept-Encoding")
	}
	if requestETagMatches(c.GetHeader("If-None-Match"), node.ETag) {
		c.Status(http.StatusNotModified)
		return
	}
	rangeRequested := strings.TrimSpace(c.GetHeader("Range")) != ""
	if canGzip && !rangeRequested && acceptsHTTPEncoding(c.GetHeader("Accept-Encoding"), "gzip") {
		c.Header("Content-Encoding", "gzip")
		if c.Request.Method == http.MethodHead {
			c.Status(http.StatusOK)
			return
		}
		reader, err := models.OpenDAVBlobContext(c.Request.Context(), blob)
		if err != nil {
			c.Status(http.StatusInternalServerError)
			return
		}
		defer reader.Close()
		c.Status(http.StatusOK)
		writer := gzip.NewWriter(c.Writer)
		_, copyErr := io.Copy(writer, reader)
		closeErr := writer.Close()
		if copyErr != nil || closeErr != nil {
			return
		}
		return
	}
	reader, err := models.OpenDAVBlobContext(c.Request.Context(), blob)
	if err != nil {
		c.Status(http.StatusInternalServerError)
		return
	}
	defer reader.Close()
	http.ServeContent(c.Writer, c.Request, node.Name, node.ModifyTime, reader)
}

func davPublicAssetCacheControl(publicPath string) string {
	parts := strings.Split(strings.Trim(publicPath, "/"), "/")
	if len(parts) >= 4 &&
		parts[0] == "pptist" &&
		len(parts[1]) == 40 &&
		isHexValue(parts[1]) &&
		parts[2] == "fonts" &&
		strings.EqualFold(path.Ext(parts[len(parts)-1]), ".woff2") {
		return "public, max-age=31536000, immutable"
	}
	return "public, max-age=3600"
}

func isHexValue(value string) bool {
	_, err := hex.DecodeString(value)
	return err == nil
}

func requestETagMatches(header, etag string) bool {
	quoted := `"` + etag + `"`
	for _, candidate := range strings.Split(header, ",") {
		candidate = strings.TrimSpace(candidate)
		if candidate == "*" || candidate == quoted || candidate == "W/"+quoted {
			return true
		}
	}
	return false
}

func HandleLocalWebDAV(c *gin.Context) {
	clientIP := c.ClientIP()
	ipLimitKey := "ip" + davAuthLimiterKeySplit + clientIP
	account, password, ok := c.Request.BasicAuth()
	if !ok {
		if !davAuthLimiter.check(ipLimitKey, davAuthIPFailureLimit, davAuthFailureWindow) {
			davRateLimited(c)
			return
		}
		davUnauthorized(c)
		return
	}
	accountLimitKey := "account" + davAuthLimiterKeySplit + strings.ToLower(strings.TrimSpace(account))
	if !davAuthLimiter.check(accountLimitKey, davAuthFailureLimit, davAuthFailureWindow) {
		davRateLimited(c)
		return
	}
	member, err := models.GetMemberByAccount(account)
	if err != nil || member.Status != 1 || !models.VerifyDAVAppPassword(member.MemberID, password) {
		davUnauthorized(c)
		return
	}
	davAuthLimiter.reset(accountLimitKey)
	if _, err := models.EnsureDAVRoot(member.MemberID); err != nil {
		c.Status(http.StatusInternalServerError)
		return
	}
	settings := models.GetWebDAVSettings()
	if c.Request.Method == http.MethodPut && c.Request.ContentLength > settings.FileMaxBytes {
		c.Status(http.StatusRequestEntityTooLarge)
		return
	}
	state := services.NewDAVRequestState()
	ctx := services.WithDAVMember(c.Request.Context(), member.MemberID)
	ctx = services.WithDAVRequestState(ctx, state)
	if isDAVHeavyMethod(c.Request.Method) {
		var release func()
		ctx, release, err = models.BeginDAVTransfer(ctx)
		if err != nil {
			c.Status(http.StatusServiceUnavailable)
			return
		}
		defer release()
	}
	request := c.Request.WithContext(ctx)
	request.Body = &davTrackedRequestBody{ReadCloser: c.Request.Body, state: state}
	localDAVHandlerForMember(member.MemberID).ServeHTTP(c.Writer, request)
}

func isDAVHeavyMethod(method string) bool {
	switch method {
	case http.MethodGet, http.MethodHead, http.MethodPost, http.MethodPut, "COPY":
		return true
	default:
		return false
	}
}

func davRateLimited(c *gin.Context) {
	c.Header("Retry-After", strconv.FormatInt(int64(davAuthFailureWindow/time.Second), 10))
	c.Status(http.StatusTooManyRequests)
}

func localDAVHandlerForMember(memberID int64) *webdav.Handler {
	if existing, ok := localDAVHandlers.Load(memberID); ok {
		return existing.(*webdav.Handler)
	}
	handler := &webdav.Handler{
		Prefix:     "/dav",
		FileSystem: services.LocalDAVFileSystem{},
		LockSystem: webdav.NewMemLS(),
	}
	actual, _ := localDAVHandlers.LoadOrStore(memberID, handler)
	return actual.(*webdav.Handler)
}

func acceptsHTTPEncoding(header, encoding string) bool {
	encoding = strings.ToLower(strings.TrimSpace(encoding))
	if encoding == "" {
		return false
	}
	var wildcard *bool
	for _, item := range strings.Split(header, ",") {
		parts := strings.Split(item, ";")
		name := strings.ToLower(strings.TrimSpace(parts[0]))
		if name == "" {
			continue
		}
		accepted := true
		for _, parameter := range parts[1:] {
			key, value, found := strings.Cut(parameter, "=")
			if !found || !strings.EqualFold(strings.TrimSpace(key), "q") {
				continue
			}
			quality, err := strconv.ParseFloat(strings.TrimSpace(value), 64)
			if err != nil || quality <= 0 || quality > 1 {
				accepted = false
			}
		}
		if name == encoding {
			return accepted
		}
		if name == "*" {
			value := accepted
			wildcard = &value
		}
	}
	return wildcard != nil && *wildcard
}

func davUnauthorized(c *gin.Context) {
	c.Header("WWW-Authenticate", `Basic realm="BookStark WebDAV", charset="UTF-8"`)
	c.Status(http.StatusUnauthorized)
}

func localDAVAPIError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, models.ErrDAVNotFound):
		apiError(c, http.StatusNotFound, "文件或目录不存在")
	case errors.Is(err, models.ErrDAVAlreadyExists):
		apiError(c, http.StatusConflict, "同名文件或目录已存在")
	case errors.Is(err, models.ErrDAVInvalidPath):
		apiError(c, http.StatusBadRequest, "文件路径无效")
	case errors.Is(err, models.ErrDAVQuotaExceeded):
		apiError(c, http.StatusInsufficientStorage, "WebDAV 空间容量不足")
	case errors.Is(err, models.ErrDAVFileTooLarge):
		apiError(c, http.StatusRequestEntityTooLarge, "文件超过大小上限")
	case errors.Is(err, models.ErrDAVIsDirectory), errors.Is(err, models.ErrDAVNotDirectory):
		apiError(c, http.StatusBadRequest, "文件类型与操作不匹配")
	default:
		apiError(c, http.StatusInternalServerError, "WebDAV 操作失败")
	}
}

func absoluteRequestURL(c *gin.Context, requestPath string) string {
	scheme := "http"
	if c.Request.TLS != nil || strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https") {
		scheme = "https"
	}
	return scheme + "://" + c.Request.Host + requestPath
}

func davPublicBaseURL(c *gin.Context, account string) string {
	settings := models.GetWebDAVSettings()
	if settings.SeparatePublicURL && settings.PublicBaseURL != "" {
		return settings.PublicBaseURL + "/" + url.PathEscape(account)
	}
	return absoluteRequestURL(c, "/dav-public/"+url.PathEscape(account))
}

func davPublicAssetURL(c *gin.Context, account, publicPath string) string {
	parts := strings.Split(publicPath, "/")
	for i := range parts {
		parts[i] = url.PathEscape(parts[i])
	}
	return davPublicBaseURL(c, account) + "/" + strings.Join(parts, "/")
}

func validDAVHash(value string) bool {
	if len(value) != 64 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func validDAVEntryName(value string) bool {
	if value == "" || value == "." || value == ".." || value != path.Base(value) ||
		strings.ContainsAny(value, `/\`) {
		return false
	}
	return strings.IndexFunc(value, func(r rune) bool {
		return r < 0x20 || r == 0x7f
	}) < 0
}

func randomDAVToken() string {
	value := make([]byte, 24)
	_, _ = rand.Read(value)
	return hex.EncodeToString(value)
}

func davProofIndices(count int) []int {
	if count < 2 {
		return nil
	}
	result := []int{0, count - 1}
	if count > 2 {
		random := make([]byte, 2)
		_, _ = rand.Read(random)
		index := int(random[0])<<8 | int(random[1])
		index = 1 + index%(count-2)
		result = append(result, index)
	}
	return result
}

func cleanupDAVProofChallenges() {
	now := time.Now()
	davProofChallenges.Range(func(key, value any) bool {
		if challenge, ok := value.(davProofChallenge); !ok || now.After(challenge.ExpiresAt) {
			davProofChallenges.Delete(key)
		}
		return true
	})
}
