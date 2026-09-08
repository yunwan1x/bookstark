package models

import (
	"errors"
	"strings"
	"testing"
	"time"
)

func TestPasswordResetTokenIsHashedSingleUseAndRevokesSessions(t *testing.T) {
	initAssetTestDB(t)
	member, err := GetMemberByID(1)
	if err != nil {
		t.Fatal(err)
	}
	version, err := GetMemberAuthVersion(member.MemberID)
	if err != nil || version != 1 {
		t.Fatalf("initial auth version = %d, %v; want 1", version, err)
	}
	rawToken, _, err := CreatePasswordResetToken(member.MemberID, "192.0.2.10", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if len(rawToken) < 40 {
		t.Fatalf("token length = %d", len(rawToken))
	}
	var storedHash, storedIP string
	if err := DB.QueryRow("SELECT token_hash, created_ip FROM md_password_reset_tokens WHERE member_id = ?", member.MemberID).Scan(&storedHash, &storedIP); err != nil {
		t.Fatal(err)
	}
	if storedHash == rawToken || strings.Contains(storedHash, rawToken) || len(storedHash) != 64 {
		t.Fatalf("token was not stored as a SHA-256 hash")
	}
	if storedIP != "192.0.2.10" {
		t.Fatalf("created_ip = %q", storedIP)
	}
	if err := ResetPasswordWithToken(rawToken, "new-secret"); err != nil {
		t.Fatalf("ResetPasswordWithToken: %v", err)
	}
	member, err = GetMemberByID(member.MemberID)
	if err != nil || !member.VerifyPassword("new-secret") {
		t.Fatalf("new password was not persisted: %v", err)
	}
	version, err = GetMemberAuthVersion(member.MemberID)
	if err != nil || version != 2 {
		t.Fatalf("auth version after reset = %d, %v; want 2", version, err)
	}
	if err := ResetPasswordWithToken(rawToken, "another-secret"); !errors.Is(err, ErrPasswordResetTokenInvalid) {
		t.Fatalf("reused token error = %v", err)
	}
}

func TestCreatingPasswordResetTokenInvalidatesPreviousToken(t *testing.T) {
	initAssetTestDB(t)
	member, err := GetMemberByID(1)
	if err != nil {
		t.Fatal(err)
	}
	first, _, err := CreatePasswordResetToken(member.MemberID, "", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	second, _, err := CreatePasswordResetToken(member.MemberID, "", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if err := ResetPasswordWithToken(first, "first-password"); !errors.Is(err, ErrPasswordResetTokenInvalid) {
		t.Fatalf("superseded token error = %v", err)
	}
	if err := ResetPasswordWithToken(second, "second-password"); err != nil {
		t.Fatalf("latest token failed: %v", err)
	}
}

func TestExpiredPasswordResetTokenIsRejected(t *testing.T) {
	initAssetTestDB(t)
	member, err := GetMemberByID(1)
	if err != nil {
		t.Fatal(err)
	}
	token, _, err := CreatePasswordResetToken(member.MemberID, "", -time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if err := ResetPasswordWithToken(token, "new-password"); !errors.Is(err, ErrPasswordResetTokenInvalid) {
		t.Fatalf("expired token error = %v", err)
	}
}

func TestUpdateMemberPasswordIncrementsAuthVersion(t *testing.T) {
	initAssetTestDB(t)
	member, err := GetMemberByID(1)
	if err != nil {
		t.Fatal(err)
	}
	if err := UpdateMemberPassword(member.MemberID, "first-change"); err != nil {
		t.Fatal(err)
	}
	if err := UpdateMemberPassword(member.MemberID, "second-change"); err != nil {
		t.Fatal(err)
	}
	version, err := GetMemberAuthVersion(member.MemberID)
	if err != nil || version != 3 {
		t.Fatalf("auth version = %d, %v; want 3", version, err)
	}
}
