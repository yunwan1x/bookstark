package conf

import (
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/goccy/go-yaml"
)

type config struct {
	Port          string `yaml:"port"`
	Mode          string `yaml:"mode"`
	DBPath        string `yaml:"db_path"`
	JWTSecret     string `yaml:"jwt_secret"`
	JWTExpire     string `yaml:"jwt_expire"`
	AdminAccount  string `yaml:"admin_account"`
	AdminPassword string `yaml:"admin_password"`
	Timezone      string `yaml:"timezone"`
	TLSCertFile   string `yaml:"tls_cert_file"`
	TLSKeyFile    string `yaml:"tls_key_file"`
	AssetSecret   string `yaml:"asset_secret"`
	WebDAVDBPath  string `yaml:"webdav_db_path"`
}

var App Conf

type Conf struct {
	Port          string
	Mode          string
	DBPath        string
	JWTSecret     string
	JWTExpire     string
	AdminAccount  string
	AdminPassword string
	Timezone      string
	AssetVersion  string
	BuildTime     string
	GitCommit     string
	TLSCertFile   string
	TLSKeyFile    string
	AssetSecret   string
	WebDAVDBPath  string
}

var (
	assetHashes     map[string]string
	assetHashesOnce sync.Once
)

// LoadAssetHashes loads the asset-hashes.json file (from embedded FS).
// In dev mode, call LoadAssetHashesDisk instead.
func LoadAssetHashes(fsys fs.FS, path string) {
	if fsys == nil {
		return
	}
	data, err := fs.ReadFile(fsys, path)
	if err != nil {
		return
	}
	var m map[string]string
	if err := json.Unmarshal(data, &m); err != nil {
		return
	}
	assetHashes = m
}

// LoadAssetHashesDisk loads the asset-hashes.json file from disk (dev mode).
func LoadAssetHashesDisk(path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	var m map[string]string
	if err := json.Unmarshal(data, &m); err != nil {
		return
	}
	assetHashes = m
}

// AssetVer returns the content hash for a given static file path.
// Falls back to AssetVersion if no hash is found.
func AssetVer(path string) string {
	assetHashesOnce.Do(func() {
		if assetHashes == nil {
			// Try loading from disk (dev mode)
			data, err := os.ReadFile("static/asset-hashes.json")
			if err == nil {
				var m map[string]string
				if json.Unmarshal(data, &m) == nil {
					assetHashes = m
				}
			}
		}
	})
	// Normalize: strip leading /
	key := strings.TrimPrefix(path, "/")
	if h, ok := assetHashes[key]; ok {
		return h
	}
	return App.AssetVersion
}

func Load(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return loadFromBytes(data)
}

func LoadFS(fsys fs.FS, path string) error {
	data, err := fs.ReadFile(fsys, path)
	if err != nil {
		return err
	}
	return loadFromBytes(data)
}

func loadFromBytes(data []byte) error {
	var cfg config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return err
	}
	applyConfig(cfg)
	return nil
}

// LoadDefaults initializes config from env vars and defaults only, no config file needed.
func LoadDefaults() {
	applyConfig(config{})
}

func applyConfig(cfg config) {
	dbPath := getEnv("DB_PATH", cfg.DBPath, "./bookstark.db")
	webDAVDefaultPath := "./bookstark-webdav.db"
	if dbPath != ":memory:" && !strings.HasPrefix(dbPath, "file:") {
		webDAVDefaultPath = filepath.Join(filepath.Dir(dbPath), "bookstark-webdav.db")
	}
	App = Conf{
		Port:          getEnv("PORT", cfg.Port, "8089"),
		Mode:          getEnv("MODE", cfg.Mode, "release"),
		DBPath:        dbPath,
		JWTSecret:     getEnv("JWT_SECRET", cfg.JWTSecret, "bookstark-secret"),
		JWTExpire:     getEnv("JWT_EXPIRE", cfg.JWTExpire, "168h"),
		AdminAccount:  getEnv("ADMIN_ACCOUNT", cfg.AdminAccount, "admin"),
		AdminPassword: getEnv("ADMIN_PASSWORD", cfg.AdminPassword, "admin"),
		Timezone:      getEnv("TZ", cfg.Timezone, ""),
		TLSCertFile:   getEnv("TLS_CERT_FILE", cfg.TLSCertFile, ""),
		TLSKeyFile:    getEnv("TLS_KEY_FILE", cfg.TLSKeyFile, ""),
		AssetSecret:   getEnv("BOOKSTARK_ASSET_SECRET", cfg.AssetSecret, ""),
		WebDAVDBPath:  getEnv("WEBDAV_DB_PATH", cfg.WebDAVDBPath, webDAVDefaultPath),
	}
}

func getEnv(key, yamlVal, defaultVal string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	if yamlVal != "" {
		return yamlVal
	}
	return defaultVal
}
