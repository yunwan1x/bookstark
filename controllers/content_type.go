package controllers

import (
	"fmt"

	"bookstark/models"
)

func isSupportedDocumentType(contentType string) bool {
	switch contentType {
	case "", "markdown", "html", "spreadsheet", "drawing", "mindmap", models.RichDocumentType, models.PresentationType:
		return true
	default:
		return false
	}
}

func validateContentForType(contentType, content string) error {
	if contentType == models.RichDocumentType {
		return models.ValidateRichDocument(content)
	}
	if contentType == models.PresentationType {
		return models.ValidatePresentation(content)
	}
	return nil
}

func encodeContentBeforeEncryption(contentType, content string) (string, error) {
	encoded, err := models.EncodeContentForType(contentType, content)
	if err != nil {
		return "", fmt.Errorf("编码内容失败: %w", err)
	}
	return encoded, nil
}
