package controllers

import (
	"bookstark/conf"
	"bookstark/internal/toolpackage"
	"bookstark/models"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

var toolLocalHost = regexp.MustCompile(`^tool-[a-f0-9]{32}\.localhost$`)
var toolInstanceLabel = regexp.MustCompile(`^[a-f0-9]{32}$`)

// IsLocalToolSandboxHost admits only a per-installation loopback hostname on
// the existing launcher port; it never exposes the launcher itself.
func IsLocalToolSandboxHost(host, port string) bool {
	name, actual, err := net.SplitHostPort(host)
	return err == nil && actual == port && toolLocalHost.MatchString(strings.ToLower(name))
}

// Match the actual placeholder, not a word which might also appear in a
// literal prefix such as "instance-tools-". Only installation labels may vary.
func matchesToolHostTemplate(template, host string) bool {
	prefix, suffix, ok := strings.Cut(strings.ToLower(template), "{instance}")
	host = strings.ToLower(host)
	if !ok || !strings.HasPrefix(host, prefix) || !strings.HasSuffix(host, suffix) || len(host) != len(prefix)+32+len(suffix) {
		return false
	}
	return toolInstanceLabel.MatchString(host[len(prefix) : len(prefix)+32])
}

// Separate origins are mandatory before allow-same-origin can be combined with
// scripts. Each installation gets its own origin, never the application origin.
func validToolOriginTemplate(raw, appOrigin string) bool {
	if raw == "" {
		return true
	}
	if len(raw) > 512 {
		return false
	}
	if strings.Count(raw, "{instance}") != 1 {
		return false
	}
	u, err := url.Parse(strings.ReplaceAll(raw, "{instance}", strings.Repeat("a", 32)))
	if err != nil || u.Scheme != "https" || u.User != nil || u.Host == "" || u.Path != "" || u.RawQuery != "" || u.Fragment != "" {
		return false
	}
	if !strings.Contains(strings.Split(raw, "://")[1], "{instance}.") {
		return false
	}
	parent, err := url.Parse(appOrigin)
	if err != nil {
		return false
	}
	hostTemplate := strings.TrimPrefix(strings.ToLower(raw), "https://")
	if u.Port() != "" {
		hostTemplate = strings.TrimSuffix(hostTemplate, ":"+u.Port())
	}
	if matchesToolHostTemplate(hostTemplate, parent.Hostname()) {
		return false
	}
	return !strings.EqualFold(u.Hostname(), parent.Hostname()) && !strings.HasSuffix(strings.ToLower(parent.Hostname()), "."+strings.ToLower(u.Hostname()))
}
func toolParentOrigin(c *gin.Context) string {
	origin := requestToolOrigin(c)
	if c.GetHeader("X-Forwarded-Proto") == "https" {
		origin = "https://" + c.Request.Host
	}
	return origin
}
func toolOrigin(c *gin.Context, instance string) string {
	if len(instance) != 32 {
		return ""
	}
	parent, _ := url.Parse(toolParentOrigin(c))
	host := strings.ToLower(parent.Hostname())
	if host == "localhost" || host == "127.0.0.1" {
		target := "tool-" + instance + ".localhost"
		if parent.Port() != "" {
			target = net.JoinHostPort(target, parent.Port())
		}
		return parent.Scheme + "://" + target
	}
	raw := strings.ToLower(models.GetSetting("tool_runtime_origin"))
	if raw == "" || !validToolOriginTemplate(raw, parent.String()) {
		return ""
	}
	return strings.ReplaceAll(raw, "{instance}", instance)
}

// Intercept sandbox hosts before cookies, authentication, CORS or application
// routes. Serving login/API pages at a tool origin would break the boundary.
func ToolSandboxMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		host := strings.ToLower(c.Request.Host)
		hostname := strings.Split(host, ":")[0]
		sandbox := toolLocalHost.MatchString(hostname)
		raw := models.GetSetting("tool_runtime_origin")
		if raw != "" && matchesToolHostTemplate(strings.TrimPrefix(strings.ToLower(raw), "https://"), host) {
			sandbox = true
		}
		if c.Request.URL.Path == "/tools/frame" {
			ToolFrame(c)
			c.Abort()
			return
		}
		if sandbox {
			if c.Query("ticket") != "" {
				ToolFrame(c)
			} else if instance := sandboxToolInstance(c.Request.Host); instance != "" {
				serveSandboxToolAsset(c, instance)
			} else {
				c.Status(http.StatusNotFound)
			}
			c.Abort()
			return
		}
		c.Next()
	}
}

type toolFrameTicket struct {
	Parent      string                 `json:"parent"`
	Origin      string                 `json:"origin"`
	Instance    string                 `json:"instance"`
	Nonce       string                 `json:"nonce"`
	Permissions models.ToolPermissions `json:"permissions"`
	Page        string                 `json:"page,omitempty"`
	Expires     int64                  `json:"expires"`
}

func signToolFrame(payload string) string {
	mac := hmac.New(sha256.New, []byte(conf.App.JWTSecret))
	mac.Write([]byte("bookstark-tool-frame-v1:" + payload))
	return hex.EncodeToString(mac.Sum(nil))
}
func toolFramePolicy(p models.ToolPermissions, assetRoot, parent string) string {
	p = p.Effective()
	flags := p.Flags()
	network := ""
	if p.Network {
		network = " http: https: ws: wss:"
	}
	form := "'none'"
	if flags["forms"] && p.Network {
		form = "http: https:"
	}
	sandbox := toolSandbox(p, true)
	return "sandbox " + sandbox + "; default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob: " + assetRoot + network + "; style-src 'unsafe-inline' " + assetRoot + network + "; img-src data: blob: " + assetRoot + network + "; font-src data: " + assetRoot + network + "; media-src data: blob: " + assetRoot + network + "; connect-src " + assetRoot + network + "; form-action " + form + "; frame-src 'none'; object-src 'none'; base-uri 'none'; frame-ancestors " + parent
}
func toolSandbox(p models.ToolPermissions, isolated bool) string {
	result := []string{"allow-scripts"}
	if isolated {
		result = append(result, "allow-same-origin")
	}
	flags := p.Flags()
	for _, spec := range models.ToolPermissionCatalog {
		if spec.Sandbox != "" && flags[spec.Key] {
			result = append(result, spec.Sandbox)
		}
	}
	return strings.Join(result, " ")
}
func toolFeaturePolicy(p models.ToolPermissions, origin string, parent bool) string {
	flags := p.Flags()
	result := []string{}
	for _, spec := range models.ToolPermissionCatalog {
		if spec.Policy == "" {
			continue
		}
		allowed := ""
		if flags[spec.Key] {
			allowed = "self"
			if parent {
				allowed = "self \"" + origin + "\""
			}
		}
		result = append(result, spec.Policy+"=("+allowed+")")
	}
	return strings.Join(result, ", ")
}
func toolFrameConfiguration(c *gin.Context, tool *models.InstalledTool) gin.H {
	origin := toolOrigin(c, tool.Instance)
	result := gin.H{"origin": origin, "instance": tool.Instance, "revision": tool.Revision, "isolated": origin != "", "socket_proxy": toolSocketEnabled()}
	if origin == "" {
		return result
	}
	ticket := toolFrameTicket{Parent: toolParentOrigin(c), Origin: origin, Instance: tool.Instance, Nonce: rand.Text(), Permissions: tool.Permissions, Expires: time.Now().Add(10 * time.Minute).Unix()}
	raw, _ := json.Marshal(ticket)
	if tool.Distribution == "files" && toolpackage.ValidName(tool.Entry) {
		ticket.Page = tool.Entry
		raw, _ = json.Marshal(ticket)
	}
	payload := base64.RawURLEncoding.EncodeToString(raw)
	result["url"] = origin + "/tools/frame?ticket=" + url.QueryEscape(payload) + "&signature=" + signToolFrame(payload)
	if ticket.Page != "" {
		result["url"] = origin + "/" + ticket.Page + "?ticket=" + url.QueryEscape(payload) + "&signature=" + signToolFrame(payload)
	}
	result["nonce"] = ticket.Nonce
	c.Header("Permissions-Policy", toolFeaturePolicy(tool.Permissions, origin, true))
	c.Header("Content-Security-Policy", "frame-src "+origin)
	return result
}
func ToolFrame(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Header("Referrer-Policy", "no-referrer")
	payload := c.Query("ticket")
	signature := c.Query("signature")
	if c.Request.Method != "GET" || len(payload) > 8192 || !hmac.Equal([]byte(signToolFrame(payload)), []byte(signature)) {
		c.Status(403)
		return
	}
	raw, err := base64.RawURLEncoding.DecodeString(payload)
	var ticket toolFrameTicket
	if err != nil || json.Unmarshal(raw, &ticket) != nil || ticket.Expires < time.Now().Unix() || ticket.Expires > time.Now().Add(11*time.Minute).Unix() || ticket.Origin != toolParentOrigin(c) || ticket.Origin == ticket.Parent {
		c.Status(403)
		return
	}
	parent, _ := url.Parse(ticket.Parent)
	if parent == nil || parent.Host == "" {
		c.Status(403)
		return
	}
	// Validate the origin against the exact installation-specific address signed by
	// the authenticated host. No private HTML or account credential is in the URL.
	expected := ""
	if parent.Hostname() == "127.0.0.1" || parent.Hostname() == "localhost" {
		expected = parent.Scheme + "://tool-" + ticket.Instance + ".localhost"
		if parent.Port() != "" {
			expected += ":" + parent.Port()
		}
	} else {
		setting := models.GetSetting("tool_runtime_origin")
		if setting != "" && validToolOriginTemplate(setting, ticket.Parent) {
			expected = strings.ReplaceAll(setting, "{instance}", ticket.Instance)
		}
	}
	if expected != ticket.Origin {
		c.Status(403)
		return
	}
	assetRoot := ticket.Parent + "/api/tool-assets/" + ticket.Instance + "/"
	if ticket.Page != "" {
		if !toolpackage.ValidName(ticket.Page) || c.Request.URL.Path != "/"+ticket.Page {
			c.Status(403)
			return
		}
		assetRoot = "'self' " + assetRoot
	} else if c.Request.URL.Path != "/tools/frame" {
		c.Status(403)
		return
	}
	c.Header("Content-Security-Policy", toolFramePolicy(ticket.Permissions, assetRoot, ticket.Parent))
	c.Header("Permissions-Policy", toolFeaturePolicy(ticket.Permissions, "", false))
	data, _ := json.Marshal(gin.H{"parent": ticket.Parent, "nonce": ticket.Nonce})
	script := `const config=CONFIG;function receive(event){const m=event.data;if(event.source!==parent||event.origin!==config.parent||!m||m.toolFrame!==config.nonce||typeof m.html!=="string")return;removeEventListener('message',receive);document.open();document.write(m.html);document.close();}addEventListener('message',receive);parent.postMessage({toolFrame:config.nonce,ready:true},config.parent);`
	script = strings.Replace(script, "CONFIG", string(data), 1)
	c.Data(200, "text/html; charset=utf-8", []byte(fmt.Sprintf("<!doctype html><html><head><meta charset=\"utf-8\"><title>BookStark Tool</title></head><body><script>%s</script></body></html>", script)))
}
