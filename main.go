package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"

	"bookstark/conf"
	"bookstark/models"
	"bookstark/routers"
	"bookstark/services"
)

var (
	buildTime string
	gitCommit string
	goVersion string
	assetHash string
)

func main() {
	// Containers and process supervisors collect application logs from stdout.
	log.SetOutput(os.Stdout)

	// In embed mode, wire up embedded FS and load config from it
	if EmbedFS.ConfFS != nil {
		routers.EmbedFS.StaticFS = EmbedFS.StaticFS
		routers.EmbedFS.TemplateFS = EmbedFS.TemplateFS
		routers.EmbedFS.ConfFS = EmbedFS.ConfFS

		if err := conf.LoadFS(EmbedFS.ConfFS, "app.conf"); err != nil {
			log.Printf("config from embed not found, using defaults: %v", err)
			conf.LoadDefaults()
		}
	} else {
		if err := conf.Load("conf/app.conf"); err != nil {
			log.Printf("conf/app.conf not found, using defaults: %v", err)
			conf.LoadDefaults()
		}
	}

	// Command line flags override config file + env vars
	port := flag.String("port", conf.App.Port, "服务端口")
	mode := flag.String("mode", conf.App.Mode, "运行模式: debug/release")
	dbPath := flag.String("db", conf.App.DBPath, "数据库路径")
	webDAVDBPath := flag.String("webdav-db", conf.App.WebDAVDBPath, "WebDAV 文件数据库路径")
	jwtSecret := flag.String("jwt-secret", conf.App.JWTSecret, "JWT 密钥")
	jwtExpire := flag.String("jwt-expire", conf.App.JWTExpire, "JWT 过期时间")
	resetAdminPwd := flag.Bool("reset-admin-password", false, "重置管理员密码为默认值并打印，然后退出")
	flag.Parse()

	conf.App.Port = *port
	conf.App.Mode = *mode
	conf.App.DBPath = *dbPath
	conf.App.WebDAVDBPath = *webDAVDBPath
	conf.App.JWTSecret = *jwtSecret
	conf.App.JWTExpire = *jwtExpire

	// Set timezone from config/env (TZ env var takes priority)
	if conf.App.Timezone != "" {
		os.Setenv("TZ", conf.App.Timezone)
	}

	if err := models.InitDB(conf.App.DBPath); err != nil {
		log.Fatalf("init db: %v", err)
	}
	if err := models.InitWebDAVDB(conf.App.WebDAVDBPath); err != nil {
		log.Fatalf("init webdav db: %v", err)
	}
	if err := models.InitShareCommentDB(); err != nil {
		log.Fatalf("init share comments db: %v", err)
	}
	// 把内置 AI 默认 prompt 一次性 backfill 到 settings（仅当对应行为空），
	// 让 admin 在设置页能直接看到并修改默认文案。已 backfill 后不会再覆盖。
	if err := models.BackfillAIDefaults(); err != nil {
		log.Printf("backfill ai defaults: %v", err)
	}

	// Handle -reset-admin-password: reset and print, then exit
	if *resetAdminPwd {
		m, err := models.GetMemberByAccount(conf.App.AdminAccount)
		if err != nil {
			log.Fatalf("admin account %q not found: %v", conf.App.AdminAccount, err)
		}
		newPwd := conf.App.AdminPassword
		if err := models.UpdateMemberPassword(m.MemberID, newPwd); err != nil {
			log.Fatalf("reset password failed: %v", err)
		}
		fmt.Printf("Admin password reset to: %s\n", newPwd)
		return
	}

	// Set asset version for cache busting (content hash from build.py, fallback to commit/timestamp)
	assetVer := assetHash
	if assetVer == "" {
		assetVer = gitCommit
	}
	if assetVer == "" {
		assetVer = buildTime
	}
	if assetVer == "" {
		assetVer = "dev"
	}
	conf.App.AssetVersion = assetVer
	conf.App.BuildTime = buildTime
	conf.App.GitCommit = gitCommit

	// Load per-file asset hashes for template ?v= cache busting
	if EmbedFS.StaticFS != nil {
		conf.LoadAssetHashes(EmbedFS.StaticFS, "asset-hashes.json")
	} else {
		conf.LoadAssetHashesDisk("static/asset-hashes.json")
	}

	r := routers.Setup()
	notificationService := services.StartNotificationService()
	defer notificationService.Stop()

	addr := fmt.Sprintf(":%s", conf.App.Port)
	log.Printf("BookStark %s (commit: %s, go: %s, built: %s)", "dev", gitCommit, goVersion, buildTime)
	log.Printf("Starting on %s (mode: %s)", addr, conf.App.Mode)
	srv := &http.Server{
		Addr:    addr,
		Handler: headMethodFallback(r),
	}
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("start server: %v", err)
	}
}

// headMethodFallback wraps a handler so that HEAD requests are routed
// to GET handlers. Gin's router does not fall back HEAD→GET automatically,
// causing HEAD to hit NoRoute and get redirected.
func headMethodFallback(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodHead {
			r.Method = http.MethodGet
			h.ServeHTTP(&headResponseWriter{ResponseWriter: w}, r)
			return
		}
		h.ServeHTTP(w, r)
	})
}

type headResponseWriter struct {
	http.ResponseWriter
}

func (w *headResponseWriter) Write(b []byte) (int, error) {
	return len(b), nil
}
