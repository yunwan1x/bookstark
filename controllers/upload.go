package controllers

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"image"
	"image/gif"
	"image/jpeg"
	"image/png"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"bookstark/middleware"
	"bookstark/models"

	"github.com/deepteams/webp"
	"golang.org/x/image/draw"
	xwebp "golang.org/x/image/webp"

	"github.com/gin-gonic/gin"
)

var uploadSem = make(chan struct{}, 5) // max 5 concurrent uploads

// ServeUploadFile serves uploaded files (public, no auth required)
func ServeUploadFile(c *gin.Context) {
	fp := c.Param("filepath")
	if strings.Contains(fp, "..") {
		apiError(c, http.StatusForbidden, "非法路径")
		return
	}

	fullPath := filepath.Join(models.UploadBaseDir, filepath.Clean(fp))
	absPath, err := filepath.Abs(fullPath)
	if err != nil {
		apiError(c, http.StatusForbidden, "非法路径")
		return
	}
	absBase, _ := filepath.Abs(models.UploadBaseDir)
	if !strings.HasPrefix(absPath, absBase+string(filepath.Separator)) && absPath != absBase {
		apiError(c, http.StatusForbidden, "非法路径")
		return
	}
	if _, err := os.Stat(absPath); err != nil {
		c.Status(http.StatusNotFound)
		return
	}

	c.Header("Cache-Control", "public, max-age=31536000")

	if strings.HasSuffix(strings.ToLower(fp), ".svg") {
		c.Header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'")
	}

	c.File(absPath)
}

// UploadImage handles POST /api/uploads
func UploadImage(c *gin.Context) {
	memberID := middleware.GetMemberID(c)
	if memberID == 0 {
		apiError(c, http.StatusUnauthorized, "未登录")
		return
	}

	maxSize := models.GetUploadMaxSize()

	// Check Content-Length header
	if c.Request.ContentLength > maxSize {
		apiError(c, http.StatusBadRequest, "文件大小超过限制")
		return
	}

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		apiError(c, http.StatusBadRequest, "请上传文件")
		return
	}
	defer file.Close()
	originalName := header.Filename

	// Read file with limit
	limited := io.LimitReader(file, maxSize+1)
	buf, err := io.ReadAll(limited)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取文件失败")
		return
	}
	if int64(len(buf)) > maxSize {
		apiError(c, http.StatusBadRequest, "文件大小超过限制")
		return
	}

	// Detect MIME type
	detected := http.DetectContentType(buf[:min(512, len(buf))])
	// http.DetectContentType cannot detect SVG; fallback to content sniffing
	if strings.HasPrefix(detected, "text/plain") || strings.HasPrefix(detected, "text/xml") || strings.HasPrefix(detected, "application/xml") {
		trimmed := strings.TrimSpace(string(buf[:min(1024, len(buf))]))
		if strings.HasPrefix(trimmed, "<svg") || strings.Contains(trimmed, "<svg") {
			detected = "image/svg+xml"
		}
	}
	if !models.IsAllowedMIMEType(detected) {
		apiError(c, http.StatusBadRequest, "不支持的文件类型: "+detected)
		return
	}

	// Compute file hash for dedup
	fileHash := sha256.Sum256(buf)
	hashStr := hex.EncodeToString(fileHash[:])

	// Check for duplicate
	if existing, err := models.GetUploadByHash(hashStr); err == nil && existing != nil {
		urlPrefix := "/upload-files/"
		result := gin.H{
			"id":        existing.UploadID,
			"url":       urlPrefix + existing.StoragePath,
			"thumb_url": "",
			"file_name": existing.FileName,
			"width":     existing.Width,
			"height":    existing.Height,
			"file_size": existing.FileSize,
		}
		if existing.ThumbPath != "" {
			result["thumb_url"] = urlPrefix + existing.ThumbPath
		}
		apiSuccess(c, result)
		return
	}

	// Validate category
	category := c.DefaultPostForm("category", "editor")
	if forcedCategory, ok := c.Get("uploadCategory"); ok {
		if value, valid := forcedCategory.(string); valid && value != "" {
			category = value
		}
	}
	if strings.Contains(category, "..") || strings.Contains(category, "/") || strings.Contains(category, "\\") {
		apiError(c, http.StatusBadRequest, "非法分类名称")
		return
	}
	if !models.IsAllowedCategory(category) {
		apiError(c, http.StatusBadRequest, "不支持的上传分类")
		return
	}

	// Acquire semaphore
	uploadSem <- struct{}{}
	defer func() { <-uploadSem }()

	// Determine file extension and processing strategy
	var ext string
	var storeAsIs bool // true for SVG and animated GIF
	var imgWidth, imgHeight int
	var storedSize int64 // actual file size on disk

	switch detected {
	case "image/svg+xml":
		ext = ".svg"
		storeAsIs = true
	case "image/gif":
		if isAnimatedGIF(buf) {
			ext = ".gif"
			storeAsIs = true
		} else {
			ext = ".webp"
			storeAsIs = false
		}
	default:
		ext = ".webp"
		storeAsIs = false
	}

	// Generate filename and path
	now := time.Now()
	filename := fmt.Sprintf("%d-%s", now.UnixMilli(), randomHex(3))
	relPath := uploadFilePath(category, now.Format("2006/01/02"), filename+ext)

	// Ensure directory exists
	fullDir := filepath.Dir(filepath.Join(models.UploadBaseDir, relPath))
	if err := os.MkdirAll(fullDir, 0755); err != nil {
		log.Printf("UploadImage: MkdirAll failed: %v", err)
		apiError(c, http.StatusInternalServerError, "创建目录失败")
		return
	}

	fullPath := filepath.Join(models.UploadBaseDir, relPath)
	var thumbRelPath string
	var thumbSize int64

	if storeAsIs {
		// Write buffer directly (SVG or animated GIF)
		if err := atomicWriteFile(fullPath, buf); err != nil {
			log.Printf("UploadImage: atomicWriteFile failed: %v", err)
			apiError(c, http.StatusInternalServerError, "写入文件失败")
			return
		}
		storedSize = int64(len(buf))

		// For GIF, try to get dimensions
		if detected == "image/gif" {
			if cfg, err := gif.DecodeConfig(bytes.NewReader(buf)); err == nil {
				imgWidth = cfg.Width
				imgHeight = cfg.Height
			}
		}
	} else {
		// Decode image
		img, err := decodeImage(buf)
		if err != nil {
			apiError(c, http.StatusBadRequest, "无法解码图片: "+err.Error())
			return
		}

		bounds := img.Bounds()
		imgWidth = bounds.Dx()
		imgHeight = bounds.Dy()

		// Resize if needed
		maxWidth := models.GetUploadMaxWidth()
		if imgWidth > maxWidth {
			img = resizeImage(img, maxWidth, 0)
			bounds = img.Bounds()
			imgWidth = bounds.Dx()
			imgHeight = bounds.Dy()
		}

		// Encode to WebP (quality 80)
		var webpBuf bytes.Buffer
		if err := webp.Encode(&webpBuf, img, &webp.Options{Quality: 80, Method: 6, Pass: 5}); err != nil {
			log.Printf("UploadImage: webp encode failed: %v", err)
			apiError(c, http.StatusInternalServerError, "编码图片失败")
			return
		}

		if err := atomicWriteFile(fullPath, webpBuf.Bytes()); err != nil {
			log.Printf("UploadImage: atomicWriteFile failed: %v", err)
			apiError(c, http.StatusInternalServerError, "写入文件失败")
			return
		}
		storedSize = int64(webpBuf.Len())

		// Generate thumbnail
		thumbWidth := models.GetUploadThumbWidth()
		if imgWidth > thumbWidth {
			thumbImg := resizeImage(img, thumbWidth, 0)
			var thumbBuf bytes.Buffer
			if err := webp.Encode(&thumbBuf, thumbImg, &webp.Options{Quality: 70, Method: 6, Pass: 5}); err == nil {
				thumbFilename := "thumb_" + filename + ext
				thumbRelPath = uploadFilePath(category, now.Format("2006/01/02"), thumbFilename)
				thumbFullPath := filepath.Join(models.UploadBaseDir, thumbRelPath)
				if err := atomicWriteFile(thumbFullPath, thumbBuf.Bytes()); err != nil {
					log.Printf("UploadImage: atomicWriteFile thumb failed: %v", err)
					thumbRelPath = "" // non-fatal
				} else {
					thumbSize = int64(thumbBuf.Len())
				}
			}
		}
	}

	// Insert into database
	upload := &models.Upload{
		FileName:    originalName,
		StoragePath: relPath,
		FileHash:    hashStr,
		ThumbPath:   thumbRelPath,
		Category:    category,
		MimeType:    detected,
		FileSize:    storedSize,
		ThumbSize:   thumbSize,
		Width:       imgWidth,
		Height:      imgHeight,
		MemberID:    memberID,
		CreateTime:  now,
	}

	id, err := models.InsertUpload(upload)
	if err != nil {
		log.Printf("UploadImage: InsertUpload failed: %v", err)
		// Clean up files
		os.Remove(fullPath)
		if thumbRelPath != "" {
			os.Remove(filepath.Join(models.UploadBaseDir, thumbRelPath))
		}
		apiError(c, http.StatusInternalServerError, "保存上传记录失败")
		return
	}

	urlPrefix := "/upload-files/"
	result := gin.H{
		"id":        id,
		"url":       urlPrefix + relPath,
		"thumb_url": "",
		"file_name": originalName,
		"width":     imgWidth,
		"height":    imgHeight,
		"file_size": storedSize,
	}
	if thumbRelPath != "" {
		result["thumb_url"] = urlPrefix + thumbRelPath
	}

	apiSuccess(c, result)
}

// GetUploadByHash handles GET /api/uploads/by-hash/:hash
func GetUploadByHash(c *gin.Context) {
	hash := c.Param("hash")
	if hash == "" || len(hash) != 64 {
		apiError(c, http.StatusBadRequest, "无效的哈希值")
		return
	}
	if _, err := hex.DecodeString(hash); err != nil {
		apiError(c, http.StatusBadRequest, "无效的哈希值")
		return
	}

	existing, err := models.GetUploadByHash(hash)
	if err != nil || existing == nil {
		apiError(c, http.StatusNotFound, "未找到")
		return
	}

	urlPrefix := "/upload-files/"
	result := gin.H{
		"id":        existing.UploadID,
		"url":       urlPrefix + existing.StoragePath,
		"thumb_url": "",
		"file_name": existing.FileName,
		"width":     existing.Width,
		"height":    existing.Height,
		"file_size": existing.FileSize,
	}
	if existing.ThumbPath != "" {
		result["thumb_url"] = urlPrefix + existing.ThumbPath
	}
	apiSuccess(c, result)
}

// ListUploads handles GET /api/uploads
func ListUploads(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	pageSize := getPageSize(c, "page_size_uploads", "20")
	keyword := c.Query("keyword")
	category := c.Query("category")

	uploads, total, err := models.ListUploadsPaged(page, pageSize, keyword, category)
	if err != nil {
		log.Printf("ListUploads: %v", err)
		apiError(c, http.StatusInternalServerError, "获取上传列表失败")
		return
	}

	_, totalSize, _ := models.GetUploadStats()

	urlPrefix := "/upload-files/"
	type uploadItem struct {
		ID         int64  `json:"id"`
		FileName   string `json:"file_name"`
		URL        string `json:"url"`
		ThumbURL   string `json:"thumb_url"`
		Category   string `json:"category"`
		MimeType   string `json:"mime_type"`
		FileSize   int64  `json:"file_size"`
		Width      int    `json:"width"`
		Height     int    `json:"height"`
		CreateTime string `json:"create_time"`
	}

	list := make([]uploadItem, 0, len(uploads))
	for _, u := range uploads {
		item := uploadItem{
			ID:         u.UploadID,
			FileName:   u.FileName,
			URL:        urlPrefix + u.StoragePath,
			ThumbURL:   "",
			Category:   u.Category,
			MimeType:   u.MimeType,
			FileSize:   u.FileSize,
			Width:      u.Width,
			Height:     u.Height,
			CreateTime: u.CreateTime.Format("2006-01-02 15:04"),
		}
		if u.ThumbPath != "" {
			item.ThumbURL = urlPrefix + u.ThumbPath
		}
		list = append(list, item)
	}

	totalPages := calcTotalPages(total, pageSize)
	c.JSON(http.StatusOK, gin.H{
		"code":        0,
		"data":        list,
		"total":       total,
		"total_size":  totalSize,
		"page":        page,
		"page_size":   pageSize,
		"total_pages": totalPages,
	})
}

// DeleteUpload handles DELETE /api/uploads/:id
func DeleteUpload(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效ID")
		return
	}

	upload, err := models.GetUploadByID(id)
	if err != nil || upload == nil {
		apiError(c, http.StatusNotFound, "文件不存在")
		return
	}

	// Check permission: owner or admin
	if !checkOwnership(c, upload.MemberID) {
		forbidden(c)
		return
	}

	// Delete DB record
	if err := models.DeleteUpload(id); err != nil {
		log.Printf("DeleteUpload: DeleteUpload failed for id %d: %v", id, err)
		apiError(c, http.StatusInternalServerError, "删除失败")
		return
	}

	// Delete original file
	originalPath := filepath.Join(models.UploadBaseDir, upload.StoragePath)
	if err := os.Remove(originalPath); err != nil && !os.IsNotExist(err) {
		log.Printf("DeleteUpload: failed to remove file %s: %v", originalPath, err)
	}

	// Delete thumbnail if exists
	if upload.ThumbPath != "" {
		thumbPath := filepath.Join(models.UploadBaseDir, upload.ThumbPath)
		if err := os.Remove(thumbPath); err != nil && !os.IsNotExist(err) {
			log.Printf("DeleteUpload: failed to remove thumb %s: %v", thumbPath, err)
		}
	}

	apiSuccessMsg(c, "已删除")
}

// ImagesPage renders the image management page
func ImagesPage(c *gin.Context) {
	data := commonData(c, "images")
	c.HTML(http.StatusOK, "images.html", data)
}

// --- Helper functions ---

// randomHex generates n random bytes as a hex string
func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		// Fallback to timestamp-based hex
		return fmt.Sprintf("%x", time.Now().UnixNano())[:n*2]
	}
	return hex.EncodeToString(b)
}

// isAnimatedGIF checks if GIF data contains multiple frames
func isAnimatedGIF(data []byte) bool {
	gifImg, err := gif.DecodeAll(bytes.NewReader(data))
	if err != nil {
		return false
	}
	return len(gifImg.Image) > 1
}

// uploadFilePath builds a relative path like editor/2006/01/02/filename.webp
func uploadFilePath(category, datePath, filename string) string {
	return filepath.Join(category, datePath, filename)
}

// atomicWriteFile writes data to a .tmp file then renames to the target path
func atomicWriteFile(path string, data []byte) error {
	tmpPath := path + ".tmp"
	if err := os.WriteFile(tmpPath, data, 0644); err != nil {
		return err
	}
	return os.Rename(tmpPath, path)
}

// decodeImage attempts to decode an image from bytes, trying multiple formats
func decodeImage(data []byte) (image.Image, error) {
	r := bytes.NewReader(data)

	// Try webp first
	if img, err := xwebp.Decode(r); err == nil {
		return img, nil
	}
	r.Reset(data)

	// Try jpeg
	if img, err := jpeg.Decode(r); err == nil {
		return img, nil
	}
	r.Reset(data)

	// Try png
	if img, err := png.Decode(r); err == nil {
		return img, nil
	}
	r.Reset(data)

	// Try gif (first frame)
	if img, err := gif.Decode(r); err == nil {
		return img, nil
	}

	return nil, fmt.Errorf("unsupported image format")
}

// resizeImage resizes an image to the given width maintaining aspect ratio.
// If height is 0, it is calculated from the width.
func resizeImage(src image.Image, maxWidth, maxHeight int) image.Image {
	srcBounds := src.Bounds()
	srcW := srcBounds.Dx()
	srcH := srcBounds.Dy()
	if srcW <= 0 || srcH <= 0 {
		return src
	}

	dstW := srcW
	dstH := srcH

	if maxWidth > 0 && srcW > maxWidth {
		dstW = maxWidth
		dstH = srcH * maxWidth / srcW
	}
	if maxHeight > 0 && dstH > maxHeight {
		dstH = maxHeight
		dstW = dstW * maxHeight / dstH
	}

	if dstW == srcW && dstH == srcH {
		return src
	}

	dst := image.NewRGBA(image.Rect(0, 0, dstW, dstH))
	draw.CatmullRom.Scale(dst, dst.Bounds(), src, srcBounds, draw.Over, nil)
	return dst
}
