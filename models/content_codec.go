package models

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"fmt"
	"io"
	"strings"
)

const compressedContentPrefix = "CMP:v1:gzip:"

func IsCompressedContent(content string) bool {
	return strings.HasPrefix(content, compressedContentPrefix)
}

func EncodeHTMLContent(content string) (string, error) {
	if content == "" || IsCompressedContent(content) {
		return content, nil
	}
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write([]byte(content)); err != nil {
		_ = zw.Close()
		return "", fmt.Errorf("压缩内容失败: %w", err)
	}
	if err := zw.Close(); err != nil {
		return "", fmt.Errorf("压缩内容失败: %w", err)
	}
	return compressedContentPrefix + base64.StdEncoding.EncodeToString(buf.Bytes()), nil
}

func EncodeContentForType(contentType, content string) (string, error) {
	if contentType != "html" && contentType != "richdoc" {
		return content, nil
	}
	return EncodeHTMLContent(content)
}

func DecodeCompressedContent(content string) (string, error) {
	if !IsCompressedContent(content) {
		return content, nil
	}
	gzipBytes, err := CompressedContentGzipBytes(content)
	if err != nil {
		return "", err
	}
	zr, err := gzip.NewReader(bytes.NewReader(gzipBytes))
	if err != nil {
		return "", fmt.Errorf("解压内容失败: %w", err)
	}
	defer zr.Close()
	plain, err := io.ReadAll(zr)
	if err != nil {
		return "", fmt.Errorf("解压内容失败: %w", err)
	}
	return string(plain), nil
}

func DecodeContentForType(contentType, content string) (string, error) {
	if contentType != "html" && contentType != "richdoc" {
		return content, nil
	}
	return DecodeCompressedContent(content)
}

func CompressedContentGzipBytes(content string) ([]byte, error) {
	if !IsCompressedContent(content) {
		return nil, fmt.Errorf("内容未压缩")
	}
	data := strings.TrimPrefix(content, compressedContentPrefix)
	gzipBytes, err := base64.StdEncoding.DecodeString(data)
	if err != nil {
		return nil, fmt.Errorf("解码压缩内容失败: %w", err)
	}
	return gzipBytes, nil
}
