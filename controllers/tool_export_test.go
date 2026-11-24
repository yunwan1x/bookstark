package controllers_test

import (
	"bookstark/internal/toolpackage"
	"bookstark/models"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/url"
	"strings"
	"testing"
)

func TestInstalledToolZIPExportRoundTripExcludesRuntimeData(t *testing.T) {
	router, token := initPackageWorkflow(t)
	files := packageWorkflowFiles("pages/index.html", "1.0.0")
	files["pages/index.html"] = []byte(`<script src="/assets/main.js"></script>`)
	files["assets/main.js"] = []byte(`fetch('/assets/protocol.wasm')`)
	upload := packageWorkflowUploadOK(t, router, token, files, 0)
	pub := packageWorkflowPublish(t, router, token, upload, "1.0.0", "login")
	base := fmt.Sprintf("/api/tool-installs/%d", upload.ID)
	w := adminAssetRequest(router, token, "PUT", base, map[string]any{"revision": pub.Revision, "hash": pub.Metadata.Hash})
	if w.Code != 200 {
		t.Fatalf("install %d %s", w.Code, w.Body.String())
	}
	installed, err := models.GetInstalledTool(1, upload.ID)
	if err != nil {
		t.Fatal(err)
	}
	w = adminAssetRequest(router, token, "POST", base+"/data", map[string]any{"revision": installed.Revision, "instance": installed.Instance, "op": "set", "key": "private-state", "value": "runtime-secret"})
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if err = models.PutToolResource(1, upload.ID, installed.Revision, installed.Instance, "data", "private.txt", "text/plain", strings.NewReader("private-user-file")); err != nil {
		t.Fatal(err)
	}
	other := &models.Member{Account: "export-other", Password: "test-only", Role: 1}
	if err := other.Insert(); err != nil {
		t.Fatal(err)
	}
	otherToken, err := models.CreateApiToken(other.MemberID, "export-test")
	if err != nil {
		t.Fatal(err)
	}
	if response := packageWorkflowGet(router, otherToken.Token, base+"/export?revision="+installed.Revision+"&instance="+installed.Instance); response.Code != 404 {
		t.Fatalf("cross-member export %d", response.Code)
	}
	if response := packageWorkflowGet(router, token, base+"/export?revision="+installed.Revision+"&instance=wrong"); response.Code != 409 {
		t.Fatalf("wrong instance %d", response.Code)
	}
	query := url.Values{"revision": {installed.Revision}, "instance": {installed.Instance}}.Encode()
	if w = packageWorkflowGet(router, "", base+"/export?"+query); w.Code == 200 {
		t.Fatal("anonymous export")
	}
	if w = packageWorkflowGet(router, token, base+"/export?revision=stale&instance="+installed.Instance); w.Code != 409 {
		t.Fatalf("stale export %d", w.Code)
	}
	w = packageWorkflowGet(router, token, base+"/export?"+query)
	if w.Code != 200 {
		t.Fatalf("export %d %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Header().Get("Content-Disposition"), ".zip") || w.Header().Get("Cache-Control") != "private, no-store" {
		t.Fatalf("download headers: %v", w.Header())
	}
	archive, err := toolpackage.Unpack(bytes.NewReader(w.Body.Bytes()), int64(w.Body.Len()))
	if err != nil {
		t.Fatal(err)
	}
	exported := map[string][]byte{}
	for _, f := range archive.Files {
		exported[f.Name] = f.Data
		for _, private := range []string{"runtime-secret", "private-user-file", installed.Instance, installed.Assets, installed.DataRoot} {
			if private != "" && bytes.Contains(f.Data, []byte(private)) {
				t.Fatalf("private information in %s: %s", f.Name, private)
			}
		}
	}
	if len(exported) != len(files) || !bytes.Equal(exported["assets/protocol.wasm"], files["assets/protocol.wasm"]) {
		t.Fatal("program tree changed")
	}
	if string(exported["assets/main.js"]) != string(files["assets/main.js"]) || !bytes.Contains(exported["pages/index.html"], []byte(`/assets/main.js`)) {
		t.Fatal("program URLs not portable")
	}
	var manifest map[string]any
	if err = json.Unmarshal(exported["tool.json"], &manifest); err != nil || manifest["entry"] != "pages/index.html" {
		t.Fatal("manifest entry lost")
	}
	again := packageWorkflowUploadOK(t, router, token, exported, 0)
	pub2 := packageWorkflowPublish(t, router, token, again, "1.0.0", "login")
	base2 := fmt.Sprintf("/api/tool-installs/%d", again.ID)
	w = adminAssetRequest(router, token, "PUT", base2, map[string]any{"revision": pub2.Revision, "hash": pub2.Metadata.Hash})
	if w.Code != 200 {
		t.Fatalf("reinstall %d %s", w.Code, w.Body.String())
	}
	restored, err := models.GetInstalledTool(1, again.ID)
	if err != nil {
		t.Fatal(err)
	}
	if restored.Instance == installed.Instance {
		t.Fatal("reinstalled instance reused")
	}
	values, err := models.GetInstalledToolValues(1, again.ID)
	if err != nil || len(values) != 0 {
		t.Fatal("runtime data copied")
	}
	_, _, reader, err := models.ReadDAVFile(1, restored.Assets+"/assets/protocol.wasm")
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	body, err := io.ReadAll(reader)
	if err != nil || !bytes.Equal(body, files["assets/protocol.wasm"]) {
		t.Fatal("binary changed")
	}
	// Exported tool.json must remain within the importer's 16 KiB limit.
	if _, err := models.DB.Exec(`UPDATE md_tool_installs SET description=? WHERE member_id=1 AND tool_id=?`, strings.Repeat("<>&", 4000), upload.ID); err != nil {
		t.Fatal(err)
	}
	if response := packageWorkflowGet(router, token, base+"/export?"+query); response.Code != 413 {
		t.Fatalf("oversized generated manifest %d", response.Code)
	}
	// Article/reference installations have no complete program tree to export.
	if _, err := models.DB.Exec(`UPDATE md_tool_install_metadata SET metadata=json_set(metadata,'$.distribution','references') WHERE member_id=1 AND tool_id=?`, upload.ID); err != nil {
		t.Fatal(err)
	}
	if response := packageWorkflowGet(router, token, base+"/export?"+query); response.Code != 403 {
		t.Fatalf("reference export %d", response.Code)
	}

}
