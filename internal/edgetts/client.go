// Package edgetts provides the text-only adapter used by BookStark.
// See UPSTREAM.md and LICENSE for the pinned MIT protocol implementation.
package edgetts

import (
	"bookstark/internal/edgetts/internal/communicate"
	"bookstark/internal/edgetts/internal/communicateOption"
	"context"
	"io"
)

func WriteTo(ctx context.Context, text, voice, proxy string, w io.Writer) error {
	c, err := communicate.NewCommunicate(communicate.InputText, text, &communicateOption.CommunicateOption{Voice: voice, Rate: "+0%", Pitch: "+0Hz", Volume: "+0%", HttpProxy: proxy})
	if err != nil {
		return err
	}
	_, err = c.WriteStreamToContext(ctx, w)
	return err
}
