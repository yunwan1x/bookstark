//go:build wails

package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
)

type savedCredential struct {
	Account  string `json:"account"`
	Password string `json:"password"`
}

func webOrigin(address string) string {
	u, err := url.Parse(address)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || u.User != nil {
		return ""
	}
	return u.Scheme + "://" + u.Host
}

func (l *launcher) allowedClientOrigin(origin string) bool {
	if origin == "http://"+l.addr {
		return true
	}
	p, err := l.preferences()
	return err == nil && p.Remote != "" && origin == webOrigin(p.Remote)
}

// Credentials are encrypted at rest, scoped to an exact server origin, and
// readable only through the native main-window bridge or local access cookie.
func (l *launcher) credential(origin string, value *savedCredential, remove bool) (*savedCredential, error) {
	l.credentialMu.Lock()
	defer l.credentialMu.Unlock()
	dir := filepath.Join(l.dir, "credentials")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	path := filepath.Join(dir, fmt.Sprintf("%x.enc", sha256.Sum256([]byte(origin))))
	if remove {
		err := os.Remove(path)
		if errors.Is(err, os.ErrNotExist) {
			err = nil
		}
		return nil, err
	}
	secret, err := localSecret(filepath.Join(dir, "vault.key"))
	if err != nil {
		return nil, err
	}
	key := sha256.Sum256([]byte(secret))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if value != nil {
		if value.Account == "" || len(value.Account) > 256 || value.Password == "" || len(value.Password) > 72 {
			return nil, errors.New("invalid credentials")
		}
		data, err := json.Marshal(value)
		if err != nil {
			return nil, err
		}
		nonce := make([]byte, gcm.NonceSize())
		if _, err := rand.Read(nonce); err != nil {
			return nil, err
		}
		return value, writePrivateFile(path, gcm.Seal(nonce, nonce, data, []byte(origin)))
	}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if len(data) < gcm.NonceSize() {
		return nil, errors.New("invalid saved credentials")
	}
	plain, err := gcm.Open(nil, data[:gcm.NonceSize()], data[gcm.NonceSize():], []byte(origin))
	if err != nil {
		return nil, errors.New("could not read saved credentials")
	}
	var result savedCredential
	if err := json.Unmarshal(plain, &result); err != nil {
		return nil, err
	}
	return &result, nil
}
