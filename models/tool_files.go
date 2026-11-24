package models

import (
	"errors"
	"strings"
	"time"
)

// ToolFileInfo intentionally omits WebDAV node IDs, private backing paths and
// public URLs. All paths are relative to this installation's data root.
type ToolFileInfo struct {
	Name     string    `json:"name"`
	Path     string    `json:"path"`
	IsDir    bool      `json:"is_directory"`
	Size     int64     `json:"size"`
	MIME     string    `json:"mime_type,omitempty"`
	Modified time.Time `json:"modified"`
}
type ToolFileOperation struct {
	Op        string `json:"op"`
	Path      string `json:"path"`
	To        string `json:"to,omitempty"`
	Recursive bool   `json:"recursive,omitempty"`
}

var ErrToolDirectoryNotEmpty = errors.New("tool directory not empty")

func ToolFilePermissions(op string) (read, write bool) {
	switch op {
	case "read", "list", "stat", "exists":
		return true, false
	case "write", "mkdir", "remove", "rename", "move":
		return false, true
	case "copy":
		return true, true
	}
	return false, false
}
func toolDataPath(t *InstalledTool, name string, allowRoot bool) (string, error) {
	if len(name) > 2048 {
		return "", ErrDAVInvalidPath
	}
	if allowRoot && (name == "" || name == "/") {
		p, err := ToolResourcePath(t, "data", "placeholder")
		return strings.TrimSuffix(p, "/placeholder"), err
	}
	return ToolResourcePath(t, "data", name)
}
func toolFileInfo(node *DAVNode, root string) ToolFileInfo {
	relative := strings.TrimPrefix(strings.TrimPrefix(node.Path, "/"), strings.TrimPrefix(root, "/")+"/")
	if strings.Trim(node.Path, "/") == strings.Trim(root, "/") {
		relative = ""
	}
	return ToolFileInfo{Name: node.Name, Path: relative, IsDir: node.IsDir, Size: node.Size, MIME: node.MIMEType, Modified: node.ModifyTime}
}
func ensureToolDirectory(member int64, value string, recursive bool) error {
	if recursive {
		parts := strings.Split(strings.Trim(value, "/"), "/")
		prefix := ""
		for _, part := range parts {
			prefix += "/" + part
			if _, err := CreateDAVDirectory(member, prefix); err != nil && !errors.Is(err, ErrDAVAlreadyExists) {
				return err
			}
			node, err := GetDAVNode(member, prefix)
			if err != nil {
				return err
			}
			if !node.IsDir {
				return ErrDAVNotDirectory
			}
		}
		return nil
	}
	_, err := CreateDAVDirectory(member, value)
	if errors.Is(err, ErrDAVAlreadyExists) {
		node, readErr := GetDAVNode(member, value)
		if readErr != nil {
			return readErr
		}
		if node.IsDir {
			return nil
		}
		return ErrDAVNotDirectory
	}
	return err
}

// ExecuteToolFileOperation holds the installation lock across permission and
// revision validation and the operation, just like file writes and uninstall.
func ExecuteToolFileOperation(member, id int64, revision, instance string, request ToolFileOperation) (any, error) {
	switch request.Op {
	case "list", "stat", "exists", "mkdir", "remove", "rename", "move", "copy":
	default:
		return nil, ErrDAVInvalidPath
	}
	lock := toolLock(member, id)
	lock.Lock()
	defer lock.Unlock()
	t, err := GetInstalledTool(member, id)
	if err != nil {
		return nil, err
	}
	if t.Revision != revision || t.Instance != instance {
		return nil, ErrToolConflict
	}
	read, write := ToolFilePermissions(request.Op)
	if !read && !write {
		return nil, ErrDAVInvalidPath
	}
	if read && !t.Permissions.ReadFiles || write && !t.Permissions.SaveFiles {
		return nil, ErrToolPermission
	}
	if WebDAVDB == nil {
		return nil, errors.New("file storage unavailable")
	}
	root, err := toolDataPath(t, "", true)
	if err != nil {
		return nil, err
	}
	value, err := toolDataPath(t, request.Path, request.Op == "list" || request.Op == "stat" || request.Op == "exists")
	if err != nil {
		return nil, err
	}
	node, err := GetDAVNode(member, value)
	if request.Op == "exists" {
		if errors.Is(err, ErrDAVNotFound) {
			return value == root, nil
		}
		if err != nil {
			return nil, err
		}
		return true, nil
	}
	if request.Op == "list" || request.Op == "stat" {
		if value == root && errors.Is(err, ErrDAVNotFound) {
			if request.Op == "list" {
				return []ToolFileInfo{}, nil
			}
			return ToolFileInfo{Name: "", Path: "", IsDir: true}, nil
		}
		if err != nil {
			return nil, err
		}
		if request.Op == "stat" {
			return toolFileInfo(node, root), nil
		}
		nodes, err := ListDAVNodes(member, value)
		if err != nil {
			return nil, err
		}
		result := make([]ToolFileInfo, 0, len(nodes))
		for _, entry := range nodes {
			result = append(result, toolFileInfo(&entry, root))
		}
		return result, nil
	}
	if _, err := EnsureDAVRoot(member); err != nil {
		return nil, err
	}
	switch request.Op {
	case "mkdir":
		if err := ensureToolDirectory(member, root, true); err != nil {
			return nil, err
		}
		if err := ensureToolDirectory(member, value, request.Recursive); err != nil {
			return nil, err
		}
		node, err = GetDAVNode(member, value)
		if err != nil {
			return nil, err
		}
		return toolFileInfo(node, root), nil
	case "remove":
		if err != nil {
			return nil, err
		}
		if node.IsDir && !request.Recursive {
			children, listErr := ListDAVNodes(member, value)
			if listErr != nil {
				return nil, listErr
			}
			if len(children) > 0 {
				return nil, ErrToolDirectoryNotEmpty
			}
		}
		return nil, DeleteDAVNode(member, value, request.Recursive)
	case "rename", "move", "copy":
		if err != nil {
			return nil, err
		}
		target, pathErr := toolDataPath(t, request.To, false)
		if pathErr != nil {
			return nil, pathErr
		}
		if request.Op == "copy" {
			err = CopyDAVNode(member, value, target, GetWebDAVSettings().UserQuotaBytes)
		} else {
			err = RenameDAVNode(member, value, target)
		}
		if err != nil {
			return nil, err
		}
		node, err = GetDAVNode(member, target)
		if err != nil {
			return nil, err
		}
		return toolFileInfo(node, root), nil
	}
	return nil, ErrDAVInvalidPath
}
