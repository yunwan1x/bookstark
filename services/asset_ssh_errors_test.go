package services

import (
	"context"
	"errors"
	"net"
	"testing"

	"bookstark/models"
)

func TestAssetSSHErrorMessages(t *testing.T) {
	for _, tc := range []struct {
		err  error
		want string
	}{
		{errors.New("ssh: handshake failed: ssh: unable to authenticate, attempted methods [none publickey]"), "认证失败"},
		{context.DeadlineExceeded, "连接超时"},
		{&net.DNSError{Err: "timeout", IsTimeout: true}, "连接超时"},
		{errors.New("dial tcp internal-host:22: connection refused"), "SSH 连接失败"},
	} {
		if got := sanitizeSSHError(tc.err).Error(); got != tc.want {
			t.Errorf("got %q, want %q", got, tc.want)
		}
	}
	if _, err := sshAuth(models.AssetAuthKey, "invalid-private-key"); err == nil || err.Error() != "私钥解析失败" {
		t.Fatalf("invalid key should have a safe error, got %v", err)
	}
}
