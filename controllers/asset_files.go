package controllers

import (
	"bytes"
	"database/sql"
	"errors"
	"io"
	"net/http"
	"path"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"

	"bookstark/middleware"
	"bookstark/models"
	"bookstark/services"
)

type assetFilePathRequest struct {
	Path string `json:"path"`
}

type assetFileRenameRequest struct {
	OldPath string `json:"old_path"`
	NewPath string `json:"new_path"`
}

type assetFileCopyRequest struct {
	SourcePath string `json:"source_path"`
	TargetPath string `json:"target_path"`
}

type assetFileChmodRequest struct {
	Path string `json:"path"`
	Mode string `json:"mode"`
}

type assetFileSaveRequest struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

type assetFileListResponse struct {
	Items     []services.AssetFileEntry `json:"items"`
	Limit     int                       `json:"limit"`
	Truncated bool                      `json:"truncated"`
}

var assetFileManager = services.AssetFileManager{Timeout: 10 * time.Second}

const assetEditableFileMaxBytes = 2 * 1024 * 1024
const assetFileListLimit = 1000

var errAssetFileTooLarge = errors.New("asset file content is too large")

func AssetFilesHostPage(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		c.String(http.StatusBadRequest, "invalid SSH host ID")
		return
	}
	data := commonData(c, "assets")
	data["AssetPageMode"] = "files-host"
	data["DockerHostID"] = ""
	data["FilesHostID"] = strconv.FormatInt(id, 10)
	data["WebDAVServerID"] = ""
	c.HTML(http.StatusOK, "admin_assets.html", data)
}

func ListAssetFiles(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
	if !ok {
		return
	}
	entries, err := assetFileManager.List(host, credential, strings.TrimSpace(c.Query("path")))
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取远程目录失败: "+err.Error())
		return
	}
	items, truncated := limitAssetFileEntries(entries, assetFileListLimit)
	apiSuccess(c, assetFileListResponse{
		Items:     items,
		Limit:     assetFileListLimit,
		Truncated: truncated,
	})
}

func limitAssetFileEntries(entries []services.AssetFileEntry, limit int) ([]services.AssetFileEntry, bool) {
	if limit <= 0 || len(entries) <= limit {
		return entries, false
	}
	return entries[:limit], true
}

func DownloadAssetFile(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
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
	if err := assetFileManager.Download(host, credential, remotePath, c.Writer); err != nil {
		apiError(c, http.StatusInternalServerError, "下载远程文件失败: "+err.Error())
		return
	}
}

func ReadAssetFileContent(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
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
	if err := assetFileManager.Download(host, credential, remotePath, writer); err != nil {
		if errors.Is(err, errAssetFileTooLarge) {
			apiError(c, http.StatusRequestEntityTooLarge, "文件过大，无法在线编辑")
			return
		}
		apiError(c, http.StatusInternalServerError, "读取远程文件失败: "+err.Error())
		return
	}
	if !isTextContent(buf.Bytes()) {
		apiError(c, http.StatusUnsupportedMediaType, "该文件不是文本文件，无法在线预览")
		return
	}
	apiSuccess(c, gin.H{"path": remotePath, "content": buf.String()})
}

func SaveAssetFileContent(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
	if !ok {
		return
	}
	var req assetFileSaveRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Path) == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if err := assetFileManager.Upload(host, credential, strings.TrimSpace(req.Path), strings.NewReader(req.Content)); err != nil {
		if err == io.EOF {
			apiError(c, http.StatusInternalServerError, "保存远程文件失败")
			return
		}
		apiError(c, http.StatusInternalServerError, "保存远程文件失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func UploadAssetFile(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
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
	if dir == "." {
		remotePath = header.Filename
	}
	if err := assetFileManager.Upload(host, credential, remotePath, file); err != nil {
		apiError(c, http.StatusInternalServerError, "上传远程文件失败: "+err.Error())
		return
	}
	apiSuccess(c, gin.H{"path": remotePath})
}

func MkdirAssetFile(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
	if !ok {
		return
	}
	var req assetFilePathRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Path) == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if err := assetFileManager.Mkdir(host, credential, strings.TrimSpace(req.Path)); err != nil {
		apiError(c, http.StatusInternalServerError, "创建远程目录失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func RenameAssetFile(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
	if !ok {
		return
	}
	var req assetFileRenameRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.OldPath) == "" || strings.TrimSpace(req.NewPath) == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if err := assetFileManager.Rename(host, credential, strings.TrimSpace(req.OldPath), strings.TrimSpace(req.NewPath)); err != nil {
		apiError(c, http.StatusInternalServerError, "重命名远程文件失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func CopyAssetFile(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
	if !ok {
		return
	}
	var req assetFileCopyRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.SourcePath) == "" || strings.TrimSpace(req.TargetPath) == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if err := assetFileManager.Copy(host, credential, strings.TrimSpace(req.SourcePath), strings.TrimSpace(req.TargetPath)); err != nil {
		apiError(c, http.StatusInternalServerError, "复制远程文件失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func ChmodAssetFile(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
	if !ok {
		return
	}
	var req assetFileChmodRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Path) == "" || strings.TrimSpace(req.Mode) == "" {
		apiError(c, http.StatusBadRequest, "路径和权限不能为空")
		return
	}
	if err := assetFileManager.Chmod(host, credential, strings.TrimSpace(req.Path), strings.TrimSpace(req.Mode)); err != nil {
		apiError(c, http.StatusInternalServerError, "修改远程权限失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func DeleteAssetFile(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
	if !ok {
		return
	}
	remotePath := strings.TrimSpace(c.Query("path"))
	if remotePath == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	recursive := c.Query("recursive") == "true" || c.Query("recursive") == "1"
	if err := assetFileManager.Remove(host, credential, remotePath, recursive); err != nil {
		apiError(c, http.StatusInternalServerError, "删除远程文件失败: "+err.Error())
		return
	}
	apiSuccessMsg(c, "ok")
}

func loadAssetFileHost(c *gin.Context) (*models.AssetSSHHost, string, bool) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的 SSH 主机 ID")
		return nil, "", false
	}
	host, err := models.GetAssetSSHHost(id)
	if err == sql.ErrNoRows {
		apiError(c, http.StatusNotFound, "SSH 主机不存在")
		return nil, "", false
	}
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 SSH 主机失败")
		return nil, "", false
	}
	credential, err := decryptAssetCredential(host.CredentialCipher)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "解密凭据失败")
		return nil, "", false
	}
	return host, credential, true
}

func downloadFileName(remotePath string) string {
	name := path.Base(remotePath)
	if name == "." || name == "/" || name == "" {
		return "download"
	}
	return strings.ReplaceAll(name, `"`, "")
}

type limitedBufferWriter struct {
	buf   *bytes.Buffer
	limit int
}

func (w *limitedBufferWriter) Write(p []byte) (int, error) {
	if w.buf.Len()+len(p) > w.limit {
		return 0, errAssetFileTooLarge
	}
	return w.buf.Write(p)
}

func isKnownBinaryFile(remotePath string) bool {
	ext := strings.ToLower(path.Ext(remotePath))
	if ext == "" {
		return false
	}
	binaryExts := map[string]bool{
		".7z": true, ".avi": true, ".bin": true, ".bmp": true, ".class": true, ".dll": true,
		".doc": true, ".docx": true, ".dylib": true, ".eot": true, ".exe": true, ".gif": true,
		".gz": true, ".ico": true, ".jar": true, ".jpeg": true, ".jpg": true, ".mov": true,
		".mp3": true, ".mp4": true, ".otf": true, ".pdf": true, ".png": true, ".ppt": true,
		".pptx": true, ".rar": true, ".so": true, ".sqlite": true, ".ttf": true, ".webm": true,
		".webp": true, ".woff": true, ".woff2": true, ".xls": true, ".xlsx": true, ".zip": true,
	}
	return binaryExts[ext]
}

func isTextContent(data []byte) bool {
	if len(data) == 0 {
		return true
	}
	if bytes.IndexByte(data, 0) >= 0 {
		return false
	}
	if !utf8.Valid(data) {
		return false
	}
	control := 0
	for _, b := range data {
		if b < 0x20 && b != '\n' && b != '\r' && b != '\t' && b != '\f' {
			control++
		}
	}
	return control*100/len(data) < 5
}
