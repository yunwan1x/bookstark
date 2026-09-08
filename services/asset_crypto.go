package services

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
)

type AssetCredentialCipher struct {
	aead cipher.AEAD
}

func NewAssetCredentialCipher(secret string) (*AssetCredentialCipher, error) {
	key, err := assetSecretKey(secret)
	if err != nil {
		return nil, err
	}
	aead, err := newAssetAEAD(key)
	if err != nil {
		return nil, err
	}
	return &AssetCredentialCipher{aead: aead}, nil
}

func assetSecretKey(secret string) ([]byte, error) {
	if secret == "" {
		return nil, fmt.Errorf("asset secret is required")
	}
	sum := sha256.Sum256([]byte(secret))
	return sum[:], nil
}

func newAssetAEAD(key []byte) (cipher.AEAD, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create asset cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("create asset gcm: %w", err)
	}
	return aead, nil
}

func (c *AssetCredentialCipher) Encrypt(plaintext string) (string, error) {
	nonce := make([]byte, c.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("create nonce: %w", err)
	}
	ciphertext := c.aead.Seal(nil, nonce, []byte(plaintext), nil)
	payload := append(nonce, ciphertext...)
	return base64.StdEncoding.EncodeToString(payload), nil
}

func (c *AssetCredentialCipher) Decrypt(encoded string) (string, error) {
	payload, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return "", fmt.Errorf("decode credential: %w", err)
	}
	nonceSize := c.aead.NonceSize()
	if len(payload) <= nonceSize {
		return "", fmt.Errorf("credential payload too short")
	}
	nonce := payload[:nonceSize]
	ciphertext := payload[nonceSize:]
	plaintext, err := c.aead.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", fmt.Errorf("decrypt credential: %w", err)
	}
	return string(plaintext), nil
}

func CredentialHint(authType string) string {
	if authType == "key" {
		return "private key saved"
	}
	return "password saved"
}
