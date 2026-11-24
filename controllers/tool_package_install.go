package controllers

import (
	"bookstark/internal/toolpackage"
	"bookstark/models"
	"context"
	"crypto/sha256"
	"fmt"
	"net/url"
	"strings"
)

func installToolResources(ctx context.Context, member, id int64, pkg marketTool, origin, base string, fetch toolpackage.Fetch) (string, []toolpackage.Asset, error) {
	if pkg.Distribution != "files" {
		return toolpackage.Build(ctx, pkg.Content, base, fetch)
	}
	if !toolInstanceLabel.MatchString(pkg.Package) || len(pkg.Files) == 0 || len(pkg.Files) > toolpackage.MaxFiles {
		return "", nil, fmt.Errorf("invalid file manifest")
	}
	expectedBase := origin + "/api/tool-package-assets/" + pkg.Package + "/"
	if base != expectedBase {
		return "", nil, fmt.Errorf("invalid package origin")
	}
	resources := make([]toolpackage.Asset, 0, len(pkg.Files))
	seen := map[string]bool{}
	var total int64
	entry := false
	for _, f := range pkg.Files {
		if !toolpackage.ValidName(f.Name) || seen[f.Name] || f.Size < 0 || f.Size > toolpackage.MaxFile || !toolDigest.MatchString(f.Hash) {
			return "", nil, fmt.Errorf("invalid file manifest")
		}
		seen[f.Name] = true
		var b []byte
		var err error
		if id > 0 {
			var p models.ToolPackage
			p, err = models.GetToolPackage(pkg.Package)
			if err == nil {
				b, _, err = models.ReadToolPackageFile(p, f.Name)
			}
		} else {
			u, _ := url.Parse(toolpackage.AssetURL(expectedBase, f.Name))
			var status int
			q := u.Query()
			q.Set("revision", pkg.Revision)
			u.RawQuery = q.Encode()
			b, status, err = requestMarket(ctx, origin, u.RequestURI(), "GET", nil, clientMarketToken(member, origin))
			if err == nil && status != 200 {
				err = fmt.Errorf("market_status_%d", status)
			}
		}
		if err != nil {
			return "", nil, err
		}
		total += int64(len(b))
		if total > toolpackage.MaxBytes || int64(len(b)) != f.Size || fmt.Sprintf("%x", sha256.Sum256(b)) != f.Hash {
			return "", nil, fmt.Errorf("package integrity failed")
		}
		if f.Name == pkg.Entry {
			entry = true
			if string(b) != pkg.Content {
				return "", nil, fmt.Errorf("entry mismatch")
			}
		}
		resources = append(resources, toolpackage.Asset{Name: f.Name, MIME: f.MIME, Data: b})
	}
	if !entry || !(strings.HasSuffix(strings.ToLower(pkg.Entry), ".html") || strings.HasSuffix(strings.ToLower(pkg.Entry), ".htm")) {
		return "", nil, fmt.Errorf("invalid entry")
	}
	return pkg.Content, resources, nil
}
