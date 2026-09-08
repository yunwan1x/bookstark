package models

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func setupWebDAVStoreTest(t *testing.T) {
	t.Helper()
	oldDB := WebDAVDB
	if err := InitWebDAVDB(filepath.Join(t.TempDir(), "webdav.db")); err != nil {
		t.Fatalf("InitWebDAVDB() error = %v", err)
	}
	t.Cleanup(func() {
		if WebDAVDB != nil {
			_ = WebDAVDB.Close()
		}
		WebDAVDB = oldDB
	})
}

func TestDAVStoreDeduplicatesAcrossMembersAndReleasesLastReference(t *testing.T) {
	setupWebDAVStoreTest(t)
	content := []byte(strings.Repeat("bookstark webdav content\n", 800))
	if _, err := CreateDAVDirectory(1, "docs"); err != nil {
		t.Fatalf("CreateDAVDirectory(member 1) error = %v", err)
	}
	if _, err := CreateDAVDirectory(2, "docs"); err != nil {
		t.Fatalf("CreateDAVDirectory(member 2) error = %v", err)
	}
	first, deduplicated, err := PutDAVFile(1, "docs/readme.txt", "text/plain", bytes.NewReader(content), 1<<20, 1<<20)
	if err != nil || deduplicated {
		t.Fatalf("first PutDAVFile() = (%v, %v), error %v", first, deduplicated, err)
	}
	second, deduplicated, err := PutDAVFile(2, "docs/copy.txt", "text/plain", bytes.NewReader(content), 1<<20, 1<<20)
	if err != nil || !deduplicated {
		t.Fatalf("second PutDAVFile() = (%v, %v), error %v", second, deduplicated, err)
	}
	if first.BlobID == nil || second.BlobID == nil || *first.BlobID != *second.BlobID {
		t.Fatalf("files do not reference the same blob: %#v %#v", first.BlobID, second.BlobID)
	}
	blob, err := FindDAVBlob(first.ETag, int64(len(content)))
	if err != nil || blob.RefCount != 2 {
		t.Fatalf("deduplicated blob = %#v, error %v", blob, err)
	}
	var compressedChunks int
	if err := WebDAVDB.QueryRow(
		"SELECT COUNT(*) FROM dav_blob_chunks WHERE blob_id=? AND compression=?",
		blob.BlobID, DAVCompressionGzip,
	).Scan(&compressedChunks); err != nil || compressedChunks == 0 {
		t.Fatalf("compressed chunks = %d, error %v", compressedChunks, err)
	}

	if err := DeleteDAVNode(1, "docs/readme.txt", false); err != nil {
		t.Fatalf("DeleteDAVNode(member 1) error = %v", err)
	}
	blob, err = FindDAVBlob(first.ETag, int64(len(content)))
	if err != nil || blob.RefCount != 1 {
		t.Fatalf("blob after first delete = %#v, error %v", blob, err)
	}
	if err := DeleteDAVNode(2, "docs/copy.txt", false); err != nil {
		t.Fatalf("DeleteDAVNode(member 2) error = %v", err)
	}
	if _, err := FindDAVBlob(first.ETag, int64(len(content))); !errors.Is(err, ErrDAVNotFound) {
		t.Fatalf("FindDAVBlob() after last delete error = %v, want ErrDAVNotFound", err)
	}
}

func TestRemoveDAVMemberDataInvalidatesCachedAppPassword(t *testing.T) {
	setupWebDAVStoreTest(t)
	password, err := ResetDAVAppPassword(101)
	if err != nil {
		t.Fatalf("ResetDAVAppPassword() error = %v", err)
	}
	if !VerifyDAVAppPassword(101, password) {
		t.Fatal("VerifyDAVAppPassword() should populate a valid cache entry")
	}
	if err := RemoveDAVMemberData(101); err != nil {
		t.Fatalf("RemoveDAVMemberData() error = %v", err)
	}
	if VerifyDAVAppPassword(101, password) {
		t.Fatal("removed member password remained valid through the authentication cache")
	}
}

func TestDAVAppPasswordAcceptsStandardBcrypt2YHash(t *testing.T) {
	setupWebDAVStoreTest(t)
	const (
		memberID = int64(102)
		secret   = "testpass"
		hash     = "$2y$10$AnONABRW5OA34TUqatp4GeHpyjyO3DeNJnaS//8S.kIUhUgQjWDUK"
	)
	if _, err := WebDAVDB.Exec(`
		INSERT INTO dav_app_credentials(member_id, secret_hash, create_time, modify_time)
		VALUES (?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`, memberID, hash); err != nil {
		t.Fatalf("insert standard bcrypt credential: %v", err)
	}
	if !VerifyDAVAppPassword(memberID, secret) {
		t.Fatal("VerifyDAVAppPassword() rejected a valid standard bcrypt 2y hash")
	}
}

func TestSetDAVAppPasswordReplacesCredentialAndInvalidatesCache(t *testing.T) {
	setupWebDAVStoreTest(t)
	const memberID = int64(103)
	if err := SetDAVAppPassword(memberID, "first-password"); err != nil {
		t.Fatalf("SetDAVAppPassword(first) error = %v", err)
	}
	if !VerifyDAVAppPassword(memberID, "first-password") {
		t.Fatal("first custom password should be valid")
	}
	if err := SetDAVAppPassword(memberID, "second-password"); err != nil {
		t.Fatalf("SetDAVAppPassword(second) error = %v", err)
	}
	if VerifyDAVAppPassword(memberID, "first-password") {
		t.Fatal("replaced custom password remained valid")
	}
	if !VerifyDAVAppPassword(memberID, "second-password") {
		t.Fatal("second custom password should be valid")
	}
}

func TestDAVStoreLinkBlobAndPublicAsset(t *testing.T) {
	setupWebDAVStoreTest(t)
	content := []byte("console.log('public asset');\n")
	if _, err := CreateDAVDirectory(1, "assets"); err != nil {
		t.Fatalf("CreateDAVDirectory() error = %v", err)
	}
	node, _, err := PutDAVFile(1, "assets/app.js", "application/javascript", bytes.NewReader(content), 1<<20, 1<<20)
	if err != nil {
		t.Fatalf("PutDAVFile() error = %v", err)
	}
	if _, err := CreateDAVDirectory(2, "assets"); err != nil {
		t.Fatalf("CreateDAVDirectory(member 2) error = %v", err)
	}
	linked, err := LinkDAVBlob(2, "assets/app.js", *node.BlobID, "application/javascript", 1<<20)
	if err != nil {
		t.Fatalf("LinkDAVBlob() error = %v", err)
	}
	if linked.ETag != node.ETag {
		t.Fatalf("linked etag = %q, want %q", linked.ETag, node.ETag)
	}
	asset, err := CreateOrUpdateDAVPublicAsset(1, node.NodeID, "vendor/app.js")
	if err != nil || asset.PublicPath != "vendor/app.js" {
		t.Fatalf("CreateOrUpdateDAVPublicAsset() = %#v, error %v", asset, err)
	}
	publicNode, blob, err := ResolveDAVPublicAsset(1, "vendor/app.js")
	if err != nil || publicNode.NodeID != node.NodeID {
		t.Fatalf("ResolveDAVPublicAsset() = %#v, error %v", publicNode, err)
	}
	reader, err := OpenDAVBlob(blob)
	if err != nil {
		t.Fatalf("OpenDAVBlob() error = %v", err)
	}
	defer reader.Close()
	got, _ := io.ReadAll(reader)
	if !bytes.Equal(got, content) {
		t.Fatalf("public content = %q, want %q", got, content)
	}
	second, _, err := PutDAVFile(1, "assets/second.js", "application/javascript", strings.NewReader("second"), 1<<20, 1<<20)
	if err != nil {
		t.Fatalf("PutDAVFile(second) error = %v", err)
	}
	if _, err := CreateOrUpdateDAVPublicAsset(1, second.NodeID, "vendor/app.js"); !errors.Is(err, ErrDAVAlreadyExists) {
		t.Fatalf("duplicate public path error = %v, want ErrDAVAlreadyExists", err)
	}
}

func TestDAVStoreQuotaAndCompressionPolicy(t *testing.T) {
	setupWebDAVStoreTest(t)
	if _, err := CreateDAVDirectory(1, "files"); err != nil {
		t.Fatalf("CreateDAVDirectory() error = %v", err)
	}
	if _, _, err := PutDAVFile(1, "files/large.txt", "text/plain", strings.NewReader(strings.Repeat("a", 100)), 50, 1000); !errors.Is(err, ErrDAVFileTooLarge) {
		t.Fatalf("file size error = %v, want ErrDAVFileTooLarge", err)
	}
	if _, _, err := PutDAVFile(1, "files/quota.txt", "text/plain", strings.NewReader(strings.Repeat("a", 100)), 1000, 50); !errors.Is(err, ErrDAVQuotaExceeded) {
		t.Fatalf("quota error = %v, want ErrDAVQuotaExceeded", err)
	}
	if ShouldTryDAVCompression("photo.png", []byte(strings.Repeat("a", 8192))) {
		t.Fatal("PNG should skip compression by extension")
	}
	if ShouldTryDAVCompression("tiny.txt", []byte("tiny")) {
		t.Fatal("small text should skip compression")
	}
	if !ShouldTryDAVCompression("large.css", []byte(strings.Repeat(".a{color:red}", 1024))) {
		t.Fatal("compressible CSS should use compression")
	}
}

func TestNormalizeDAVPathRejectsTraversalAndPreservesSpaces(t *testing.T) {
	for _, value := range []string{"../secret.txt", "docs/../secret.txt", "/docs/../../secret.txt", `docs\\secret.txt`} {
		if _, err := NormalizeDAVPath(value); !errors.Is(err, ErrDAVInvalidPath) {
			t.Fatalf("NormalizeDAVPath(%q) error = %v, want ErrDAVInvalidPath", value, err)
		}
	}
	got, err := NormalizeDAVPath("/docs//./ report final .txt")
	if err != nil {
		t.Fatalf("NormalizeDAVPath() error = %v", err)
	}
	if got != "docs/ report final .txt" {
		t.Fatalf("NormalizeDAVPath() = %q, want preserved spaces", got)
	}
}

func TestDAVStoreSupportsNamesWithSpaces(t *testing.T) {
	setupWebDAVStoreTest(t)
	if _, err := CreateDAVDirectory(1, " project files "); err != nil {
		t.Fatalf("CreateDAVDirectory() error = %v", err)
	}
	if _, _, err := PutDAVFile(1, " project files / report final .txt", "text/plain", strings.NewReader("spaces"), 1<<20, 1<<20); err != nil {
		t.Fatalf("PutDAVFile() error = %v", err)
	}
	node, err := GetDAVNode(1, " project files / report final .txt")
	if err != nil || node.Name != " report final .txt" {
		t.Fatalf("GetDAVNode() = %#v, error %v", node, err)
	}
}

func TestDAVStoreBackupIsReadable(t *testing.T) {
	setupWebDAVStoreTest(t)
	if _, err := CreateDAVDirectory(1, "backup"); err != nil {
		t.Fatalf("CreateDAVDirectory() error = %v", err)
	}
	if _, _, err := PutDAVFile(1, "backup/readme.txt", "text/plain", strings.NewReader("backup content"), 1<<20, 1<<20); err != nil {
		t.Fatalf("PutDAVFile() error = %v", err)
	}
	destination := filepath.Join(t.TempDir(), "backup.db")
	if err := BackupWebDAVDatabase(destination); err != nil {
		t.Fatalf("BackupWebDAVDatabase() error = %v", err)
	}
	oldDB := WebDAVDB
	if err := InitWebDAVDB(destination); err != nil {
		t.Fatalf("open backup error = %v", err)
	}
	node, err := GetDAVNode(1, "backup/readme.txt")
	if err != nil || node.Size != int64(len("backup content")) {
		t.Fatalf("backup node = %#v, error %v", node, err)
	}
	_ = WebDAVDB.Close()
	WebDAVDB = oldDB
}

func TestDAVQuotaUsesCompressedDeduplicatedStorage(t *testing.T) {
	setupWebDAVStoreTest(t)
	if _, err := CreateDAVDirectory(1, "files"); err != nil {
		t.Fatalf("CreateDAVDirectory() error = %v", err)
	}
	content := strings.Repeat("highly compressible content\n", 12000)
	const quota = int64(8 << 10)
	first, _, err := PutDAVFile(1, "files/first.txt", "text/plain", strings.NewReader(content), 1<<20, quota)
	if err != nil {
		t.Fatalf("compressed PutDAVFile() error = %v", err)
	}
	if first.Size <= quota || first.StoredSize > quota {
		t.Fatalf("compressed file size=%d stored=%d quota=%d", first.Size, first.StoredSize, quota)
	}
	usage, err := GetDAVUsage(1, quota)
	if err != nil {
		t.Fatalf("GetDAVUsage() error = %v", err)
	}
	if usage.StoredBytes != first.StoredSize || usage.LogicalBytes != first.Size {
		t.Fatalf("usage after first upload = %#v, file = %#v", usage, first)
	}

	second, deduplicated, err := PutDAVFile(1, "files/second.txt", "text/plain", strings.NewReader(content), 1<<20, quota)
	if err != nil || !deduplicated {
		t.Fatalf("deduplicated PutDAVFile() = (%#v, %v), error %v", second, deduplicated, err)
	}
	usage, err = GetDAVUsage(1, quota)
	if err != nil {
		t.Fatalf("GetDAVUsage(second) error = %v", err)
	}
	if usage.StoredBytes != first.StoredSize || usage.LogicalBytes != first.Size*2 {
		t.Fatalf("deduplicated usage = %#v, first stored size = %d", usage, first.StoredSize)
	}
}

func TestDAVStoreRecursiveDeleteReleasesCopiedReferencesAndPublicAssets(t *testing.T) {
	setupWebDAVStoreTest(t)
	for _, dir := range []string{"source", "source/nested", "copies"} {
		if _, err := CreateDAVDirectory(1, dir); err != nil {
			t.Fatalf("CreateDAVDirectory(%q) error = %v", dir, err)
		}
	}
	content := strings.Repeat("shared recursive content\n", 300)
	source, _, err := PutDAVFile(1, "source/nested/item.txt", "text/plain", strings.NewReader(content), 1<<20, 1<<20)
	if err != nil {
		t.Fatalf("PutDAVFile() error = %v", err)
	}
	if _, err := CreateOrUpdateDAVPublicAsset(1, source.NodeID, "stable/item.txt"); err != nil {
		t.Fatalf("CreateOrUpdateDAVPublicAsset() error = %v", err)
	}
	if err := CopyDAVNode(1, "source", "copies/source-copy", 1<<20); err != nil {
		t.Fatalf("CopyDAVNode() error = %v", err)
	}

	blob, err := FindDAVBlob(source.ETag, int64(len(content)))
	if err != nil || blob.RefCount != 2 {
		t.Fatalf("blob after copy = %#v, error %v", blob, err)
	}
	usage, err := GetDAVUsage(1, 1<<20)
	if err != nil {
		t.Fatalf("GetDAVUsage() error = %v", err)
	}
	if usage.FileCount != 2 || usage.LogicalBytes != int64(len(content)*2) ||
		usage.DeduplicatedBytes != int64(len(content)) {
		t.Fatalf("usage after copy = %#v", usage)
	}

	if err := DeleteDAVNode(1, "source", true); err != nil {
		t.Fatalf("DeleteDAVNode(source) error = %v", err)
	}
	if _, _, err := ResolveDAVPublicAsset(1, "stable/item.txt"); !errors.Is(err, ErrDAVNotFound) {
		t.Fatalf("public asset after source delete error = %v, want ErrDAVNotFound", err)
	}
	blob, err = FindDAVBlob(source.ETag, int64(len(content)))
	if err != nil || blob.RefCount != 1 {
		t.Fatalf("blob after source delete = %#v, error %v", blob, err)
	}
	if err := DeleteDAVNode(1, "copies", true); err != nil {
		t.Fatalf("DeleteDAVNode(copies) error = %v", err)
	}
	if _, err := FindDAVBlob(source.ETag, int64(len(content))); !errors.Is(err, ErrDAVNotFound) {
		t.Fatalf("blob after last recursive delete error = %v, want ErrDAVNotFound", err)
	}
}

func TestDAVStoreRenameKeepsPublicPathAndFailedOverwriteKeepsContent(t *testing.T) {
	setupWebDAVStoreTest(t)
	if _, err := CreateDAVDirectory(1, "docs"); err != nil {
		t.Fatalf("CreateDAVDirectory() error = %v", err)
	}
	original := "original"
	node, _, err := PutDAVFile(1, "docs/original.txt", "text/plain", strings.NewReader(original), 1<<20, 1<<20)
	if err != nil {
		t.Fatalf("PutDAVFile() error = %v", err)
	}
	if _, err := CreateOrUpdateDAVPublicAsset(1, node.NodeID, "fixed/readme.txt"); err != nil {
		t.Fatalf("CreateOrUpdateDAVPublicAsset() error = %v", err)
	}
	if err := RenameDAVNode(1, "docs/original.txt", "docs/renamed.txt"); err != nil {
		t.Fatalf("RenameDAVNode() error = %v", err)
	}
	publicNode, _, err := ResolveDAVPublicAsset(1, "fixed/readme.txt")
	if err != nil || publicNode.NodeID != node.NodeID {
		t.Fatalf("public asset after rename = %#v, error %v", publicNode, err)
	}

	if _, _, err := PutDAVFile(1, "docs/renamed.txt", "text/plain", strings.NewReader(strings.Repeat("x", 40)), 1<<20, 10); !errors.Is(err, ErrDAVQuotaExceeded) {
		t.Fatalf("failed overwrite error = %v, want ErrDAVQuotaExceeded", err)
	}
	_, _, reader, err := ReadDAVFile(1, "docs/renamed.txt")
	if err != nil {
		t.Fatalf("ReadDAVFile() error = %v", err)
	}
	got, _ := io.ReadAll(reader)
	_ = reader.Close()
	if string(got) != original {
		t.Fatalf("content after failed overwrite = %q, want %q", got, original)
	}
}

func TestDAVStoreRejectsFileAsCopyParentAndIsolatesMembers(t *testing.T) {
	setupWebDAVStoreTest(t)
	for _, memberID := range []int64{1, 2} {
		if _, err := CreateDAVDirectory(memberID, "docs"); err != nil {
			t.Fatalf("CreateDAVDirectory(member %d) error = %v", memberID, err)
		}
	}
	memberOne, _, err := PutDAVFile(1, "docs/item.txt", "text/plain", strings.NewReader("member one"), 1<<20, 1<<20)
	if err != nil {
		t.Fatalf("PutDAVFile(member 1) error = %v", err)
	}
	if _, _, err := PutDAVFile(2, "docs/item.txt", "text/plain", strings.NewReader("member two"), 1<<20, 1<<20); err != nil {
		t.Fatalf("PutDAVFile(member 2) error = %v", err)
	}
	if _, err := GetDAVNodeByID(2, memberOne.NodeID); !errors.Is(err, ErrDAVNotFound) {
		t.Fatalf("cross-member GetDAVNodeByID error = %v, want ErrDAVNotFound", err)
	}
	if err := CopyDAVNode(1, "docs/item.txt", "docs/item.txt/child.txt", 1<<20); !errors.Is(err, ErrDAVInvalidPath) {
		t.Fatalf("copy into source file error = %v, want ErrDAVInvalidPath", err)
	}
	if _, _, err := PutDAVFile(1, "target.txt", "text/plain", strings.NewReader("target"), 1<<20, 1<<20); err != nil {
		t.Fatalf("PutDAVFile(target) error = %v", err)
	}
	if err := CopyDAVNode(1, "docs/item.txt", "target.txt/child.txt", 1<<20); !errors.Is(err, ErrDAVNotDirectory) {
		t.Fatalf("copy into unrelated file error = %v, want ErrDAVNotDirectory", err)
	}
}

func TestDAVStoreConcurrentIdenticalUploadsKeepOneBlobAndValidReferences(t *testing.T) {
	setupWebDAVStoreTest(t)
	if _, err := CreateDAVDirectory(1, "parallel"); err != nil {
		t.Fatalf("CreateDAVDirectory() error = %v", err)
	}
	content := strings.Repeat("same parallel content\n", 600)
	const uploadCount = 6
	var wait sync.WaitGroup
	errorsByUpload := make(chan error, uploadCount)
	for index := 0; index < uploadCount; index++ {
		wait.Add(1)
		go func(index int) {
			defer wait.Done()
			_, _, err := PutDAVFile(
				1,
				"parallel/file-"+string(rune('a'+index))+".txt",
				"text/plain",
				strings.NewReader(content),
				1<<20,
				1<<20,
			)
			errorsByUpload <- err
		}(index)
	}
	wait.Wait()
	close(errorsByUpload)
	for err := range errorsByUpload {
		if err != nil {
			t.Fatalf("concurrent PutDAVFile() error = %v", err)
		}
	}
	hash := sha256HexForDAVTest([]byte(content))
	blob, err := FindDAVBlob(hash, int64(len(content)))
	if err != nil || blob.RefCount != uploadCount {
		t.Fatalf("shared blob after concurrent uploads = %#v, error %v", blob, err)
	}
	var blobCount int
	if err := WebDAVDB.QueryRow("SELECT COUNT(*) FROM dav_blobs").Scan(&blobCount); err != nil {
		t.Fatalf("count blobs error = %v", err)
	}
	if blobCount != 1 {
		t.Fatalf("blob count = %d, want 1", blobCount)
	}
}

func TestDAVStoreChunkBoundariesSeekAndCascadeDelete(t *testing.T) {
	setupWebDAVStoreTest(t)
	if _, err := CreateDAVDirectory(1, "chunks"); err != nil {
		t.Fatalf("CreateDAVDirectory() error = %v", err)
	}
	sizes := []int{0, 1, DAVChunkSize - 1, DAVChunkSize, DAVChunkSize + 1, 2*DAVChunkSize + 37}
	for index, size := range sizes {
		content := make([]byte, size)
		for offset := range content {
			content[offset] = byte((offset*31 + index*17) % 251)
		}
		name := fmt.Sprintf("chunks/item-%d.bin", index)
		node, _, err := PutDAVFile(1, name, "application/octet-stream", bytes.NewReader(content), 10<<20, 100<<20)
		if err != nil {
			t.Fatalf("PutDAVFile(size=%d) error = %v", size, err)
		}
		blob, err := FindDAVBlob(node.ETag, int64(size))
		if err != nil {
			t.Fatalf("FindDAVBlob(size=%d) error = %v", size, err)
		}
		expectedChunks := (size + DAVChunkSize - 1) / DAVChunkSize
		if blob.ChunkSize != DAVChunkSize || blob.ChunkCount != expectedChunks {
			t.Fatalf("blob(size=%d) chunk metadata = size %d count %d, want %d/%d",
				size, blob.ChunkSize, blob.ChunkCount, DAVChunkSize, expectedChunks)
		}
		var chunkCount int
		var originalTotal int64
		if err := WebDAVDB.QueryRow(`
			SELECT COUNT(*), COALESCE(SUM(original_size), 0)
			FROM dav_blob_chunks WHERE blob_id=?`, blob.BlobID).Scan(&chunkCount, &originalTotal); err != nil {
			t.Fatalf("query chunks(size=%d): %v", size, err)
		}
		if chunkCount != expectedChunks || originalTotal != int64(size) {
			t.Fatalf("stored chunks(size=%d) = count %d bytes %d", size, chunkCount, originalTotal)
		}
		reader, err := OpenDAVBlob(blob)
		if err != nil {
			t.Fatalf("OpenDAVBlob(size=%d): %v", size, err)
		}
		if size > DAVChunkSize {
			start := DAVChunkSize - 7
			if _, err := reader.Seek(int64(start), io.SeekStart); err != nil {
				t.Fatalf("Seek(size=%d): %v", size, err)
			}
			window := make([]byte, min(32, size-start))
			if _, err := io.ReadFull(reader, window); err != nil {
				t.Fatalf("cross-chunk read(size=%d): %v", size, err)
			}
			if !bytes.Equal(window, content[start:start+len(window)]) {
				t.Fatalf("cross-chunk content mismatch(size=%d)", size)
			}
			_, _ = reader.Seek(0, io.SeekStart)
		}
		got, err := io.ReadAll(reader)
		_ = reader.Close()
		if err != nil || !bytes.Equal(got, content) {
			t.Fatalf("full chunk read(size=%d) error=%v bytes=%d", size, err, len(got))
		}
		if err := DeleteDAVNode(1, name, false); err != nil {
			t.Fatalf("DeleteDAVNode(size=%d): %v", size, err)
		}
		if err := WebDAVDB.QueryRow("SELECT COUNT(*) FROM dav_blob_chunks WHERE blob_id=?", blob.BlobID).Scan(&chunkCount); err != nil {
			t.Fatalf("count chunks after delete(size=%d): %v", size, err)
		}
		if chunkCount != 0 {
			t.Fatalf("chunks after last delete(size=%d) = %d, want 0", size, chunkCount)
		}
	}
}

func TestDAVStoreDetectsCorruptChunk(t *testing.T) {
	setupWebDAVStoreTest(t)
	content := bytes.Repeat([]byte("chunk-integrity-"), (DAVChunkSize/16)+100)
	node, _, err := PutDAVFile(1, "corrupt.txt", "text/plain", bytes.NewReader(content), 10<<20, 100<<20)
	if err != nil {
		t.Fatalf("PutDAVFile() error = %v", err)
	}
	if _, err := WebDAVDB.Exec(`
		UPDATE dav_blob_chunks SET content_blob=X'00', stored_size=1
		WHERE blob_id=? AND chunk_index=0`, *node.BlobID); err != nil {
		t.Fatalf("corrupt chunk: %v", err)
	}
	_, _, reader, err := ReadDAVFile(1, "corrupt.txt")
	if err != nil {
		t.Fatalf("ReadDAVFile() open error = %v", err)
	}
	defer reader.Close()
	if _, err := io.ReadAll(reader); !errors.Is(err, ErrDAVCorruptBlob) {
		t.Fatalf("corrupt read error = %v, want ErrDAVCorruptBlob", err)
	}
	if err := ValidateDAVBlobStorage(); !errors.Is(err, ErrDAVCorruptBlob) {
		t.Fatalf("ValidateDAVBlobStorage() error = %v, want ErrDAVCorruptBlob", err)
	}
}

func TestDAVReaderKeepsSnapshotWhenLastReferenceIsDeleted(t *testing.T) {
	setupWebDAVStoreTest(t)
	content := bytes.Repeat([]byte("snapshot-content-"), (2*DAVChunkSize/17)+100)
	node, _, err := PutDAVFile(1, "snapshot.bin", "application/octet-stream", bytes.NewReader(content), 10<<20, 100<<20)
	if err != nil {
		t.Fatalf("PutDAVFile() error = %v", err)
	}
	blob, err := FindDAVBlob(node.ETag, int64(len(content)))
	if err != nil {
		t.Fatalf("FindDAVBlob() error = %v", err)
	}
	reader, err := OpenDAVBlob(blob)
	if err != nil {
		t.Fatalf("OpenDAVBlob() error = %v", err)
	}
	prefix := make([]byte, 32)
	if _, err := io.ReadFull(reader, prefix); err != nil {
		_ = reader.Close()
		t.Fatalf("read prefix: %v", err)
	}
	if err := DeleteDAVNode(1, "snapshot.bin", false); err != nil {
		_ = reader.Close()
		t.Fatalf("DeleteDAVNode() while reading error = %v", err)
	}
	remaining, err := io.ReadAll(reader)
	_ = reader.Close()
	got := append(append([]byte(nil), prefix...), remaining...)
	if err != nil || !bytes.Equal(got, content) {
		t.Fatalf("snapshot read after delete error=%v bytes=%d", err, len(remaining)+len(prefix))
	}
	if _, err := FindDAVBlob(node.ETag, int64(len(content))); !errors.Is(err, ErrDAVNotFound) {
		t.Fatalf("blob after reader close error = %v, want ErrDAVNotFound", err)
	}
}

func TestDAVTransferGateLimitsAndCancelsWaiters(t *testing.T) {
	gate := newDAVTransferGate()
	release, err := gate.acquireWithLimit(context.Background(), 1)
	if err != nil {
		t.Fatalf("first acquireWithLimit() error = %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if _, err := gate.acquireWithLimit(ctx, 1); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("blocked acquire error = %v, want context deadline", err)
	}
	release()
	release()
	secondRelease, err := gate.acquireWithLimit(context.Background(), 1)
	if err != nil {
		t.Fatalf("acquire after release error = %v", err)
	}
	secondRelease()
}

func TestDAVTransferGateAppliesRaisedLimitToExistingWaiter(t *testing.T) {
	gate := newDAVTransferGate()
	var limit atomic.Int64
	limit.Store(1)
	firstRelease, err := gate.acquireWithLimitProvider(context.Background(), func() int {
		return int(limit.Load())
	})
	if err != nil {
		t.Fatalf("first acquire error = %v", err)
	}
	defer firstRelease()

	acquired := make(chan func(), 1)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	go func() {
		release, acquireErr := gate.acquireWithLimitProvider(ctx, func() int {
			return int(limit.Load())
		})
		if acquireErr == nil {
			acquired <- release
		}
	}()
	limit.Store(2)
	select {
	case release := <-acquired:
		release()
	case <-ctx.Done():
		t.Fatal("waiting transfer did not observe the raised live limit")
	}
}

func TestOpenDAVBlobRejectsInvalidSuppliedMetadata(t *testing.T) {
	setupWebDAVStoreTest(t)
	invalid := &DAVBlob{
		BlobID:       1,
		OriginalSize: DAVChunkSize + 1,
		ChunkSize:    DAVChunkSize,
		ChunkCount:   1,
	}
	if _, err := OpenDAVBlob(invalid); !errors.Is(err, ErrDAVCorruptBlob) {
		t.Fatalf("OpenDAVBlob() error = %v, want ErrDAVCorruptBlob", err)
	}
}

func TestInitWebDAVDBReplacesEmptyLegacyContentSchemaAndKeepsCredential(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "legacy-empty.db")
	db, err := sql.Open("sqlite", sqliteDSN(dbPath))
	if err != nil {
		t.Fatalf("open legacy database: %v", err)
	}
	for _, statement := range []string{
		`CREATE TABLE dav_blobs (
			blob_id INTEGER PRIMARY KEY,
			content_blob BLOB NOT NULL
		)`,
		`CREATE TABLE dav_app_credentials (
			member_id INTEGER PRIMARY KEY,
			secret_hash TEXT NOT NULL,
			create_time DATETIME NOT NULL,
			modify_time DATETIME NOT NULL,
			last_use_time DATETIME
		)`,
		`INSERT INTO dav_app_credentials(
			member_id, secret_hash, create_time, modify_time
		) VALUES (7, 'preserved-hash', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
	} {
		if _, err := db.Exec(statement); err != nil {
			_ = db.Close()
			t.Fatalf("prepare legacy schema: %v", err)
		}
	}
	_ = db.Close()

	oldDB := WebDAVDB
	if err := InitWebDAVDB(dbPath); err != nil {
		t.Fatalf("InitWebDAVDB() error = %v", err)
	}
	t.Cleanup(func() {
		if WebDAVDB != nil {
			_ = WebDAVDB.Close()
		}
		WebDAVDB = oldDB
	})
	var credentialHash string
	if err := WebDAVDB.QueryRow(
		"SELECT secret_hash FROM dav_app_credentials WHERE member_id=7",
	).Scan(&credentialHash); err != nil {
		t.Fatalf("read preserved credential: %v", err)
	}
	if credentialHash != "preserved-hash" {
		t.Fatalf("credential hash = %q, want preserved value", credentialHash)
	}
	var chunkTable string
	if err := WebDAVDB.QueryRow(`
		SELECT name FROM sqlite_master
		WHERE type='table' AND name='dav_blob_chunks'`,
	).Scan(&chunkTable); err != nil {
		t.Fatalf("chunk table missing after schema replacement: %v", err)
	}
}

func TestInitWebDAVDBRejectsNonEmptyLegacyContentSchema(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "legacy-content.db")
	db, err := sql.Open("sqlite", sqliteDSN(dbPath))
	if err != nil {
		t.Fatalf("open legacy database: %v", err)
	}
	if _, err := db.Exec(`
		CREATE TABLE dav_blobs (
			blob_id INTEGER PRIMARY KEY,
			content_blob BLOB NOT NULL
		)`); err != nil {
		t.Fatalf("create legacy schema: %v", err)
	}
	if _, err := db.Exec("INSERT INTO dav_blobs(blob_id, content_blob) VALUES (1, X'01')"); err != nil {
		t.Fatalf("insert legacy blob: %v", err)
	}
	_ = db.Close()

	oldDB := WebDAVDB
	err = InitWebDAVDB(dbPath)
	WebDAVDB = oldDB
	if err == nil || !strings.Contains(err.Error(), "legacy WebDAV content exists") {
		t.Fatalf("InitWebDAVDB() error = %v, want non-empty legacy rejection", err)
	}
}

func sha256HexForDAVTest(content []byte) string {
	sum := sha256.Sum256(content)
	return hex.EncodeToString(sum[:])
}
