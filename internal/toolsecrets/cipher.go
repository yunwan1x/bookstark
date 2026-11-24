// Package toolsecrets encrypts tool credentials with a workspace key kept outside
// both SQLite databases. The key file must be included in workspace backups.
package toolsecrets

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sync"
)

var keyLock sync.Mutex

func loadKey(filename string, create bool) ([]byte, error) {
	keyLock.Lock()
	defer keyLock.Unlock()
	key, err := os.ReadFile(filename)
	if errors.Is(err, os.ErrNotExist) && create {
		key = make([]byte, 32)
		if _, err = io.ReadFull(rand.Reader, key); err != nil {
			return nil, err
		}
		// Link a complete, synced file atomically: another process must never
		// observe a partially written key or overwrite the winning key.
		f, err := os.CreateTemp(filepath.Dir(filename), ".tool-secret-key-*")
		if err != nil {
			return nil, err
		}
		defer os.Remove(f.Name())
		_, err = f.Write(key)
		if err == nil {
			err = f.Sync()
		}
		closeErr := f.Close()
		if err != nil {
			return nil, err
		}
		if closeErr != nil {
			return nil, closeErr
		}
		if err = os.Link(f.Name(), filename); err != nil && !errors.Is(err, os.ErrExist) {
			return nil, err
		}
		// Persist the directory entry as well as the key bytes. Directory sync
		// is not supported on every desktop platform, so it is best-effort.
		if dir, openErr := os.Open(filepath.Dir(filename)); openErr == nil {
			_ = dir.Sync()
			_ = dir.Close()
		}
		key, err = os.ReadFile(filename)
	}
	if err != nil {
		return nil, err
	}
	if len(key) != 32 {
		return nil, errors.New("invalid tool secrets key")
	}
	return key, nil
}

func aead(filename string, create bool) (cipher.AEAD, error) {
	key, err := loadKey(filename, create)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

func Encrypt(filename, context, value string) (string, error) {
	c, err := aead(filename, true)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, c.NonceSize())
	if _, err = io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	payload := c.Seal(nonce, nonce, []byte(value), []byte(context))
	return "v1:" + base64.StdEncoding.EncodeToString(payload), nil
}

func Decrypt(filename, context, value string) (string, error) {
	if len(value) < 3 || value[:3] != "v1:" {
		return "", errors.New("invalid tool secret")
	}
	c, err := aead(filename, false)
	if err != nil {
		return "", err
	}
	data, err := base64.StdEncoding.DecodeString(value[3:])
	if err != nil || len(data) < c.NonceSize() {
		return "", errors.New("invalid tool secret")
	}
	plain, err := c.Open(nil, data[:c.NonceSize()], data[c.NonceSize():], []byte(context))
	if err != nil {
		return "", errors.New("cannot decrypt tool secret")
	}
	return string(plain), nil
}
