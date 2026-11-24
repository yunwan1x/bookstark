package models

import (
	"bookstark/conf"
	"bookstark/internal/toolsecrets"
	"context"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strings"
)

var toolSecretName = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,128}$`)

// Called under the installation lock after identity and file permission checks.
// The data root stays stable across upgrades and keep-data reinstalls; binding
// ciphertext to that root, member, tool and name prevents transplant attacks.
func executeToolSecretOperation(member, id int64, t *InstalledTool, request ToolFileOperation) (any, error) {
	if !toolSecretName.MatchString(request.Path) {
		return nil, ErrDAVInvalidPath
	}
	p, err := ToolResourcePath(t, "data", ".credentials/"+request.Path)
	if err != nil {
		return nil, err
	}
	keyFile := conf.App.DBPath + ".tool-secrets.key"
	binding := fmt.Sprintf("bookstark-tool-secret-v1:%d:%d:%s", member, id, p)
	switch request.Op {
	case "secret_get":
		_, _, reader, err := ReadDAVFileContext(context.Background(), member, p)
		if errors.Is(err, ErrDAVNotFound) {
			return nil, nil
		}
		if err != nil {
			return nil, err
		}
		defer reader.Close()
		value, err := io.ReadAll(io.LimitReader(reader, (2<<20)+1))
		if err != nil {
			return nil, err
		}
		if len(value) > 2<<20 {
			return nil, ErrDAVFileTooLarge
		}
		return toolsecrets.Decrypt(keyFile, binding, string(value))
	case "secret_set":
		if len(request.Value) > 1<<20 {
			return nil, ErrDAVFileTooLarge
		}
		value, err := toolsecrets.Encrypt(keyFile, binding, request.Value)
		if err != nil {
			return nil, err
		}
		return nil, putToolResourceAt(member, p, "application/octet-stream", strings.NewReader(value))
	case "secret_remove":
		err := DeleteDAVNode(member, p, false)
		if errors.Is(err, ErrDAVNotFound) {
			err = nil
		}
		return nil, err
	}
	return nil, ErrDAVInvalidPath
}
