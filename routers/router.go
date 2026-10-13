package routers

import (
	"encoding/json"
	"html/template"
	"io/fs"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"bookstark/conf"
	"bookstark/controllers"
	"bookstark/middleware"
	"bookstark/models"
)

// EmbedFS is set by main package in embed mode; nil in dev mode
var EmbedFS struct {
	StaticFS   fs.FS
	TemplateFS fs.FS
	ConfFS     fs.FS
}

var templateFuncs = template.FuncMap{
	"footerGroups": models.GroupFriendLinks,
	"footerSimple": models.FooterSimpleMode,
	"buildTime": func() string {
		if t, err := time.Parse("20060102150405", conf.App.BuildTime); err == nil {
			return t.Format("01-02 15:04")
		}
		return "—"
	},
	"gitCommit": func() string {
		if conf.App.GitCommit == "" {
			return "unknown"
		}
		return conf.App.GitCommit
	},
	"formatTime": func(t interface{}) string {
		switch v := t.(type) {
		case time.Time:
			if v.IsZero() {
				return ""
			}
			return v.Format("2006-01-02 15:04")
		case *time.Time:
			if v == nil || v.IsZero() {
				return ""
			}
			return v.Format("2006-01-02 15:04")
		default:
			return ""
		}
	},
	"splitLabels": func(s string) []string {
		if s == "" {
			return nil
		}
		var result []string
		for _, part := range strings.Split(s, ",") {
			part = strings.TrimSpace(part)
			if part != "" {
				result = append(result, part)
			}
		}
		return result
	},
	"substr": func(s string, start, length int) string {
		if start >= len(s) {
			return ""
		}
		end := start + length
		if end > len(s) {
			end = len(s)
		}
		return s[start:end]
	},
	"jsonJS": func(s string) template.JS {
		b, _ := json.Marshal(s)
		result := strings.ReplaceAll(string(b), "</script", `<\/script`)
		return template.JS(result)
	},
	"json": func(v interface{}) template.JS {
		b, _ := json.Marshal(v)
		result := strings.ReplaceAll(string(b), "</script", `<\/script`)
		return template.JS(result)
	},
	"calcTotalPages": func(total int64, pageSize int) int {
		pages := int(total) / pageSize
		if int(total)%pageSize > 0 {
			pages++
		}
		return pages
	},
	"sub": func(a, b int) int {
		return a - b
	},
	"assetVer": func(path string) string {
		return conf.AssetVer(path)
	},
	"hasPrefix": strings.HasPrefix,
}

func Setup() *gin.Engine {
	if conf.App.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.Default()
	r.RedirectTrailingSlash = false
	r.MaxMultipartMemory = 8 << 20 // 8MB

	r.Use(middleware.LangMiddleware())

	// 安全响应头中间件
	r.Use(func(c *gin.Context) {
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "SAMEORIGIN")
		c.Header("X-XSS-Protection", "1; mode=block")
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		c.Header("Permissions-Policy", "camera=(self), microphone=(self), display-capture=(self), geolocation=(self)")
		// HSTS 仅在 HTTPS 下启用
		if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
			c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		c.Next()
	})

	// CORS middleware — allow browser extension / API client access
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS, PROPFIND, PROPPATCH, MKCOL, COPY, MOVE, LOCK, UNLOCK")
		c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type")
		c.Header("Access-Control-Max-Age", "86400")
		if c.Request.Method == "OPTIONS" {
			if c.Request.URL.Path == "/dav" || strings.HasPrefix(c.Request.URL.Path, "/dav/") {
				c.Next()
				return
			}
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	// Load templates with custom functions
	r.SetFuncMap(templateFuncs)
	if EmbedFS.TemplateFS != nil {
		tmpl := template.Must(template.New("").Funcs(templateFuncs).ParseFS(EmbedFS.TemplateFS, "*"))
		r.SetHTMLTemplate(tmpl)
	} else {
		r.LoadHTMLGlob("templates/*")
	}

	// Static files
	if EmbedFS.StaticFS != nil {
		r.StaticFS("/static", http.FS(EmbedFS.StaticFS))
	} else {
		r.Static("/static", "./static")
	}

	// Favicon
	r.GET("/favicon.ico", func(c *gin.Context) {
		if EmbedFS.StaticFS != nil {
			c.FileFromFS("favicon.svg", http.FS(EmbedFS.StaticFS))
		} else {
			c.File("static/favicon.svg")
		}
	})

	// Favicon proxy (public, no auth required)
	r.GET("/api/favicon", controllers.FaviconProxy)

	// Language switch API (public, no auth/CSRF required)
	r.POST("/api/lang", controllers.SetLangAPI)
	r.GET("/api/lang/bundle", controllers.GetLangBundle)
	r.GET("/api/set-lang", controllers.SetLang)

	// Upload file serving (public, no auth required)
	r.GET("/upload-files/*filepath", controllers.ServeUploadFile)

	// Manifest (must have correct Content-Type for PWA installability)
	r.GET("/manifest.json", func(c *gin.Context) {
		c.Header("Content-Type", "application/json")
		c.Header("Cache-Control", "no-cache")
		if EmbedFS.StaticFS != nil {
			c.FileFromFS("manifest.json", http.FS(EmbedFS.StaticFS))
		} else {
			c.File("static/manifest.json")
		}
	})

	// Service Worker (must be at root scope)
	r.GET("/sw.js", func(c *gin.Context) {
		c.Header("Service-Worker-Allowed", "/")
		c.Header("Content-Type", "application/javascript")
		c.Header("Cache-Control", "no-cache")
		if EmbedFS.StaticFS != nil {
			c.FileFromFS("sw.js", http.FS(EmbedFS.StaticFS))
		} else {
			c.File("static/sw.js")
		}
	})

	// Public pages
	r.GET("/", middleware.OptionalAuth(), middleware.CSRFMiddleware(), middleware.VisitLog(), controllers.HomePage)
	r.GET("/nav", middleware.OptionalAuth(), middleware.CSRFMiddleware(), middleware.VisitLog(), controllers.NavPage)
	r.GET("/login", controllers.LoginPage)
	r.GET("/register", controllers.RegisterPage)
	r.GET("/forgot-password", controllers.ForgotPasswordPage)
	r.GET("/reset-password", controllers.ResetPasswordPage)
	// Public bookmark page (with optional auth for user filtering)
	r.GET("/bookmarks", middleware.OptionalAuth(), middleware.CSRFMiddleware(), middleware.VisitLog(), controllers.BookmarksPage)
	// Public shares pages
	r.GET("/shares", middleware.OptionalAuth(), middleware.CSRFMiddleware(), middleware.VisitLog(), controllers.SharesPage)
	r.GET("/shares/:identify", middleware.OptionalAuth(), middleware.CSRFMiddleware(), middleware.VisitLog(), controllers.ShareViewPage)
	// Public notes page
	r.GET("/notes/public", middleware.OptionalAuth(), middleware.CSRFMiddleware(), middleware.VisitLog(), controllers.NotesPublicPage)

	// Public APIs
	r.GET("/api/csrf-token", middleware.CSRFMiddleware(), func(c *gin.Context) {
		c.Header("Cache-Control", "no-store")
		// Background workers cannot read document.cookie.
		c.JSON(http.StatusOK, gin.H{"code": 0, "csrf_token": middleware.GetCSRFToken(c)})
	})
	r.POST("/api/login", controllers.Login)
	r.POST("/api/register", controllers.Register)
	r.POST("/api/password/forgot", controllers.RequestPasswordReset)
	r.POST("/api/password/reset", controllers.CompletePasswordReset)
	r.GET("/api/register-config", controllers.RegisterConfig)
	// Public bookmark APIs (with optional auth for user filtering)
	r.GET("/api/bookmark-labels", middleware.OptionalAuth(), controllers.ListBookmarkLabels)
	r.GET("/api/bookmark-labels-with-count", middleware.OptionalAuth(), controllers.ListBookmarkLabelsWithCount)
	r.GET("/api/bookmarks", middleware.OptionalAuth(), controllers.ListBookmarks)
	r.GET("/api/bookmarks-grouped", middleware.OptionalAuth(), controllers.ListBookmarksGrouped)
	// Public share APIs
	r.GET("/api/shares", controllers.ListShares)
	r.GET("/api/shares/:identify", controllers.GetShare)
	r.POST("/api/shares/:identify/verify-password", controllers.VerifySharePassword)
	r.POST("/api/shares/:identify/verify-password/raw", controllers.VerifySharePasswordRaw)
	r.GET("/api/shares/:identify/content/raw", controllers.GetShareHTMLRawContent)
	r.GET("/api/shares/:identify/comments", middleware.OptionalAuth(), controllers.ListShareComments)
	r.POST("/api/shares/:identify/comments", middleware.OptionalAuth(), middleware.CSRFMiddleware(), controllers.CreateShareComment)
	r.DELETE("/api/share-comments/:commentID", middleware.OptionalAuth(), middleware.CSRFMiddleware(), controllers.DeleteShareComment)
	r.GET("/api/shares/:identify/docs/:docIdentify", controllers.GetBookShareDoc)
	r.GET("/api/shares/:identify/docs/:docIdentify/content/raw", controllers.GetBookShareDocHTMLRawContent)
	r.GET("/api/shares/:identify/edit", controllers.GetShareEdit)
	r.GET("/api/shares/:identify/edit/content/raw", controllers.GetShareEditHTMLRawContent)
	r.POST("/api/shares/:identify/edit/content/unlock", controllers.UnlockShareEditRawContent)
	r.POST("/api/shares/:identify/edit/uploads", controllers.UploadShareEditImage)
	r.PUT("/api/shares/:identify/edit", controllers.SaveShareEdit)
	r.GET("/dav-public/:account/*filepath", controllers.ServeDAVPublicAsset)
	r.HEAD("/dav-public/:account/*filepath", controllers.ServeDAVPublicAsset)
	for _, method := range []string{
		http.MethodGet, http.MethodHead, http.MethodPut, http.MethodDelete, http.MethodOptions,
		"PROPFIND", "PROPPATCH", "MKCOL", "COPY", "MOVE", "LOCK", "UNLOCK",
	} {
		r.Handle(method, "/dav", controllers.HandleLocalWebDAV)
		r.Handle(method, "/dav/*filepath", controllers.HandleLocalWebDAV)
	}
	controllers.RegisterWebRTCSignalingRoutes(r)

	// Auth required
	auth := r.Group("/")
	auth.Use(middleware.AuthRequired())
	// CSRF 中间件仅保护需要认证的路由
	// 跳过已认证但不需要 CSRF 的路径（如果有）
	auth.Use(middleware.CSRFMiddleware("/api/logout"))
	auth.Use(middleware.VisitLog())
	{
		// Pages
		auth.GET("/home", controllers.PersonalHomePage)
		auth.GET("/api/home", controllers.HomeSummary)
		auth.PUT("/api/home/layout", controllers.SaveHomeLayout)
		auth.GET("/books", controllers.IndexPage)
		auth.GET("/books/:identify/edit", controllers.EditorPage)
		auth.GET("/blogs", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "/notes") })
		auth.GET("/blogs/:identify/edit", controllers.BlogEditorPage)
		auth.GET("/notes", controllers.NotesPage)
		auth.GET("/topics", controllers.TopicsPage)
		auth.GET("/images", controllers.ImagesPage)
		auth.GET("/labels", controllers.LabelsPage)
		auth.GET("/search", controllers.SearchPage)
		auth.GET("/profile", controllers.ProfilePage)
		auth.GET("/trash", controllers.TrashPage)
		auth.GET("/webdav", controllers.WebDAVPage)

		// Account APIs
		auth.POST("/api/logout", controllers.Logout)
		auth.GET("/api/profile", controllers.GetProfile)
		auth.GET("/api/profile/background", controllers.GetBackground)
		auth.PUT("/api/profile/background", controllers.UpdateBackground)
		auth.GET("/api/profile/background/image", controllers.BackgroundImage)
		auth.PUT("/api/profile", controllers.UpdateProfile)
		auth.GET("/api/profile/task-reminder", controllers.GetTaskReminderPreference)
		auth.PUT("/api/profile/task-reminder", controllers.UpdateTaskReminderPreference)
		auth.POST("/api/profile/task-reminder/test", controllers.TestProfileMail)
		auth.PUT("/api/password", controllers.ChangePassword)

		// Built-in WebDAV APIs
		auth.GET("/api/webdav/profile", controllers.LocalDAVProfile)
		auth.POST("/api/webdav/app-password/reset", controllers.ResetLocalDAVPassword)
		auth.DELETE("/api/webdav/app-password", controllers.RevokeLocalDAVPassword)
		auth.GET("/api/webdav/files", controllers.ListLocalDAVFiles)
		auth.GET("/api/webdav/files/download", controllers.DownloadLocalDAVFile)
		auth.GET("/api/webdav/files/preview", controllers.PreviewLocalDAVFile)
		auth.GET("/api/webdav/files/content", controllers.ReadLocalDAVFile)
		auth.PUT("/api/webdav/files/content", controllers.SaveLocalDAVFile)
		auth.POST("/api/webdav/files/upload", controllers.UploadLocalDAVFile)
		auth.POST("/api/webdav/files/upload/check", controllers.CheckLocalDAVUpload)
		auth.POST("/api/webdav/files/upload/prove", controllers.ProveLocalDAVUpload)
		auth.POST("/api/webdav/files/mkdir", controllers.MkdirLocalDAVFile)
		auth.POST("/api/webdav/files/rename", controllers.RenameLocalDAVFile)
		auth.POST("/api/webdav/files/copy", controllers.CopyLocalDAVFile)
		auth.DELETE("/api/webdav/files", controllers.DeleteLocalDAVFile)
		auth.POST("/api/webdav/files/public", controllers.PublishLocalDAVFile)
		auth.DELETE("/api/webdav/files/public", controllers.UnpublishLocalDAVFile)

		// Book APIs
		auth.GET("/api/books", controllers.ListBooks)
		auth.GET("/api/books/:id", controllers.GetBook)
		auth.POST("/api/books", controllers.CreateBook)
		auth.PUT("/api/books/:id", controllers.UpdateBook)
		auth.DELETE("/api/books/:id", controllers.DeleteBook)

		// Document APIs
		auth.GET("/api/books/:id/docs/tree", controllers.GetDocTree)
		auth.GET("/api/docs/:id", controllers.GetDocument)
		auth.GET("/api/docs/:id/content/raw", controllers.GetDocumentHTMLRawContent)
		auth.POST("/api/books/:id/docs", controllers.CreateDocument)
		auth.PUT("/api/docs/:id", controllers.UpdateDocument)
		auth.DELETE("/api/docs/:id", controllers.DeleteDocument)
		auth.PATCH("/api/docs/:id/sort", controllers.SortDocument)
		auth.PATCH("/api/docs/:id/move", controllers.MoveDocument)
		auth.PATCH("/api/docs/:id/reorder", controllers.ReorderDocument)

		// Blog APIs
		auth.GET("/api/blogs", controllers.ListBlogs)
		auth.POST("/api/blogs", controllers.CreateBlog)
		auth.GET("/api/blogs/:id", controllers.GetBlog)
		auth.GET("/api/blogs/:id/content/raw", controllers.GetBlogHTMLRawContent)
		auth.PUT("/api/blogs/:id", controllers.UpdateBlog)
		auth.DELETE("/api/blogs/:id", controllers.DeleteBlog)
		auth.POST("/api/blogs/:id/verify-password", controllers.VerifyBlogPassword)
		auth.POST("/api/blogs/:id/verify-password/raw", controllers.VerifyBlogPasswordRaw)
		auth.PATCH("/api/blogs/:id/pin", controllers.ToggleBlogPinAPI)
		auth.PATCH("/api/blogs/:id/visibility", controllers.ToggleBlogVisibilityAPI)
		auth.POST("/api/blogs/batch-pin", controllers.BatchPinBlogsAPI)
		auth.GET("/api/blogs/daily-counts", controllers.GetBlogDailyCountsAPI)

		// Bookmark APIs
		auth.POST("/api/bookmarks", controllers.CreateBookmark)
		auth.POST("/api/bookmarks/batch-delete", controllers.BatchDeleteBookmarks)
		auth.POST("/api/bookmarks/batch-share", controllers.BatchShareBookmarks)
		auth.POST("/api/bookmarks/batch-unshare", controllers.BatchUnshareBookmarks)
		auth.POST("/api/bookmarks/batch-add-labels", controllers.BatchAddBookmarkLabels)
		auth.POST("/api/bookmarks/batch-remove-labels", controllers.BatchRemoveBookmarkLabels)
		auth.POST("/api/bookmarks/batch-pin", controllers.BatchPinBookmarks)
		auth.POST("/api/bookmarks/batch-unpin", controllers.BatchUnpinBookmarks)
		auth.POST("/api/bookmarks/batch-show-nav", controllers.BatchShowNavBookmarks)
		auth.POST("/api/bookmarks/batch-hide-nav", controllers.BatchHideNavBookmarks)
		auth.PATCH("/api/bookmarks/sort", controllers.SortBookmarks)
		auth.PUT("/api/bookmarks/:id", controllers.UpdateBookmark)
		auth.PATCH("/api/bookmarks/:id/public", controllers.ToggleBookmarkPublic)
		auth.PATCH("/api/bookmarks/:id/pin", controllers.ToggleBookmarkPin)
		auth.PATCH("/api/bookmarks/:id/nav-visible", controllers.ToggleBookmarkNavVisible)
		auth.PATCH("/api/bookmarks/:id/favicon", controllers.RefreshBookmarkFavicon)
		auth.DELETE("/api/bookmarks/:id", controllers.DeleteBookmark)
		auth.POST("/api/fetch-meta", controllers.FetchBookmarkMeta)

		// Action APIs
		auth.GET("/api/tasks", controllers.ListTasksAPI)
		auth.GET("/api/tasks/daily-counts", controllers.GetTaskDailyCountsAPI)
		auth.GET("/api/tasks/:id", controllers.GetTaskAPI)
		auth.POST("/api/tasks", controllers.CreateTaskAPI)
		auth.PUT("/api/tasks/:id", controllers.UpdateTaskAPI)
		auth.PATCH("/api/tasks/:id/done", controllers.UpdateTaskDoneAPI)
		auth.DELETE("/api/tasks/:id", controllers.DeleteTaskAPI)

		// Topic APIs
		auth.GET("/api/topics", controllers.ListTopicsAPI)
		auth.POST("/api/topics", controllers.CreateTopicAPI)
		auth.GET("/api/topics/daily-counts", controllers.GetTopicDailyCountsAPI)
		auth.GET("/api/topics/:id", controllers.GetTopicAPI)
		auth.PUT("/api/topics/:id", controllers.UpdateTopicAPI)
		auth.DELETE("/api/topics/:id", controllers.DeleteTopicAPI)
		auth.PATCH("/api/topics/:id/pin", controllers.ToggleTopicPinAPI)
		auth.POST("/api/topics/:id/summaries", controllers.CreateTopicSummaryAPI)
		auth.PUT("/api/topics/:id/summaries/:summaryId", controllers.UpdateTopicSummaryAPI)
		auth.DELETE("/api/topics/:id/summaries/:summaryId", controllers.DeleteTopicSummaryAPI)
		auth.PATCH("/api/topics/:id/summaries/sort", controllers.SortTopicSummariesAPI)
		auth.POST("/api/topics/:id/resources", controllers.CreateTopicResourceAPI)
		auth.DELETE("/api/topics/:id/resources/:resourceId", controllers.DeleteTopicResourceAPI)
		auth.PATCH("/api/topics/:id/resources/sort", controllers.SortTopicResourcesAPI)
		auth.GET("/api/topics/:id/comments", controllers.ListTopicCommentsAPI)
		auth.POST("/api/topics/:id/comments", controllers.CreateTopicCommentAPI)
		auth.PUT("/api/topics/:id/comments/:commentId", controllers.UpdateTopicCommentAPI)
		auth.DELETE("/api/topics/:id/comments/:commentId", controllers.DeleteTopicCommentAPI)

		// Linkding 兼容 API（浏览器插件用）
		auth.POST("/api/bookmarks/", controllers.CreateBookmarkCompat)
		auth.GET("/api/bookmarks/", controllers.ListBookmarksCompat)
		auth.GET("/api/bookmarks/check/", controllers.CheckBookmarkCompat)
		auth.GET("/api/tags/", controllers.ListTagsCompat)
		auth.GET("/api/bookmarks/:id/", controllers.GetBookmarkCompat)
		auth.PATCH("/api/bookmarks/:id/", controllers.UpdateBookmarkCompat)
		auth.PUT("/api/bookmarks/:id/", controllers.UpdateBookmarkCompat)
		auth.DELETE("/api/bookmarks/:id/", controllers.DeleteBookmarkCompat)

		// API Token 管理
		auth.GET("/api/api-tokens", controllers.ListApiTokens)
		auth.POST("/api/api-tokens", controllers.CreateApiToken)
		auth.DELETE("/api/api-tokens/:id", controllers.DeleteApiToken)

		// Search API
		auth.GET("/api/search", controllers.SearchAPI)

		// Upload APIs
		auth.POST("/api/uploads", controllers.UploadImage)
		auth.GET("/api/uploads", controllers.ListUploads)
		auth.GET("/api/uploads/by-hash/:hash", controllers.GetUploadByHash)
		auth.DELETE("/api/uploads/:id", controllers.DeleteUpload)

		// Label APIs
		auth.GET("/api/labels", controllers.ListLabels)
		auth.GET("/api/labels/recommendations", controllers.ListRecommendedLabels)
		auth.GET("/api/labels/recommendation-settings", controllers.GetTagRecommendationSettings)
		auth.PUT("/api/labels/recommendation-settings", controllers.UpdateTagRecommendationSettings)
		auth.POST("/api/labels", controllers.CreateLabel)
		auth.DELETE("/api/labels/unused", controllers.DeleteUnusedLabels)
		auth.PUT("/api/labels/:id", controllers.UpdateLabel)
		auth.DELETE("/api/labels/:id", controllers.DeleteLabel)
		auth.POST("/api/labels/bindlist", controllers.BindLabels)
		auth.DELETE("/api/labels/bindlist", controllers.UnbindLabels)
		auth.GET("/api/labels/:id/detail", controllers.GetLabelDetail)
		auth.POST("/api/labels/merge", controllers.MergeLabels)
		auth.GET("/api/labels/resource/:type/:id", controllers.GetResourceLabels)
		auth.PUT("/api/labels/resource/:type/:id", controllers.UpdateResourceLabels)

		// Share APIs (auth required)
		auth.POST("/api/shares", controllers.PublishShare)
		auth.DELETE("/api/shares/:type/:id", controllers.UnpublishShare)
		auth.GET("/api/shares/status", controllers.GetShareStatus)
		auth.PATCH("/api/shares/:type/:id/pin", controllers.ToggleSharePin)
		auth.PATCH("/api/shares/:type/:id/edit-token", controllers.ManageEditToken)

		// Trash APIs
		auth.GET("/api/trash", controllers.ListTrashAPI)
		auth.GET("/api/trash/count", controllers.TrashCountAPI)
		auth.POST("/api/trash/:id/restore", controllers.RestoreTrashAPI)
		auth.DELETE("/api/trash/:id", controllers.PermanentDeleteTrashAPI)
		auth.POST("/api/trash/batch-restore", controllers.BatchRestoreTrashAPI)
		auth.POST("/api/trash/batch-delete", controllers.BatchDeleteTrashAPI)
		auth.DELETE("/api/trash/purge", controllers.PurgeTrashAPI)

		// AI assistant (streaming SSE)
		auth.POST("/api/ai/complete", controllers.AIComplete)
		auth.GET("/api/ai/assistant", controllers.AssistantSessionAPI)
		auth.POST("/api/ai/assistant/chat", controllers.AssistantChatAPI)
		auth.POST("/api/ai/assistant/reset", controllers.AssistantResetAPI)
		auth.POST("/api/ai/assistant/drafts/:id", controllers.AssistantResolveAPI)

		// Admin APIs
		admin := auth.Group("/api/admin")
		admin.Use(middleware.AdminRequired())
		{
			admin.GET("/members", controllers.ListMembers)
			admin.PUT("/members/:id/approve", controllers.ApproveMember)
			admin.PUT("/members/:id/reject", controllers.RejectMember)
			admin.PUT("/members/:id/role", controllers.SetMemberRole)
			admin.PUT("/members/:id/reset-password", controllers.ResetMemberPassword)
			admin.GET("/friend-links", controllers.ListFriendLinks)
			admin.PUT("/friend-links", controllers.ReplaceFriendLinks)
			admin.GET("/settings", controllers.GetSettings)
			admin.PUT("/settings", controllers.UpdateSettings)
			admin.POST("/settings/ai/reset", controllers.ResetAISetting)
			admin.POST("/settings/ai/test", controllers.TestAIConnection)
			admin.POST("/settings/mail/test", controllers.TestAdminMail)
			admin.GET("/webdav/backup", controllers.BackupLocalDAVDatabase)
			admin.GET("/mail/status", controllers.GetAdminMailStatus)
			admin.GET("/share-comments", controllers.ListAdminShareComments)
			admin.POST("/share-comments/delete", controllers.HardDeleteAdminShareComments)

			assets := admin.Group("/assets")
			{
				assets.GET("/credentials", controllers.ListAssetCredentials)
				assets.POST("/credentials", controllers.CreateAssetCredential)
				assets.PUT("/credentials/:id", controllers.UpdateAssetCredential)
				assets.DELETE("/credentials/:id", controllers.DeleteAssetCredential)

				assets.GET("/ssh-hosts", controllers.ListAssetSSHHosts)
				assets.POST("/ssh-hosts", controllers.CreateAssetSSHHost)
				assets.POST("/ssh-hosts/:id/test", controllers.TestAssetSSHHost)
				assets.GET("/ssh-hosts/:id/terminal", controllers.AssetSSHTerminal)
				assets.PUT("/ssh-hosts/:id", controllers.UpdateAssetSSHHost)
				assets.DELETE("/ssh-hosts/:id", controllers.DeleteAssetSSHHost)

				assets.GET("/ssh-hosts/:id/files", controllers.ListAssetFiles)
				assets.GET("/ssh-hosts/:id/files/download", controllers.DownloadAssetFile)
				assets.GET("/ssh-hosts/:id/files/preview", controllers.PreviewAssetFile)
				assets.GET("/ssh-hosts/:id/files/content", controllers.ReadAssetFileContent)
				assets.PUT("/ssh-hosts/:id/files/content", controllers.SaveAssetFileContent)
				assets.POST("/ssh-hosts/:id/files/upload", controllers.UploadAssetFile)
				assets.POST("/ssh-hosts/:id/files/mkdir", controllers.MkdirAssetFile)
				assets.POST("/ssh-hosts/:id/files/rename", controllers.RenameAssetFile)
				assets.POST("/ssh-hosts/:id/files/copy", controllers.CopyAssetFile)
				assets.POST("/ssh-hosts/:id/files/chmod", controllers.ChmodAssetFile)
				assets.DELETE("/ssh-hosts/:id/files", controllers.DeleteAssetFile)

				assets.GET("/webdav-servers", controllers.ListAssetWebDAVServers)
				assets.POST("/webdav-servers", controllers.CreateAssetWebDAVServer)
				assets.POST("/webdav-servers/:id/test", controllers.TestAssetWebDAVServer)
				assets.PUT("/webdav-servers/:id", controllers.UpdateAssetWebDAVServer)
				assets.DELETE("/webdav-servers/:id", controllers.DeleteAssetWebDAVServer)
				assets.GET("/webdav-servers/:id/files", controllers.ListAssetWebDAVFiles)
				assets.GET("/webdav-servers/:id/files/download", controllers.DownloadAssetWebDAVFile)
				assets.GET("/webdav-servers/:id/files/preview", controllers.PreviewAssetWebDAVFile)
				assets.GET("/webdav-servers/:id/files/content", controllers.ReadAssetWebDAVFileContent)
				assets.PUT("/webdav-servers/:id/files/content", controllers.SaveAssetWebDAVFileContent)
				assets.POST("/webdav-servers/:id/files/upload", controllers.UploadAssetWebDAVFile)
				assets.POST("/webdav-servers/:id/files/mkdir", controllers.MkdirAssetWebDAVFile)
				assets.POST("/webdav-servers/:id/files/rename", controllers.RenameAssetWebDAVFile)
				assets.POST("/webdav-servers/:id/files/copy", controllers.CopyAssetWebDAVFile)
				assets.DELETE("/webdav-servers/:id/files", controllers.DeleteAssetWebDAVFile)

				assets.GET("/ssh-hosts/:id/docker-containers", controllers.ListAssetDockerContainers)
				assets.POST("/ssh-hosts/:id/docker-containers", controllers.CreateAssetDockerContainer)
				assets.POST("/ssh-hosts/:id/docker/:resource/prune", controllers.PruneAssetDocker)
				assets.GET("/ssh-hosts/:id/docker-networks", controllers.ListAssetDockerNetworks)
				assets.POST("/ssh-hosts/:id/docker-networks", controllers.CreateAssetDockerNetwork)
				assets.DELETE("/ssh-hosts/:id/docker-networks/:network", controllers.DeleteAssetDockerNetwork)
				assets.GET("/ssh-hosts/:id/docker-volumes", controllers.ListAssetDockerVolumes)
				assets.POST("/ssh-hosts/:id/docker-volumes", controllers.CreateAssetDockerVolume)
				assets.DELETE("/ssh-hosts/:id/docker-volumes/:volume", controllers.DeleteAssetDockerVolume)
				assets.GET("/ssh-hosts/:id/docker-images", controllers.ListAssetDockerImages)
				assets.POST("/ssh-hosts/:id/docker-images", controllers.PullAssetDockerImage)
				assets.DELETE("/ssh-hosts/:id/docker-images/*image", controllers.DeleteAssetDockerImage)
				assets.POST("/ssh-hosts/:id/docker-containers/:container/inspect", controllers.InspectAssetDockerContainer)
				assets.POST("/ssh-hosts/:id/docker-containers/:container/:action", controllers.OperateAssetDockerContainer)
				assets.GET("/ssh-hosts/:id/docker-containers/:container/logs", controllers.AssetDockerLogs)
				assets.GET("/ssh-hosts/:id/docker-containers/:container/logs/stream", controllers.AssetDockerLogStream)
				assets.GET("/ssh-hosts/:id/docker-containers/:container/terminal", controllers.AssetDockerTerminal)

				assets.GET("/settings", controllers.GetAssetSettings)
				assets.PUT("/settings", controllers.UpdateAssetSettings)
			}

			// Export/Import APIs
			admin.GET("/export", controllers.ExportData)
			admin.POST("/import/check", controllers.ImportCheck)
			admin.POST("/import/execute", controllers.ImportExecute)
			admin.POST("/bookmarks/import", controllers.ImportBookmarkHTML)

			// Dashboard APIs
			admin.GET("/dashboard/stats", controllers.GetDashboardStats)
			admin.GET("/dashboard/trend", controllers.GetDashboardTrend)
			admin.GET("/dashboard/logs", controllers.GetDashboardLogs)

			// Bookmark cleanup APIs
			admin.POST("/bookmarks/cleanup/start", controllers.StartBookmarkCleanup)
			admin.GET("/bookmarks/cleanup/status", controllers.GetCleanupStatus)
			admin.POST("/bookmarks/cleanup/cancel", controllers.CancelCleanup)
		}

		// Admin pages
		adminPages := auth.Group("/")
		adminPages.Use(middleware.AdminRequired())
		{
			adminPages.GET("/admin/assets", controllers.AssetsPage)
			adminPages.GET("/admin/assets/ssh-hosts/:id/docker", controllers.AssetDockerHostPage)
			adminPages.GET("/admin/assets/ssh-hosts/:id/files", controllers.AssetFilesHostPage)
			adminPages.GET("/admin/assets/webdav-servers/:id/files", controllers.AssetWebDAVFilesPage)
			adminPages.GET("/admin/system", controllers.AdminSystemPage)
			adminPages.GET("/admin/dashboard", controllers.DashboardPage)
		}
	}

	// NoRoute: redirect to /shares (unauthenticated) or /books (authenticated)
	r.NoRoute(middleware.OptionalAuth(), func(c *gin.Context) {
		if middleware.GetMemberID(c) > 0 {
			c.Redirect(http.StatusFound, "/")
		} else {
			c.Redirect(http.StatusFound, "/shares")
		}
	})

	return r
}
