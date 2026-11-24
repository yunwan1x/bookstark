package toolpackage

import (
	"archive/zip"
	"bytes"
	"encoding/binary"
	"io/fs"
	"strings"
	"testing"
)

type archiveFixtureFile struct {
	name string
	data []byte
	mode fs.FileMode
}

func archiveFixture(t *testing.T, files ...archiveFixtureFile) []byte {
	t.Helper()
	var out bytes.Buffer
	w := zip.NewWriter(&out)
	for _, file := range files {
		h := &zip.FileHeader{Name: file.name, Method: zip.Deflate}
		if file.mode != 0 {
			h.SetMode(file.mode)
		}
		entry, err := w.CreateHeader(h)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = entry.Write(file.data); err != nil {
			t.Fatal(err)
		}
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	return out.Bytes()
}

func unpackFixture(t *testing.T, files ...archiveFixtureFile) (Archive, error) {
	t.Helper()
	data := archiveFixture(t, files...)
	return Unpack(bytes.NewReader(data), int64(len(data)))
}

func TestArchivePreservesCompleteWASMWorkerResourceTree(t *testing.T) {
	files := []archiveFixtureFile{
		{name: "tool.json", data: []byte(`{"title":"Tool","version":"1.0.0","entry":"app/index.html"}`)},
		{name: "app/index.html", data: []byte(`<script type="module" src="./main.js"></script>`)},
		{name: "app/main.js", data: []byte("const file='worker';new Worker(`./${file}.js`,{type:'module'});")},
		{name: "app/worker.js", data: []byte(`fetch('./protocol.wasm')`)},
		{name: "app/protocol.wasm", data: []byte{'\x00', 'a', 's', 'm', 1, 0, 0, 0}},
		{name: "app/data/unreferenced.json", data: []byte(`{"preserve":true}`)},
		{name: "app/styles/main.css", data: []byte(`body{color:inherit}`)},
	}
	a, err := unpackFixture(t, files...)
	if err != nil {
		t.Fatal(err)
	}
	if a.Entry != "app/index.html" || len(a.Entries) != 1 || len(a.Files) != len(files) || len(a.Config) == 0 {
		t.Fatalf("incomplete archive: %#v", a)
	}
	got := make(map[string]Asset, len(a.Files))
	for _, f := range a.Files {
		got[f.Name] = f
	}
	var total int64
	for _, f := range files {
		stored, ok := got[f.name]
		if !ok || !bytes.Equal(stored.Data, f.data) {
			t.Fatalf("resource changed or missing: %q", f.name)
		}
		total += int64(len(f.data))
	}
	if a.Size != total || got["app/protocol.wasm"].MIME != "application/wasm" {
		t.Fatalf("size or WASM MIME lost: size=%d, wasm=%#v", a.Size, got["app/protocol.wasm"])
	}
}

func TestArchiveEntryAndOptionalManifest(t *testing.T) {
	for _, tc := range []struct {
		name  string
		files []archiveFixtureFile
		entry string
		err   string
	}{
		{name: "no manifest", files: []archiveFixtureFile{{name: "index.html", data: []byte("<h1>Tool</h1>")}}, entry: "index.html"},
		{name: "root entry preferred", files: []archiveFixtureFile{{name: "nested/tool.html"}, {name: "index.html"}}, entry: "index.html"},
		{name: "nested entry", files: []archiveFixtureFile{{name: "nested/tool.html"}}, entry: "nested/tool.html"},
		{name: "explicit entry", files: []archiveFixtureFile{{name: "index.html"}, {name: "other.htm"}, {name: "tool.json", data: []byte(`{"entry":"other.htm"}`)}}, entry: "other.htm"},
		{name: "no HTML", files: []archiveFixtureFile{{name: "main.js"}}, err: "missing_entry"},
		{name: "entry missing", files: []archiveFixtureFile{{name: "index.html"}, {name: "tool.json", data: []byte(`{"entry":"missing.html"}`)}}, err: "invalid_entry"},
		{name: "non HTML entry", files: []archiveFixtureFile{{name: "index.html"}, {name: "main.js"}, {name: "tool.json", data: []byte(`{"entry":"main.js"}`)}}, err: "invalid_entry"},
		{name: "invalid manifest JSON", files: []archiveFixtureFile{{name: "index.html"}, {name: "tool.json", data: []byte(`{"entry":`)}}, err: "invalid_tool_manifest"},
		{name: "invalid manifest type", files: []archiveFixtureFile{{name: "index.html"}, {name: "tool.json", data: []byte(`[]`)}}, err: "invalid_tool_manifest"},
		{name: "oversized manifest", files: []archiveFixtureFile{{name: "index.html"}, {name: "tool.json", data: []byte(`{"notes":"` + strings.Repeat("x", 16384) + `"}`)}}, err: "invalid_tool_manifest"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			a, err := unpackFixture(t, tc.files...)
			if tc.err != "" {
				if err == nil || !strings.Contains(err.Error(), tc.err) {
					t.Fatalf("error=%v, want %s", err, tc.err)
				}
				return
			}
			if err != nil || a.Entry != tc.entry {
				t.Fatalf("entry=%q, error=%v", a.Entry, err)
			}
		})
	}
}

func TestArchiveRejectsUnsafeAndConflictingPaths(t *testing.T) {
	for _, name := range []string{"../escape.js", "/absolute.js", "a/../escape.js", "a//file.js", `a\file.js`, "C:/file.js", "a%2fb.js", "a?query.js", "a#fragment.js", "./file.js", "bad\x00name.js"} {
		t.Run(name, func(t *testing.T) {
			_, err := unpackFixture(t, archiveFixtureFile{name: "index.html"}, archiveFixtureFile{name: name})
			if err == nil || !strings.Contains(err.Error(), "unsafe_archive_path") {
				t.Fatalf("unsafe name %q accepted: %v", name, err)
			}
		})
	}
	for _, tc := range []struct {
		name  string
		files []archiveFixtureFile
		want  string
	}{
		{name: "duplicate", files: []archiveFixtureFile{{name: "index.html"}, {name: "index.html"}}, want: "duplicate_archive_path"},
		{name: "symlink", files: []archiveFixtureFile{{name: "index.html"}, {name: "link", data: []byte("/etc/passwd"), mode: fs.ModeSymlink | 0777}}, want: "unsafe_archive_path"},
		{name: "file ancestor", files: []archiveFixtureFile{{name: "index.html"}, {name: "assets"}, {name: "assets/main.js"}}, want: "unsafe_archive_path"},
		{name: "directory collision", files: []archiveFixtureFile{{name: "index.html"}, {name: "assets/", mode: fs.ModeDir | 0755}, {name: "assets"}}, want: "duplicate_archive_path"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := unpackFixture(t, tc.files...)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error=%v, want %s", err, tc.want)
			}
		})
	}
}

func TestArchiveRejectsLimitsAndCorruptInput(t *testing.T) {
	for _, size := range []int64{0, -1, MaxArchive + 1} {
		if _, err := Unpack(bytes.NewReader(nil), size); err == nil || !strings.Contains(err.Error(), "archive_too_large") {
			t.Fatalf("invalid compressed size %d not rejected before parsing: %v", size, err)
		}
	}
	if _, err := Unpack(bytes.NewReader([]byte("not ZIP")), 7); err == nil {
		t.Fatal("corrupt ZIP accepted")
	}
	files := []archiveFixtureFile{{name: "index.html"}}
	for i := 0; i < MaxFiles; i++ {
		files = append(files, archiveFixtureFile{name: strings.Repeat("a", i+1) + ".js"})
	}
	if _, err := unpackFixture(t, files...); err == nil || !strings.Contains(err.Error(), "too_many_files") {
		t.Fatalf("file count limit not enforced: %v", err)
	}
	// Forged central-directory lengths must be rejected before inflation/allocation.
	data := archiveFixture(t, archiveFixtureFile{name: "index.html", data: []byte("x")})
	central := bytes.Index(data, []byte{'P', 'K', 1, 2})
	if central < 0 {
		t.Fatal("central directory missing")
	}
	binary.LittleEndian.PutUint32(data[central+24:central+28], uint32(MaxFile+1))
	if _, err := Unpack(bytes.NewReader(data), int64(len(data))); err == nil || !strings.Contains(err.Error(), "archive_too_large") {
		t.Fatalf("file size limit not enforced: %v", err)
	}
}

func TestArchiveAssetURLEscapesPathSegments(t *testing.T) {
	got := AssetURL("https://market.test/files/", "目录/space name.wasm")
	if got != "https://market.test/files/%E7%9B%AE%E5%BD%95/space%20name.wasm" {
		t.Fatalf("invalid resource URL: %s", got)
	}
}
