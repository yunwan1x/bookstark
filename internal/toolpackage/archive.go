package toolpackage

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"mime"
	"net/url"
	"path"
	"sort"
	"strings"
	"unicode/utf8"
)

const MaxArchive = 64 << 20

type File struct {
	Name string `json:"name"`
	MIME string `json:"mime"`
	Size int64  `json:"size"`
	Hash string `json:"hash"`
}
type Archive struct {
	Files   []Asset
	Entries []string
	Entry   string
	Config  json.RawMessage
	Size    int64
}

func ValidName(name string) bool {
	if name == "" || len(name) > 512 || !utf8.ValidString(name) || strings.ContainsAny(name, "\\\x00?#:%") || strings.HasPrefix(name, "/") || path.Clean(name) != name {
		return false
	}
	for _, part := range strings.Split(name, "/") {
		if part == "." || part == ".." || part == "" {
			return false
		}
	}
	return true
}

// Unpack validates every archive member before the caller persists any files.
func Unpack(reader io.ReaderAt, size int64) (Archive, error) {
	var a Archive
	if size <= 0 || size > MaxArchive {
		return a, fmt.Errorf("archive_too_large")
	}
	z, err := zip.NewReader(reader, size)
	if err != nil {
		return a, fmt.Errorf("invalid_archive")
	}
	if len(z.File) > MaxFiles*2 {
		return a, fmt.Errorf("too_many_files")
	}
	seen := map[string]bool{}
	for _, f := range z.File {
		name := strings.TrimSuffix(f.Name, "/")
		if !ValidName(name) || f.Mode()&(fs.ModeSymlink|fs.ModeDevice|fs.ModeNamedPipe|fs.ModeSocket) != 0 {
			return a, fmt.Errorf("unsafe_archive_path: %s", f.Name)
		}
		if seen[name] {
			return a, fmt.Errorf("duplicate_archive_path: %s", name)
		}
		seen[name] = true
		if f.FileInfo().IsDir() {
			continue
		}
		if !f.Mode().IsRegular() {
			return a, fmt.Errorf("unsafe_archive_path: %s", name)
		}
		if len(a.Files) >= MaxFiles {
			return a, fmt.Errorf("too_many_files")
		}
		if f.UncompressedSize64 > MaxFile || f.UncompressedSize64 > uint64(MaxBytes-a.Size) {
			return a, fmt.Errorf("archive_too_large")
		}
		r, e := f.Open()
		if e != nil {
			return a, fmt.Errorf("invalid_archive")
		}
		b, e := io.ReadAll(io.LimitReader(r, MaxFile+1))
		r.Close()
		if e != nil || len(b) > MaxFile || int64(len(b))+a.Size > MaxBytes {
			return a, fmt.Errorf("invalid_archive")
		}
		typ := mime.TypeByExtension(strings.ToLower(path.Ext(name)))
		if typ == "" {
			typ = "application/octet-stream"
		}
		if strings.EqualFold(path.Ext(name), ".wasm") {
			typ = "application/wasm"
		}
		a.Files = append(a.Files, Asset{Name: name, MIME: typ, Data: b})
		a.Size += int64(len(b))
		if strings.EqualFold(path.Ext(name), ".html") || strings.EqualFold(path.Ext(name), ".htm") {
			a.Entries = append(a.Entries, name)
		}
		if name == "tool.json" {
			if len(b) > 16384 || !json.Valid(b) {
				return a, fmt.Errorf("invalid_tool_manifest")
			}
			a.Config = append([]byte(nil), b...)
		}
	}
	// A file cannot also be an ancestor directory of another member.
	for _, f := range a.Files {
		for _, other := range a.Files {
			if strings.HasPrefix(other.Name, f.Name+"/") {
				return a, fmt.Errorf("unsafe_archive_path: %s", f.Name)
			}
		}
	}
	sort.Strings(a.Entries)
	var config struct {
		Entry string `json:"entry"`
	}
	if len(a.Config) > 0 {
		if json.Unmarshal(a.Config, &config) != nil {
			return a, fmt.Errorf("invalid_tool_manifest")
		}
	}
	if config.Entry != "" {
		a.Entry = config.Entry
	} else if seen["index.html"] {
		a.Entry = "index.html"
	} else if len(a.Entries) > 0 {
		a.Entry = a.Entries[0]
	}
	if a.Entry != "" {
		found := false
		for _, e := range a.Entries {
			if e == a.Entry {
				found = true
			}
		}
		if !found {
			return a, fmt.Errorf("invalid_entry")
		}
	}
	if len(a.Entries) == 0 {
		return a, fmt.Errorf("missing_entry")
	}
	return a, nil
}

// AssetURL keeps path segments intact while escaping them for transfer.
func AssetURL(base, name string) string {
	parts := strings.Split(name, "/")
	for i := range parts {
		parts[i] = url.PathEscape(parts[i])
	}
	return strings.TrimSuffix(base, "/") + "/" + strings.Join(parts, "/")
}
