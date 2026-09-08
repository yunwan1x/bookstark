package controllers

import (
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"path"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

type assetHTTPRange struct {
	Start   int64
	End     int64
	Partial bool
}

var errAssetRangeNotSatisfiable = errors.New("asset range not satisfiable")

func PreviewAssetFile(c *gin.Context) {
	host, credential, ok := loadAssetFileHost(c)
	if !ok {
		return
	}
	remotePath := strings.TrimSpace(c.Query("path"))
	if remotePath == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if !isPreviewableAssetMedia(remotePath) {
		apiError(c, http.StatusUnsupportedMediaType, "该文件暂不支持媒体预览")
		return
	}
	handle, err := assetFileManager.OpenReadHandle(host, credential, remotePath)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "打开远程文件失败: "+err.Error())
		return
	}
	defer handle.Close()

	rangeSpec, err := parseAssetHTTPRange(c.GetHeader("Range"), handle.Size)
	if err != nil {
		c.Header("Content-Range", fmt.Sprintf("bytes */%d", handle.Size))
		c.Status(http.StatusRequestedRangeNotSatisfiable)
		return
	}
	if rangeSpec.Start > 0 {
		if _, err := handle.Seek(rangeSpec.Start, io.SeekStart); err != nil {
			apiError(c, http.StatusInternalServerError, "定位远程文件失败: "+err.Error())
			return
		}
	}
	length := rangeSpec.End - rangeSpec.Start + 1
	if handle.Size == 0 {
		length = 0
	}

	writeAssetPreviewHeaders(c, remotePath, assetPreviewContentType(remotePath, ""), handle.Size, rangeSpec)
	c.Status(assetPreviewStatus(rangeSpec))
	if length <= 0 {
		return
	}
	if _, err := io.Copy(c.Writer, io.LimitReader(handle, length)); err != nil {
		return
	}
}

func PreviewAssetWebDAVFile(c *gin.Context) {
	server, credential, ok := loadAssetWebDAVServer(c)
	if !ok {
		return
	}
	remotePath := strings.TrimSpace(c.Query("path"))
	if remotePath == "" {
		apiError(c, http.StatusBadRequest, "路径不能为空")
		return
	}
	if !isPreviewableAssetMedia(remotePath) {
		apiError(c, http.StatusUnsupportedMediaType, "该文件暂不支持媒体预览")
		return
	}
	stream, err := assetWebDAVManager.OpenReadStream(server, credential, remotePath, c.GetHeader("Range"))
	if err != nil {
		apiError(c, http.StatusBadGateway, "打开 WebDAV 文件失败: "+err.Error())
		return
	}
	defer stream.Body.Close()

	contentType := assetPreviewContentType(remotePath, stream.Header.Get("Content-Type"))
	c.Header("Content-Disposition", `inline; filename="`+downloadFileName(remotePath)+`"`)
	c.Header("Content-Type", contentType)
	copyHeaderIfPresent(c, stream.Header, "Accept-Ranges")
	copyHeaderIfPresent(c, stream.Header, "Content-Length")
	copyHeaderIfPresent(c, stream.Header, "Content-Range")
	if stream.Header.Get("Accept-Ranges") == "" {
		c.Header("Accept-Ranges", "bytes")
	}
	status := stream.StatusCode
	if status != http.StatusPartialContent {
		status = http.StatusOK
	}
	c.Status(status)
	_, _ = io.Copy(c.Writer, stream.Body)
}

func writeAssetPreviewHeaders(c *gin.Context, remotePath, contentType string, size int64, rangeSpec assetHTTPRange) {
	c.Header("Content-Disposition", `inline; filename="`+downloadFileName(remotePath)+`"`)
	c.Header("Content-Type", contentType)
	c.Header("Accept-Ranges", "bytes")
	if rangeSpec.Partial {
		c.Header("Content-Range", fmt.Sprintf("bytes %d-%d/%d", rangeSpec.Start, rangeSpec.End, size))
		c.Header("Content-Length", strconv.FormatInt(rangeSpec.End-rangeSpec.Start+1, 10))
		return
	}
	c.Header("Content-Length", strconv.FormatInt(size, 10))
}

func copyHeaderIfPresent(c *gin.Context, h http.Header, name string) {
	if value := h.Get(name); value != "" {
		c.Header(name, value)
	}
}

func assetPreviewStatus(rangeSpec assetHTTPRange) int {
	if rangeSpec.Partial {
		return http.StatusPartialContent
	}
	return http.StatusOK
}

func parseAssetHTTPRange(header string, size int64) (assetHTTPRange, error) {
	full := assetHTTPRange{Start: 0, End: size - 1}
	header = strings.TrimSpace(header)
	if header == "" {
		return full, nil
	}
	if size <= 0 || !strings.HasPrefix(header, "bytes=") || strings.Contains(header, ",") {
		return full, errAssetRangeNotSatisfiable
	}
	spec := strings.TrimSpace(strings.TrimPrefix(header, "bytes="))
	parts := strings.SplitN(spec, "-", 2)
	if len(parts) != 2 {
		return full, errAssetRangeNotSatisfiable
	}
	var start, end int64
	var err error
	if parts[0] == "" {
		suffix, parseErr := strconv.ParseInt(strings.TrimSpace(parts[1]), 10, 64)
		if parseErr != nil || suffix <= 0 {
			return full, errAssetRangeNotSatisfiable
		}
		if suffix > size {
			suffix = size
		}
		start = size - suffix
		end = size - 1
	} else {
		start, err = strconv.ParseInt(strings.TrimSpace(parts[0]), 10, 64)
		if err != nil || start < 0 || start >= size {
			return full, errAssetRangeNotSatisfiable
		}
		if strings.TrimSpace(parts[1]) == "" {
			end = size - 1
		} else {
			end, err = strconv.ParseInt(strings.TrimSpace(parts[1]), 10, 64)
			if err != nil || end < start {
				return full, errAssetRangeNotSatisfiable
			}
			if end >= size {
				end = size - 1
			}
		}
	}
	return assetHTTPRange{Start: start, End: end, Partial: true}, nil
}

func isPreviewableAssetMedia(remotePath string) bool {
	kind := assetPreviewMediaKind(remotePath)
	return kind == "image" || kind == "video"
}

func assetPreviewMediaKind(remotePath string) string {
	contentType := assetPreviewContentType(remotePath, "")
	if strings.HasPrefix(contentType, "image/") {
		return "image"
	}
	if strings.HasPrefix(contentType, "video/") {
		return "video"
	}
	return ""
}

func assetPreviewContentType(remotePath, fallback string) string {
	fallback = strings.TrimSpace(strings.Split(fallback, ";")[0])
	if fallback != "" && fallback != "application/octet-stream" {
		return fallback
	}
	ext := strings.ToLower(path.Ext(remotePath))
	custom := map[string]string{
		".jpg":  "image/jpeg",
		".jpeg": "image/jpeg",
		".png":  "image/png",
		".gif":  "image/gif",
		".webp": "image/webp",
		".bmp":  "image/bmp",
		".svg":  "image/svg+xml",
		".mp4":  "video/mp4",
		".webm": "video/webm",
		".mov":  "video/quicktime",
		".m4v":  "video/x-m4v",
		".ogv":  "video/ogg",
		".avi":  "video/x-msvideo",
		".mkv":  "video/x-matroska",
	}
	if value := custom[ext]; value != "" {
		return value
	}
	if value := mime.TypeByExtension(ext); value != "" {
		return strings.Split(value, ";")[0]
	}
	return "application/octet-stream"
}
