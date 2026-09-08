package main

import (
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"mime"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"

	"bookstark/models"
)

const (
	defaultFileMaxSize = int64(32 << 20)
	defaultQuotaSize   = int64(2 << 30)
)

type assetFile struct {
	localPath    string
	relativePath string
}

func main() {
	var (
		dbPath       = flag.String("db", "", "path to the BookStark WebDAV database")
		sourceDir    = flag.String("source", "", "directory containing versioned public assets")
		memberID     = flag.Int64("member-id", 1, "BookStark member ID that owns the files")
		storagePath  = flag.String("storage-prefix", "", "WebDAV storage directory")
		publicPath   = flag.String("public-prefix", "", "public resource directory")
		fileMaxBytes = flag.Int64("file-max-bytes", defaultFileMaxSize, "maximum size of one file")
		quotaBytes   = flag.Int64("quota-bytes", defaultQuotaSize, "owner quota used for validation")
	)
	flag.Parse()

	if strings.TrimSpace(*dbPath) == "" || strings.TrimSpace(*sourceDir) == "" || *memberID <= 0 {
		flag.Usage()
		os.Exit(2)
	}
	if err := publishAssets(*dbPath, *sourceDir, *memberID, *storagePath, *publicPath, *fileMaxBytes, *quotaBytes); err != nil {
		fmt.Fprintln(os.Stderr, "publish WebDAV assets:", err)
		os.Exit(1)
	}
}

func publishAssets(dbPath, sourceDir string, memberID int64, storagePrefix, publicPrefix string, fileMaxBytes, quotaBytes int64) error {
	if err := models.InitWebDAVDB(dbPath); err != nil {
		return fmt.Errorf("initialize WebDAV database: %w", err)
	}
	defer func() {
		if models.WebDAVDB != nil {
			_ = models.WebDAVDB.Close()
			models.WebDAVDB = nil
		}
	}()

	storagePrefix = strings.Trim(storagePrefix, "/")
	publicPrefix = strings.Trim(publicPrefix, "/")
	if storagePrefix == "" || publicPrefix == "" {
		return errors.New("storage and public prefixes are required")
	}

	files, err := collectFiles(sourceDir)
	if err != nil {
		return err
	}
	if len(files) == 0 {
		return errors.New("source directory contains no files")
	}

	createdDirectories := make(map[string]bool)
	for index, asset := range files {
		storageName := path.Join(storagePrefix, asset.relativePath)
		parent := path.Dir(storageName)
		if !createdDirectories[parent] {
			if err := ensureDirectories(memberID, parent); err != nil {
				return err
			}
			createdDirectories[parent] = true
		}

		file, err := os.Open(asset.localPath)
		if err != nil {
			return fmt.Errorf("open %s: %w", asset.relativePath, err)
		}
		node, deduplicated, putErr := models.PutDAVFile(
			memberID,
			storageName,
			contentType(asset.relativePath),
			file,
			fileMaxBytes,
			quotaBytes,
		)
		closeErr := file.Close()
		if putErr != nil {
			return fmt.Errorf("upload %s: %w", asset.relativePath, putErr)
		}
		if closeErr != nil {
			return fmt.Errorf("close %s: %w", asset.relativePath, closeErr)
		}
		if _, err := models.CreateOrUpdateDAVPublicAsset(memberID, node.NodeID, path.Join(publicPrefix, asset.relativePath)); err != nil {
			return fmt.Errorf("publish %s: %w", asset.relativePath, err)
		}

		action := "stored"
		if deduplicated {
			action = "deduplicated"
		}
		fmt.Printf("[%3d/%3d] %-12s %9d  %s\n", index+1, len(files), action, node.Size, asset.relativePath)
	}
	fmt.Printf("published %d assets under /dav-public/<account>/%s/\n", len(files), publicPrefix)
	return nil
}

func collectFiles(sourceDir string) ([]assetFile, error) {
	root, err := filepath.Abs(sourceDir)
	if err != nil {
		return nil, fmt.Errorf("resolve source directory: %w", err)
	}
	files := make([]assetFile, 0, 64)
	err = filepath.WalkDir(root, func(localPath string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		relativePath, err := filepath.Rel(root, localPath)
		if err != nil {
			return err
		}
		files = append(files, assetFile{
			localPath:    localPath,
			relativePath: filepath.ToSlash(relativePath),
		})
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("walk source directory: %w", err)
	}
	sort.Slice(files, func(i, j int) bool {
		return files[i].relativePath < files[j].relativePath
	})
	return files, nil
}

func contentType(name string) string {
	lowerName := strings.ToLower(name)
	switch {
	case strings.HasSuffix(lowerName, ".mjs"), strings.HasSuffix(lowerName, ".js"):
		return "text/javascript; charset=utf-8"
	case strings.HasSuffix(lowerName, ".wasm"):
		return "application/wasm"
	case strings.HasSuffix(lowerName, ".otf"):
		return "font/otf"
	case strings.HasSuffix(lowerName, ".ttf"):
		return "font/ttf"
	case strings.HasSuffix(lowerName, ".woff"):
		return "font/woff"
	case strings.HasSuffix(lowerName, ".woff2"):
		return "font/woff2"
	case strings.HasSuffix(lowerName, ".bcmap"):
		return "application/octet-stream"
	case strings.HasSuffix(lowerName, ".traineddata.gz"), strings.HasSuffix(lowerName, ".gz"):
		return "application/gzip"
	case strings.HasSuffix(lowerName, ".md"), strings.HasSuffix(lowerName, ".txt"):
		return "text/plain; charset=utf-8"
	case strings.HasSuffix(lowerName, ".json"):
		return "application/json; charset=utf-8"
	}
	if detected := mime.TypeByExtension(filepath.Ext(lowerName)); detected != "" {
		return detected
	}
	return "application/octet-stream"
}

func ensureDirectories(memberID int64, value string) error {
	if _, err := models.EnsureDAVRoot(memberID); err != nil {
		return fmt.Errorf("ensure WebDAV root: %w", err)
	}
	current := ""
	for _, segment := range strings.Split(value, "/") {
		if segment == "" || segment == "." {
			continue
		}
		current = path.Join(current, segment)
		node, err := models.GetDAVNode(memberID, current)
		switch {
		case err == nil && node.IsDir:
			continue
		case err == nil:
			return fmt.Errorf("%s exists and is not a directory", current)
		case errors.Is(err, models.ErrDAVNotFound):
			if _, err := models.CreateDAVDirectory(memberID, current); err != nil && !errors.Is(err, models.ErrDAVAlreadyExists) {
				return fmt.Errorf("create directory %s: %w", current, err)
			}
		default:
			return fmt.Errorf("read directory %s: %w", current, err)
		}
	}
	return nil
}
