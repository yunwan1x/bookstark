package models

import (
	"archive/zip"
	"bookstark/internal/toolpackage"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"
)

// ExportInstalledTool exports program assets only. Runtime values, user files,
// installation IDs, private DAV paths and market credentials never enter ZIPs.
// The installation lock prevents an update/uninstall from removing files mid-read.
func ExportInstalledTool(ctx context.Context, member, id int64, revision, instance string, output io.Writer) error {
	lock := toolLock(member, id)
	lock.Lock()
	defer lock.Unlock()
	t, err := GetInstalledTool(member, id)
	if err != nil {
		return err
	}
	if t.Instance != instance || t.Revision != revision {
		return ErrToolConflict
	}
	if t.Distribution != "files" || !toolpackage.ValidName(t.Entry) {
		return ErrToolPermission
	}
	raw, err := GetInstalledToolContent(member, id)
	if err != nil {
		return err
	}
	content, err := DecodeCompressedContent(raw)
	if err != nil {
		return err
	}
	manifest := struct {
		Title       string          `json:"title"`
		Description string          `json:"description"`
		Version     string          `json:"version"`
		Category    string          `json:"category"`
		Icon        string          `json:"icon,omitempty"`
		IconStyle   string          `json:"icon_style,omitempty"`
		IconColor   string          `json:"icon_color,omitempty"`
		Entry       string          `json:"entry"`
		Access      string          `json:"access"`
		Permissions ToolPermissions `json:"permissions"`
	}{t.Title, t.Description, t.Version, t.Category, t.Icon, t.IconStyle, t.IconColor, t.Entry, "login", t.Permissions}
	config, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return err
	}
	if len(config) > 16384 {
		return ErrDAVFileTooLarge
	}
	z := zip.NewWriter(output)
	count := 0
	var total int64
	entry := false
	// Only the current program-asset root is visited, never the data root.
	var walk func(string, string, int) error
	walk = func(dir, prefix string, depth int) error {
		if depth > 64 {
			return fmt.Errorf("invalid package depth")
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		nodes, err := ListDAVNodes(member, dir)
		if err != nil {
			return err
		}
		for _, node := range nodes {
			name := prefix + node.Name
			if !toolpackage.ValidName(name) {
				return ErrDAVInvalidPath
			}
			if node.IsDir {
				if err = walk(node.Path, name+"/", depth+1); err != nil {
					return err
				}
				continue
			}
			if name == "tool.json" {
				continue
			}
			count++
			total += node.Size
			if count >= toolpackage.MaxFiles || node.Size > toolpackage.MaxFile || total > toolpackage.MaxBytes-int64(len(config)) {
				return ErrDAVFileTooLarge
			}
			f, err := z.Create(name)
			if err != nil {
				return err
			}
			if name == t.Entry {
				entry = true
				_, err = io.WriteString(f, strings.ReplaceAll(content, t.AssetBase, "/"))
				if err != nil {
					return err
				}
				continue
			}
			_, _, reader, err := ReadDAVFileContext(ctx, member, node.Path)
			if err != nil {
				return err
			}
			if strings.HasPrefix(node.MIMEType, "text/") || strings.Contains(node.MIMEType, "javascript") || strings.HasSuffix(name, ".js") || strings.HasSuffix(name, ".mjs") || strings.HasSuffix(name, ".css") {
				b, readErr := io.ReadAll(io.LimitReader(reader, toolpackage.MaxFile+1))
				reader.Close()
				if readErr != nil {
					return readErr
				}
				if len(b) > toolpackage.MaxFile {
					return ErrDAVFileTooLarge
				}
				_, err = io.WriteString(f, strings.ReplaceAll(string(b), t.AssetBase, "/"))
			} else {
				_, err = io.Copy(f, reader)
				reader.Close()
			}
			if err != nil {
				return err
			}
		}
		return nil
	}
	if err = walk(t.Assets, "", 0); err != nil {
		return err
	}
	if !entry {
		return fmt.Errorf("package entry missing")
	}
	f, err := z.Create("tool.json")
	if err != nil {
		return err
	}
	if _, err = f.Write(config); err != nil {
		return err
	}
	return z.Close()
}
