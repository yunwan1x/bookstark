package services

import (
	"encoding/base64"
	"testing"
)

func TestAssetCredentialCipherRoundTrip(t *testing.T) {
	cipher, err := NewAssetCredentialCipher("12345678901234567890123456789012")
	if err != nil {
		t.Fatalf("NewAssetCredentialCipher() error = %v", err)
	}
	encrypted, err := cipher.Encrypt("super-secret")
	if err != nil {
		t.Fatalf("Encrypt() error = %v", err)
	}
	if encrypted == "" || encrypted == "super-secret" {
		t.Fatalf("encrypted value %q must be non-empty and not plaintext", encrypted)
	}
	decrypted, err := cipher.Decrypt(encrypted)
	if err != nil {
		t.Fatalf("Decrypt() error = %v", err)
	}
	if decrypted != "super-secret" {
		t.Fatalf("decrypted = %q, want super-secret", decrypted)
	}
}

func TestAssetCredentialCipherAcceptsArbitrarySecret(t *testing.T) {
	cipher, err := NewAssetCredentialCipher("short")
	if err != nil {
		t.Fatalf("NewAssetCredentialCipher(short) error = %v", err)
	}
	encrypted, err := cipher.Encrypt("super-secret")
	if err != nil {
		t.Fatalf("Encrypt() error = %v", err)
	}
	decrypted, err := cipher.Decrypt(encrypted)
	if err != nil {
		t.Fatalf("Decrypt() error = %v", err)
	}
	if decrypted != "super-secret" {
		t.Fatalf("decrypted = %q, want super-secret", decrypted)
	}
}

func TestAssetCredentialCipherAcceptsBase64LookingSecret(t *testing.T) {
	key := base64.StdEncoding.EncodeToString([]byte("12345678901234567890123456789012"))
	cipher, err := NewAssetCredentialCipher(key)
	if err != nil {
		t.Fatalf("NewAssetCredentialCipher(base64-looking secret) error = %v", err)
	}
	encrypted, err := cipher.Encrypt("super-secret")
	if err != nil {
		t.Fatalf("Encrypt() error = %v", err)
	}
	decrypted, err := cipher.Decrypt(encrypted)
	if err != nil {
		t.Fatalf("Decrypt() error = %v", err)
	}
	if decrypted != "super-secret" {
		t.Fatalf("decrypted = %q, want super-secret", decrypted)
	}
}

func TestAssetCredentialCipherRejectsEmptySecret(t *testing.T) {
	if _, err := NewAssetCredentialCipher(""); err == nil {
		t.Fatal("NewAssetCredentialCipher(empty) error = nil, want error")
	}
}

func TestAssetCredentialCipherWrongKeyFails(t *testing.T) {
	first, err := NewAssetCredentialCipher("12345678901234567890123456789012")
	if err != nil {
		t.Fatalf("first cipher error = %v", err)
	}
	second, err := NewAssetCredentialCipher("abcdefghijklmnopabcdefghijklmnop")
	if err != nil {
		t.Fatalf("second cipher error = %v", err)
	}
	encrypted, err := first.Encrypt("secret")
	if err != nil {
		t.Fatalf("Encrypt() error = %v", err)
	}
	if _, err := second.Decrypt(encrypted); err == nil {
		t.Fatal("Decrypt() with wrong key error = nil, want error")
	}
}

func TestCredentialHint(t *testing.T) {
	if got := CredentialHint("key"); got != "private key saved" {
		t.Fatalf("CredentialHint(key) = %q, want private key saved", got)
	}
	if got := CredentialHint("password"); got != "password saved" {
		t.Fatalf("CredentialHint(password) = %q, want password saved", got)
	}
}
