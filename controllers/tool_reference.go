package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/models"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"regexp"
)

var toolDigest = regexp.MustCompile(`^[a-f0-9]{64}$`)

// The digest binds consent to the HTML, source addresses and runtime policy.
// Original resource bytes are intentionally excluded: they are downloaded at install time.
func referenceDigest(t marketTool) (string, error) {
	manifest := struct {
		Entry       string                 `json:"entry,omitempty"`
		Files       []toolpackage.File     `json:"files,omitempty"`
		Version     string                 `json:"version"`
		Title       string                 `json:"title"`
		Description string                 `json:"description"`
		Permissions models.ToolPermissions `json:"permissions"`
		Access      string                 `json:"access"`
		Members     []int64                `json:"members,omitempty"`
		Content     string                 `json:"content"`
		Base        string                 `json:"resource_base"`
	}{t.Entry, t.Files, t.Version, t.Title, t.Description, t.Permissions, t.Access, t.Members, t.Content, t.ResourceBase}
	data, err := json.Marshal(manifest)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", sha256.Sum256(data)), nil
}
