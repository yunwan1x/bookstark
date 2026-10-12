package models

import (
	"encoding/json"
	"fmt"
)

type PublicTagConfig struct {
	Mode   string   `json:"mode"`
	Labels []string `json:"labels"`
}
type PublicTagOption struct {
	Name  string
	Count int
}
type PublicTagSection struct {
	Kind    string
	Config  PublicTagConfig
	Options []PublicTagOption
	Value   string
}

func ValidatePublicTagConfig(value string) error {
	var cfg PublicTagConfig
	if len(value) > 32000 || json.Unmarshal([]byte(value), &cfg) != nil || (cfg.Mode != "auto" && cfg.Mode != "manual") || len(cfg.Labels) > 100 {
		return fmt.Errorf("invalid public tag configuration")
	}
	seen := map[string]bool{}
	for _, s := range cfg.Labels {
		if s == "" || len(s) > 200 || seen[s] {
			return fmt.Errorf("invalid or duplicate public tag")
		}
		seen[s] = true
	}
	return nil
}

func GetPublicTagConfig(kind string) PublicTagConfig {
	cfg := PublicTagConfig{Mode: "auto", Labels: []string{}}
	raw := GetSetting("public_feed_tags_" + kind)
	if raw != "" && ValidatePublicTagConfig(raw) == nil {
		_ = json.Unmarshal([]byte(raw), &cfg)
	}
	return cfg
}

// Counts and choices include only publicly accessible, non-password-protected content.
func PublicTagOptions(kind string) ([]PublicTagOption, error) {
	rows, err := DB.Query(`SELECT l.label_name,COUNT(DISTINCT r.resource_id) FROM md_label l JOIN md_label_relation r ON r.label_id=l.label_id WHERE
 (? IN ('article','note') AND r.relation_type='blog' AND EXISTS (SELECT 1 FROM md_blogs b WHERE b.blog_id=r.resource_id AND b.visibility=1 AND COALESCE(b.blog_type,'article')=? AND COALESCE(b.password,'')='')) OR
 (?='book' AND r.relation_type='book' AND EXISTS (SELECT 1 FROM md_shares s JOIN md_books b ON b.book_id=s.target_id WHERE s.share_type='book' AND s.target_id=r.resource_id)) OR
 (?='bookmark' AND r.relation_type='bookmark' AND EXISTS (SELECT 1 FROM md_bookmark b WHERE b.bookmark_id=r.resource_id AND b.is_public=1))
 GROUP BY l.label_name ORDER BY COUNT(DISTINCT r.resource_id) DESC,l.label_name ASC`, kind, kind, kind, kind)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	options := []PublicTagOption{}
	for rows.Next() {
		var o PublicTagOption
		if err := rows.Scan(&o.Name, &o.Count); err != nil {
			return nil, err
		}
		options = append(options, o)
	}
	return options, rows.Err()
}

func PublicFeedLabels(kind string) ([]string, error) {
	options, err := PublicTagOptions(kind)
	if err != nil {
		return nil, err
	}
	cfg := GetPublicTagConfig(kind)
	labels := []string{}
	if cfg.Mode == "auto" {
		for i, o := range options {
			if i == 10 {
				break
			}
			labels = append(labels, o.Name)
		}
		return labels, nil
	}
	available := map[string]bool{}
	for _, o := range options {
		available[o.Name] = true
	}
	for _, name := range cfg.Labels {
		if available[name] {
			labels = append(labels, name)
		}
	}
	return labels, nil
}

func PublicTagSections() ([]PublicTagSection, error) {
	sections := []PublicTagSection{}
	for _, kind := range []string{"article", "note", "book", "bookmark"} {
		options, err := PublicTagOptions(kind)
		if err != nil {
			return nil, err
		}
		cfg := GetPublicTagConfig(kind)
		raw, _ := json.Marshal(cfg)
		sections = append(sections, PublicTagSection{Kind: kind, Config: cfg, Options: options, Value: string(raw)})
	}
	return sections, nil
}
