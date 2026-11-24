package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/middleware"
	"bookstark/models"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func installIdentity(c *gin.Context) (int64, int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	member := middleware.GetMemberID(c)
	if err != nil || id == 0 || member <= 0 {
		c.Status(http.StatusNotFound)
		return 0, 0, false
	}
	return member, id, true
}
func toolAPIError(c *gin.Context, err error) {
	code, status := "storage_failed", 500
	switch {
	case errors.Is(err, models.ErrToolPermission):
		code, status = "permission_denied", 403
	case errors.Is(err, models.ErrToolConflict):
		code, status = "conflict", 409
	case errors.Is(err, sql.ErrNoRows) || errors.Is(err, models.ErrDAVNotFound):
		code, status = "not_found", 404
	case errors.Is(err, models.ErrDAVAlreadyExists):
		code, status = "already_exists", 409
	case errors.Is(err, models.ErrToolDirectoryNotEmpty):
		code, status = "directory_not_empty", 409
	case errors.Is(err, models.ErrDAVNotDirectory):
		code, status = "not_directory", 400
	case errors.Is(err, models.ErrDAVIsDirectory):
		code, status = "is_directory", 400
	case errors.Is(err, models.ErrDAVQuotaExceeded) || errors.Is(err, models.ErrDAVFileTooLarge):
		code, status = "quota_exceeded", 413
	case errors.Is(err, models.ErrDAVInvalidPath):
		code, status = "invalid_path", 400
	case errors.Is(err, models.ErrToolCleanupPending):
		code, status = "cleanup_pending", 503
	}
	c.JSON(status, gin.H{"error": code})
}
func ListToolInstalls(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	member := middleware.GetMemberID(c)
	if err := models.CleanupToolResources(member); err != nil {
		toolAPIError(c, fmt.Errorf("%w: %v", models.ErrToolCleanupPending, err))
		return
	}
	items, err := models.ListInstalledTools(member)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, gin.H{"tools": items})
}
func GetToolInstall(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	member, id, ok := installIdentity(c)
	if !ok {
		return
	}
	if c.Query("part") == "runtime" {
		runtime, err := models.GetInstalledToolRuntime(member, id)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		runtime.Content, err = decodeMarketContent(runtime.Content)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		c.JSON(200, runtime)
		return
	}
	t, err := models.GetInstalledTool(member, id)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	switch c.Query("part") {
	case "package":
		raw, err := models.GetInstalledToolContent(member, id)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		content, err := decodeMarketContent(raw)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		c.JSON(200, gin.H{"id": id, "content": content, "revision": t.Revision, "instance": t.Instance})
	case "data":
		values, err := models.GetInstalledToolValues(member, id)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		c.JSON(200, gin.H{"id": id, "values": values})
	default:
		c.JSON(200, t)
	}
}
func InstallMarketTool(router http.Handler) gin.HandlerFunc {
	return func(c *gin.Context) {
		member, id, ok := installIdentity(c)
		if !ok {
			return
		}
		var req struct {
			Hash     string `json:"hash"`
			Revision string `json:"revision"`
			Expected string `json:"expected"`
			Instance string `json:"instance"`
		}
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 4096)
		if c.ShouldBindJSON(&req) != nil {
			c.Status(400)
			return
		}
		pkg, err := loadPublishedTool(id)
		origin := strings.TrimSuffix(readMarketSettings(c).PublicURL, "/market")
		fetch := localToolFetch(router, origin)
		if id < 0 {
			pkg, origin, err = remoteTool(c.Request.Context(), member, id)
			fetch = marketResourceFetch(origin)
		}
		if err != nil {
			if id < 0 {
				remoteMarketError(c, err)
			} else {
				c.Status(404)
			}
			return
		}
		if req.Revision != pkg.Revision || (req.Hash != "" && req.Hash != pkg.Hash) {
			toolAPIError(c, models.ErrToolConflict)
			return
		}
		base := pkg.ResourceBase
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Minute)
		defer cancel()
		if id > 0 && !mayInstallTool(c, pkg.ToolMetadata) {
			return
		}
		if id > 0 {
			if err := loadPublishedToolContent(&pkg); err != nil {
				c.Status(404)
				return
			}
		}
		content, resources, err := toolpackage.Build(ctx, pkg.Content, base, fetch)
		if err != nil {
			c.JSON(422, gin.H{"error": "resource_download_failed"})
			return
		}
		t := models.InstalledTool{ToolMetadata: pkg.ToolMetadata, ID: id, Title: pkg.Title, Description: pkg.Description, Author: pkg.Author, Source: pkg.Source, Revision: pkg.Revision, Content: content, Resources: resources}
		if err = models.SaveInstalledTool(member, t, req.Expected, req.Instance); err != nil {
			toolAPIError(c, err)
			return
		}
		c.JSON(200, gin.H{"ok": true})
	}
}
func DeleteToolInstall(c *gin.Context) {
	member, id, ok := installIdentity(c)
	if !ok {
		return
	}
	var req struct {
		KeepData bool   `json:"keep_data"`
		Revision string `json:"revision"`
		Instance string `json:"instance"`
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 4096)
	if c.ShouldBindJSON(&req) != nil {
		c.Status(400)
		return
	}
	if err := models.DeleteInstalledTool(member, id, req.Revision, req.Instance, req.KeepData); err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, gin.H{"ok": true})
}
func PatchToolInstall(c *gin.Context) {
	member, id, ok := installIdentity(c)
	if !ok {
		return
	}
	var req struct {
		Pinned *bool  `json:"pinned"`
		Used   *int64 `json:"used"`
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 4096)
	if c.ShouldBindJSON(&req) != nil {
		c.Status(400)
		return
	}
	if err := models.PatchInstalledTool(member, id, req.Pinned, req.Used); err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, gin.H{"ok": true})
}
func WriteToolInstallData(c *gin.Context) {
	member, id, ok := installIdentity(c)
	if !ok {
		return
	}
	var req struct {
		Revision string `json:"revision"`
		Instance string `json:"instance"`
		Op       string `json:"op"`
		Key      string `json:"key"`
		Value    string `json:"value"`
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 6<<20)
	if c.ShouldBindJSON(&req) != nil {
		c.Status(400)
		return
	}
	if err := models.WriteInstalledToolValue(member, id, req.Revision, req.Instance, req.Op, req.Key, req.Value); err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, gin.H{"ok": true})
}
func ToolInstallFile(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	member, id, ok := installIdentity(c)
	if !ok {
		return
	}
	if models.WebDAVDB == nil {
		toolAPIError(c, errors.New("file storage unavailable"))
		return
	}
	if c.Request.Method == http.MethodPut {
		limit := models.GetWebDAVSettings().FileMaxBytes
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, limit)
		err := models.PutToolResource(member, id, c.GetHeader("X-Tool-Revision"), c.GetHeader("X-Tool-Instance"), "data", c.Param("filepath"), c.ContentType(), c.Request.Body)
		if err != nil {
			toolAPIError(c, err)
			return
		}
		c.JSON(200, gin.H{"ok": true})
		return
	}
	t, err := models.GetInstalledTool(member, id)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	if t.Revision != c.GetHeader("X-Tool-Revision") || t.Instance != c.GetHeader("X-Tool-Instance") {
		toolAPIError(c, models.ErrToolConflict)
		return
	}
	if !t.Permissions.ReadFiles {
		toolAPIError(c, models.ErrToolPermission)
		return
	}
	p, err := models.ToolResourcePath(t, "data", c.Param("filepath"))
	if err != nil {
		toolAPIError(c, err)
		return
	}
	node, blob, reader, err := models.ReadDAVFileContext(c.Request.Context(), member, p)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	defer reader.Close()
	c.Header("Content-Disposition", "attachment")
	c.Header("X-Content-Type-Options", "nosniff")
	c.DataFromReader(200, blob.OriginalSize, node.MIMEType, reader, nil)
}

// Metadata and tree operations are JSON to preserve names and to avoid WebDAV
// headers or paths ever exposing the rest of the account's file system.
func ToolInstallFileOperation(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	member, id, ok := installIdentity(c)
	if !ok {
		return
	}
	var request models.ToolFileOperation
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 8192)
	if c.ShouldBindJSON(&request) != nil {
		c.Status(400)
		return
	}
	result, err := models.ExecuteToolFileOperation(member, id, c.GetHeader("X-Tool-Revision"), c.GetHeader("X-Tool-Instance"), request)
	if err != nil {
		toolAPIError(c, err)
		return
	}
	c.JSON(200, gin.H{"result": result})
}
