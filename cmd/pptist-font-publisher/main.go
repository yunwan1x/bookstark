package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"

	"bookstark/models"
)

const (
	pptistCommit       = "2bfd88fef0d721b24b3a97bd5e3c8a36cabff0c6"
	defaultFontPrefix  = "pptist/" + pptistCommit + "/fonts"
	defaultFileMaxSize = int64(20 << 20)
	defaultQuotaSize   = int64(1 << 30)
)

func main() {
	var (
		dbPath       = flag.String("db", "", "path to the BookStark WebDAV database")
		sourceDir    = flag.String("source", "", "directory containing PPTist .woff2 files")
		memberID     = flag.Int64("member-id", 1, "BookStark member ID that owns the files")
		storagePath  = flag.String("storage-prefix", defaultFontPrefix, "WebDAV storage directory")
		publicPath   = flag.String("public-prefix", defaultFontPrefix, "public resource directory")
		fileMaxBytes = flag.Int64("file-max-bytes", defaultFileMaxSize, "maximum font file size")
		quotaBytes   = flag.Int64("quota-bytes", defaultQuotaSize, "owner quota used for validation")
	)
	flag.Parse()

	if strings.TrimSpace(*dbPath) == "" || strings.TrimSpace(*sourceDir) == "" || *memberID <= 0 {
		flag.Usage()
		os.Exit(2)
	}
	if err := publishFonts(*dbPath, *sourceDir, *memberID, *storagePath, *publicPath, *fileMaxBytes, *quotaBytes); err != nil {
		fmt.Fprintln(os.Stderr, "publish PPTist fonts:", err)
		os.Exit(1)
	}
}

func publishFonts(dbPath, sourceDir string, memberID int64, storagePrefix, publicPrefix string, fileMaxBytes, quotaBytes int64) error {
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
	if err := ensureDirectories(memberID, storagePrefix); err != nil {
		return err
	}

	entries, err := os.ReadDir(sourceDir)
	if err != nil {
		return fmt.Errorf("read source directory: %w", err)
	}
	fontNames := make([]string, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() && strings.EqualFold(filepath.Ext(entry.Name()), ".woff2") {
			fontNames = append(fontNames, entry.Name())
		}
	}
	sort.Strings(fontNames)
	if len(fontNames) == 0 {
		return errors.New("source directory contains no .woff2 fonts")
	}

	for _, name := range fontNames {
		localPath := filepath.Join(sourceDir, name)
		file, err := os.Open(localPath)
		if err != nil {
			return fmt.Errorf("open %s: %w", name, err)
		}
		node, deduplicated, putErr := models.PutDAVFile(
			memberID,
			path.Join(storagePrefix, name),
			"font/woff2",
			file,
			fileMaxBytes,
			quotaBytes,
		)
		closeErr := file.Close()
		if putErr != nil {
			return fmt.Errorf("upload %s: %w", name, putErr)
		}
		if closeErr != nil {
			return fmt.Errorf("close %s: %w", name, closeErr)
		}
		if _, err := models.CreateOrUpdateDAVPublicAsset(memberID, node.NodeID, path.Join(publicPrefix, name)); err != nil {
			return fmt.Errorf("publish %s: %w", name, err)
		}
		action := "stored"
		if deduplicated {
			action = "deduplicated"
		}
		fmt.Printf("%-12s %8d  %s\n", action, node.Size, name)
	}
	fmt.Printf("published %d fonts under /dav-public/<account>/%s/\n", len(fontNames), publicPrefix)
	return nil
}

func ensureDirectories(memberID int64, value string) error {
	if _, err := models.EnsureDAVRoot(memberID); err != nil {
		return fmt.Errorf("ensure WebDAV root: %w", err)
	}
	current := ""
	for _, segment := range strings.Split(value, "/") {
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
