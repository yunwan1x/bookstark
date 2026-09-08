package controllers

import (
	"bytes"
	"database/sql"
	"errors"
	"io"
	"net/http"
	"net/url"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
	"bookstark/services"
)

type assetWebDAVServerRequest struct {
	Name         string `json:"name"`
	URL          string `json:"url"`
	RootPath     string `json:"root_path"`
	CredentialID int64  `json:"credential_id"`
	Status       string `json:"status"`
}

var assetWebDAVManager = services.AssetWebDAVManager{Timeout: 10 * time.Second}

func AssetWebDAVFilesPage(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		c.String(http.StatusBadRequest, "invalid WebDAV server ID")
		return
	}
	data := commonData(c, "assets")
	data["AssetPageMode"] = "webdav-files"
	data["DockerHostID"] = ""
	data["FilesHostID"] = ""
	data["WebDAVServerID"] = strconv.FormatInt(id, 10)
	c.HTML(http.StatusOK, "admin_assets.html", data)
}

func ListAssetWebDAVServers(c *gin.Context) {
	servers, err := models.ListAssetWebDAVServers(models.AssetWebDAVServerFilter{
		Query:  strings.TrimSpace(c.Query("q")),
		Status: strings.TrimSpace(c.Query("status")),
	})
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询 WebDAV 连接失败")
		return
	}
	query := strings.ToLower(strings.TrimSpace(c.Query("q")))
	result := make([]any, 0, len(servers)+1)
	if query == "" || strings.Contains("bookstark 内置 webdav", query) {
		result = append(result, gin.H{
			"id": "local", "name": "BookStark 内置 WebDAV", "url": absoluteRequestURL(c, "/dav"),
			"root_path": "/", "credential_name": "独立应用密码", "username": middleware.GetAccount(c),
			"status": models.AssetStatusOnline, "built_in": true,
		})
	}
	for _, server := range servers {
		result = append(result, server)
	}
	apiSuccess(c, result)
}

func CreateAssetWebDAVServer(c *gin.Context) {
	var req assetWebDAVServerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	normalizeAssetWebDAVRequest(&req)
	if err := validateAssetWebDAVRequest(req); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	if _, err := resolveAssetWebDAVCredential(req.CredentialID); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	id, err := models.CreateAssetWebDAVServer(&models.AssetWebDAVServer{
		Name:         req.Name,
		URL:          req.URL,
		RootPath:     req.RootPath,
		CredentialID: req.CredentialID,
		Status:       models.AssetStatusUnknown,
		CreatedBy:    middleware.GetMemberID(c),
	})
	if err != nil {
		apiError(c, http.StatusInternalServerError, "创建 WebDAV 连接失败")
		return
	}
	server, err := models.GetAssetWebDAVServer(id)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 WebDAV 连接失败")
		return
	}
	apiSuccess(c, server)
}

func UpdateAssetWebDAVServer(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的 WebDAV 连接 ID")
		return
	}
	existing, err := models.GetAssetWebDAVServer(id)
	if err == sql.ErrNoRows {
		apiError(c, http.StatusNotFound, "WebDAV 连接不存在")
		return
	}
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 WebDAV 连接失败")
		return
	}
	var req assetWebDAVServerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	normalizeAssetWebDAVRequest(&req)
	if err := validateAssetWebDAVRequest(req); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	if _, err := resolveAssetWebDAVCredential(req.CredentialID); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	existing.Name = req.Name
	existing.URL = req.URL
	existing.RootPath = req.RootPath
	existing.CredentialID = req.CredentialID
	if err := models.UpdateAssetWebDAVServer(existing); err != nil {
		apiError(c, http.StatusInternalServerError, "更新 WebDAV 连接失败")
		return
	}
	updated, err := models.GetAssetWebDAVServer(id)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 WebDAV 连接失败")
		return
	}
	apiSuccess(c, updated)
}

func DeleteAssetWebDAVServer(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的 WebDAV 连接 ID")
		return
	}
	if err := models.DeleteAssetWebDAVServer(id); err != nil {
		apiError(c, http.StatusInternalServerError, "删除 WebDAV 连接失败")
		return
	}
	apiSuccessMsg(c, "删除成功")
}

func TestAssetWebDAVServer(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	status := models.AssetStatusOnline
	message := "连接成功"
	if err := assetWebDAVManager.Test(server, credential); err != nil {
		status = models.AssetStatusOffline
		message = err.Error()
	}
	checkedAt := time.Now()
	_ = models.UpdateAssetWebDAVServerStatus(server.ServerID, status, checkedAt)
	apiSuccess(c, gin.H{"status": status, "message": message, "checked_at": checkedAt})
}

func ListAssetWebDAVFiles(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	entries, err := assetWebDAVManager.List(server, credential, strings.TrimSpace(c.Query("path")))
	if err != nil {
		apiError(c, http.StatusBadGateway, "读取 WebDAV 目录失败: "+err.Error())
		return
	}
	items, truncated := limitAssetFileEntries(entries, assetFileListLimit)
	apiSuccess(c, assetFileListResponse{
		Items:     items,
		Limit:     assetFileListLimit,
		Truncated: truncated,
	})
}

func DownloadAssetWebDAVFile(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	remotePath := strings.TrimSpace(c.Query("path"))
	if remotePath == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	c.Header("Content-Disposition", `attachment; filename="`+downloadFileName(remotePath)+`"`)
	c.Header("Content-Type", "application/octet-stream")
	if err := assetWebDAVManager.Download(server, credential, remotePath, c.Writer); err != nil {
		apiError(c, http.StatusBadGateway, "下载 WebDAV 文件失败: "+err.Error())
		return
	}
}

func ReadAssetWebDAVFileContent(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	remotePath := strings.TrimSpace(c.Query("path"))
	if remotePath == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if isKnownBinaryFile(remotePath) {
		apiError(c, http.StatusUnsupportedMediaType, "该文件不是文本文件，无法在线预览")
		return
	}
	var buf bytes.Buffer
	writer := &limitedBufferWriter{buf: &buf, limit: assetEditableFileMaxBytes}
	if err := assetWebDAVManager.Download(server, credential, remotePath, writer); err != nil {
		if errors.Is(err, errAssetFileTooLarge) {
			apiError(c, http.StatusRequestEntityTooLarge, "文件过大，无法在线编辑")
			return
		}
		apiError(c, http.StatusBadGateway, "读取 WebDAV 文件失败: "+err.Error())
		return
	}
	if !isTextContent(buf.Bytes()) {
		apiError(c, http.StatusUnsupportedMediaType, "该文件不是文本文件，无法在线预览")
		return
	}
	apiSuccess(c, gin.H{"path": remotePath, "content": buf.String()})
}

func SaveAssetWebDAVFileContent(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	var req assetFileSaveRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Path) == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if err := assetWebDAVManager.Upload(server, credential, strings.TrimSpace(req.Path), strings.NewReader(req.Content)); err != nil {
		if err == io.EOF {
			apiError(c, http.StatusBadGateway, "保存 WebDAV 文件失败")
			return
		}
		apiError(c, http.StatusBadGateway, "保存 WebDAV 文件失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func UploadAssetWebDAVFile(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	dir := strings.TrimSpace(c.Query("path"))
	if dir == "" {
		dir = "."
	}
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		apiError(c, http.StatusBadRequest, "上传文件不能为空")
		return
	}
	defer file.Close()
	remotePath := path.Join(dir, header.Filename)
	if dir == "." || dir == "/" {
		remotePath = header.Filename
	}
	if err := assetWebDAVManager.Upload(server, credential, remotePath, file); err != nil {
		apiError(c, http.StatusBadGateway, "上传 WebDAV 文件失败: "+err.Error())
		return
	}
	apiSuccess(c, gin.H{"path": remotePath})
}

func MkdirAssetWebDAVFile(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	var req assetFilePathRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Path) == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if err := assetWebDAVManager.Mkdir(server, credential, strings.TrimSpace(req.Path)); err != nil {
		apiError(c, http.StatusBadGateway, "创建 WebDAV 目录失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func RenameAssetWebDAVFile(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	var req assetFileRenameRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.OldPath) == "" || strings.TrimSpace(req.NewPath) == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if err := assetWebDAVManager.Rename(server, credential, strings.TrimSpace(req.OldPath), strings.TrimSpace(req.NewPath)); err != nil {
		apiError(c, http.StatusBadGateway, "重命名 WebDAV 文件失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func CopyAssetWebDAVFile(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	var req assetFileCopyRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.SourcePath) == "" || strings.TrimSpace(req.TargetPath) == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if err := assetWebDAVManager.Copy(server, credential, strings.TrimSpace(req.SourcePath), strings.TrimSpace(req.TargetPath)); err != nil {
		apiError(c, http.StatusBadGateway, "复制 WebDAV 文件失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func DeleteAssetWebDAVFile(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	remotePath := strings.TrimSpace(c.Query("path"))
	if remotePath == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	recursive := c.Query("recursive") == "true" || c.Query("recursive") == "1"
	if err := assetWebDAVManager.Remove(server, credential, remotePath, recursive); err != nil {
		apiError(c, http.StatusBadGateway, "删除 WebDAV 文件失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func loadAssetWebDAVServer(c *gin.Context) (*models.AssetWebDAVServer, string, bool) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的 WebDAV 连接 ID")
		return nil, "", false
	}
	server, err := models.GetAssetWebDAVServer(id)
	if err == sql.ErrNoRows {
		apiError(c, http.StatusNotFound, "WebDAV 连接不存在")
		return nil, "", false
	}
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 WebDAV 连接失败")
		return nil, "", false
	}
	cred, err := resolveAssetWebDAVCredential(server.CredentialID)
	if err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return nil, "", false
	}
	server.Username = cred.Username
	credential, err := decryptAssetCredential(cred.CredentialCipher)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "解密凭据失败")
		return nil, "", false
	}
	return server, credential, true
}

func resolveAssetWebDAVCredential(id int64) (*models.AssetCredential, error) {
	if id <= 0 {
		return nil, errors.New("凭据不能为空")
	}
	cred, err := models.GetAssetCredential(id)
	if err == sql.ErrNoRows {
		return nil, errors.New("凭据不存在")
	}
	if err != nil {
		return nil, err
	}
	if cred.AuthType != models.AssetAuthPassword {
		return nil, errors.New("WebDAV 仅支持密码凭据")
	}
	return cred, nil
}

func normalizeAssetWebDAVRequest(req *assetWebDAVServerRequest) {
	req.Name = strings.TrimSpace(req.Name)
	req.URL = strings.TrimSpace(req.URL)
	req.RootPath = strings.TrimSpace(req.RootPath)
	if req.RootPath == "" || req.RootPath == "." {
		req.RootPath = "/"
	}
	if !strings.HasPrefix(req.RootPath, "/") {
		req.RootPath = "/" + req.RootPath
	}
	req.RootPath = path.Clean(req.RootPath)
	if req.RootPath == "." {
		req.RootPath = "/"
	}
}

func validateAssetWebDAVRequest(req assetWebDAVServerRequest) error {
	if req.Name == "" {
		return errors.New("名称不能为空")
	}
	if len(req.Name) > 100 {
		return errors.New("名称不能超过 100 个字符")
	}
	if req.URL == "" {
		return errors.New("WebDAV URL 不能为空")
	}
	parsed, err := url.Parse(req.URL)
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return errors.New("WebDAV URL 必须是有效的 http 或 https 地址")
	}
	if req.CredentialID <= 0 {
		return errors.New("凭据不能为空")
	}
	return nil
}
