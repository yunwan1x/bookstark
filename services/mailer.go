package services

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"net/mail"
	"net/smtp"
	"strings"
	"time"

	"bookstark/models"
)

type MailMessage struct {
	To       string
	Subject  string
	TextBody string
	HTMLBody string
}

func SendConfiguredMail(ctx context.Context, message MailMessage) error {
	return SendMail(ctx, models.GetMailSettings(), message)
}

func SendMail(ctx context.Context, cfg models.MailSettings, message MailMessage) error {
	if !cfg.Ready() {
		return errors.New("邮件服务尚未完整配置")
	}
	to, err := mail.ParseAddress(strings.TrimSpace(message.To))
	if err != nil || to.Address == "" {
		return errors.New("收件邮箱无效")
	}
	from, err := mail.ParseAddress(strings.TrimSpace(cfg.FromAddress))
	if err != nil || from.Address == "" {
		return errors.New("发件邮箱无效")
	}
	if strings.ContainsAny(message.Subject, "\r\n") {
		return errors.New("邮件标题无效")
	}

	address := net.JoinHostPort(cfg.Host, fmt.Sprintf("%d", cfg.Port))
	dialer := &net.Dialer{Timeout: cfg.Timeout}
	var conn net.Conn
	if cfg.Encryption == "tls" {
		conn, err = tls.DialWithDialer(dialer, "tcp", address, &tls.Config{
			ServerName: cfg.Host,
			MinVersion: tls.VersionTLS12,
		})
	} else {
		conn, err = dialer.DialContext(ctx, "tcp", address)
	}
	if err != nil {
		return fmt.Errorf("连接 SMTP 服务器失败: %w", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(cfg.Timeout))

	client, err := smtp.NewClient(conn, cfg.Host)
	if err != nil {
		return fmt.Errorf("初始化 SMTP 会话失败: %w", err)
	}
	defer client.Close()
	if cfg.Encryption == "starttls" {
		if ok, _ := client.Extension("STARTTLS"); !ok {
			return errors.New("SMTP 服务器不支持 STARTTLS")
		}
		if err := client.StartTLS(&tls.Config{ServerName: cfg.Host, MinVersion: tls.VersionTLS12}); err != nil {
			return fmt.Errorf("启用 STARTTLS 失败: %w", err)
		}
	}
	if cfg.Username != "" {
		if ok, _ := client.Extension("AUTH"); !ok {
			return errors.New("SMTP 服务器不支持身份认证")
		}
		if err := client.Auth(smtp.PlainAuth("", cfg.Username, cfg.Password, cfg.Host)); err != nil {
			return fmt.Errorf("SMTP 认证失败: %w", err)
		}
	}
	if err := client.Mail(from.Address); err != nil {
		return fmt.Errorf("设置发件人失败: %w", err)
	}
	if err := client.Rcpt(to.Address); err != nil {
		return fmt.Errorf("设置收件人失败: %w", err)
	}
	w, err := client.Data()
	if err != nil {
		return fmt.Errorf("创建邮件正文失败: %w", err)
	}
	if _, err := io.Copy(w, bytes.NewReader(buildMIMEMessage(cfg, to.Address, message))); err != nil {
		_ = w.Close()
		return fmt.Errorf("写入邮件正文失败: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("提交邮件失败: %w", err)
	}
	if err := client.Quit(); err != nil {
		return fmt.Errorf("结束 SMTP 会话失败: %w", err)
	}
	return nil
}

func buildMIMEMessage(cfg models.MailSettings, to string, message MailMessage) []byte {
	boundary := "bookstark-" + base64.RawURLEncoding.EncodeToString([]byte(fmt.Sprintf("%d", time.Now().UnixNano())))
	from := &mail.Address{Name: cfg.FromName, Address: cfg.FromAddress}
	fromHeader := from.String()
	var b strings.Builder
	b.WriteString("From: " + fromHeader + "\r\n")
	b.WriteString("To: " + to + "\r\n")
	b.WriteString("Subject: " + mime.QEncoding.Encode("UTF-8", message.Subject) + "\r\n")
	b.WriteString("Date: " + time.Now().Format(time.RFC1123Z) + "\r\n")
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: multipart/alternative; boundary=\"" + boundary + "\"\r\n\r\n")
	b.WriteString("--" + boundary + "\r\n")
	b.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	b.WriteString("Content-Transfer-Encoding: 8bit\r\n\r\n")
	b.WriteString(message.TextBody + "\r\n")
	b.WriteString("--" + boundary + "\r\n")
	b.WriteString("Content-Type: text/html; charset=UTF-8\r\n")
	b.WriteString("Content-Transfer-Encoding: 8bit\r\n\r\n")
	b.WriteString(message.HTMLBody + "\r\n")
	b.WriteString("--" + boundary + "--\r\n")
	return []byte(b.String())
}
