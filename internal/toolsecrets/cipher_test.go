package toolsecrets

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestCipherPersistsAndBindsSecrets(t *testing.T) {
	filename := filepath.Join(t.TempDir(), "key")
	value := "private-key\npassword:秘密"
	ciphertext, err := Encrypt(filename, "member:1/tool:2/data:3/name:4", value)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(ciphertext, "private-key") {
		t.Fatal("plaintext at rest")
	}
	info, _ := os.Stat(filename)
	if info.Mode().Perm() != 0600 {
		t.Fatal("key permissions", info.Mode())
	}
	plain, err := Decrypt(filename, "member:1/tool:2/data:3/name:4", ciphertext)
	if err != nil || plain != value {
		t.Fatal("reload failed", err)
	}
	for _, binding := range []string{"member:2/tool:2/data:3/name:4", "member:1/tool:3/data:3/name:4", "member:1/tool:2/data:4/name:4", "member:1/tool:2/data:3/name:5"} {
		if _, err := Decrypt(filename, binding, ciphertext); err == nil {
			t.Fatal("transplanted secret accepted")
		}
	}
	if _, err := Decrypt(filename, "member:1/tool:2/data:3/name:4", ciphertext[:len(ciphertext)-4]+"AAAA"); err == nil {
		t.Fatal("tampering accepted")
	}
	if err := os.Remove(filename); err != nil {
		t.Fatal(err)
	}
	if _, err := Decrypt(filename, "member:1/tool:2/data:3/name:4", ciphertext); err == nil {
		t.Fatal("missing key silently replaced")
	}
	if _, err := os.Stat(filename); !os.IsNotExist(err) {
		t.Fatal("read generated a new key")
	}
	if err := os.WriteFile(filename, []byte("broken"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := Encrypt(filename, "context", value); err == nil {
		t.Fatal("corrupt key silently replaced")
	}
}

func TestConcurrentFirstWriteUsesOneKey(t *testing.T) {
	filename := filepath.Join(t.TempDir(), "key")
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			c, err := Encrypt(filename, "scope", "value")
			if err != nil {
				t.Error(err)
				return
			}
			if p, err := Decrypt(filename, "scope", c); err != nil || p != "value" {
				t.Error("concurrent key mismatch", err)
			}
		}()
	}
	wg.Wait()
}
