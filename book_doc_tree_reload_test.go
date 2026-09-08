package main

import (
	"os"
	"strings"
	"testing"
)

func TestBookDocTreeSkipsReloadingCurrentDoc(t *testing.T) {
	data, err := os.ReadFile("static/js/editor.js")
	if err != nil {
		t.Fatal(err)
	}
	js := string(data)

	required := []string{
		"function isCurrentDoc(docId)",
		"return currentDocId !== null && String(currentDocId) === String(docId);",
		"async function loadDoc(docId, hintDocType) {\n      if (isCurrentDoc(docId) && !docLoadPending) return;",
		"if (hasChildren) {\n            toggleExpand(div);\n            if (isCurrentDoc(n.document_id) && !docLoadPending) return;",
		"} else {\n            if (isCurrentDoc(n.document_id) && !docLoadPending) return;\n            loadDoc(n.document_id, n.doc_type);",
		"div.onclick = function() {\n          if (isCurrentDoc(n.document_id) && !docLoadPending) return;\n          searchDocs('');",
	}

	for _, s := range required {
		if !strings.Contains(js, s) {
			t.Fatalf("editor.js missing current-doc reload guard contract: %q", s)
		}
	}
}
