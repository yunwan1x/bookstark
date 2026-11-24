package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/models"
	"github.com/gin-gonic/gin"
	"net"
	"net/http"
	"path"
	"strings"
)

func sandboxToolInstance(host string) string {
	name := strings.ToLower(host)
	if h, _, err := net.SplitHostPort(name); err == nil {
		name = h
	}
	if toolLocalHost.MatchString(name) {
		return strings.TrimSuffix(strings.TrimPrefix(name, "tool-"), ".localhost")
	}
	template := strings.TrimPrefix(strings.ToLower(models.GetSetting("tool_runtime_origin")), "https://")
	if matchesToolHostTemplate(template, strings.ToLower(host)) {
		prefix, _, _ := strings.Cut(template, "{instance}")
		return strings.ToLower(host)[len(prefix) : len(prefix)+32]
	}
	return ""
}

// Package files share only their installation's origin. No application route is
// reachable here, and the active asset epoch revokes old files after updates.
func serveSandboxToolAsset(c *gin.Context, instance string) {
	// A persistent service worker could intercept future versions on this origin.
	if c.GetHeader("Service-Worker") == "script" || c.GetHeader("Sec-Fetch-Dest") == "serviceworker" {
		c.Status(http.StatusForbidden)
		return
	}
	if c.Request.Method != http.MethodGet && c.Request.Method != http.MethodHead {
		c.Status(404)
		return
	}
	var member, id int64
	var root string
	if models.DB.QueryRow(`SELECT member_id,tool_id,assets FROM md_tool_installs WHERE instance=?`, instance).Scan(&member, &id, &root) != nil {
		c.Status(404)
		return
	}
	metadata := models.ReadToolMetadata(member, id)
	if metadata.Distribution != "files" {
		c.Status(404)
		return
	}
	name := strings.TrimPrefix(c.Request.URL.Path, "/")
	assetPrefix := "api/tool-assets/" + instance + "/" + path.Base(root) + "/"
	if strings.HasPrefix(name, "api/tool-assets/") {
		if !strings.HasPrefix(name, assetPrefix) {
			c.Status(404)
			return
		}
		name = strings.TrimPrefix(name, assetPrefix)
	}
	if !toolpackage.ValidName(name) {
		c.Status(404)
		return
	}
	p, err := models.ToolResourcePath(&models.InstalledTool{Assets: root}, "assets", name)
	if err != nil {
		c.Status(404)
		return
	}
	node, blob, reader, err := models.ReadDAVFileContext(c.Request.Context(), member, p)
	if err != nil {
		c.Status(404)
		return
	}
	defer reader.Close()
	c.Header("Cache-Control", "no-store")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Header("Referrer-Policy", "no-referrer")
	// Worker scripts enforce their own policy; document CSP is not inherited.
	c.Header("Content-Security-Policy", toolFramePolicy(metadata.Permissions, "'self'", "'none'"))
	c.Header("Permissions-Policy", toolFeaturePolicy(metadata.Permissions, "", false))
	c.DataFromReader(200, blob.OriginalSize, node.MIMEType, reader, nil)
}
