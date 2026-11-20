package controllers

import (
	"bookstark/models"
	"fmt"
	"reflect"
	"strings"
	"testing"
)

func TestPublicArticleIconCatalog(t *testing.T) {
	if len(publicArticleIcons) != 1601 {
		t.Fatalf("unexpected bundled glyph count: %d", len(publicArticleIcons))
	}
	seen := map[string]bool{}
	for _, icon := range publicArticleIcons {
		if seen[icon] || !(strings.HasPrefix(icon, "fa-solid fa-") || strings.HasPrefix(icon, "fa-regular fa-")) {
			t.Fatal("duplicate or unsupported icon", icon)
		}
		seen[icon] = true
	}
}

func TestPublicArticleIconsTitleHashAndCollisions(t *testing.T) {
	first := models.ShareItem{Title: "同一标题", ShareIdentify: "one"}
	if got := assignPublicArticleIcons([]models.ShareItem{first})["one"]; got != publicArticleIcons[publicArticleIconIndex(first.Title)] {
		t.Fatal("single article must use title hash")
	}
	buckets := map[int]string{}
	var a, b string
	for i := 0; i <= len(publicArticleIcons); i++ {
		title := fmt.Sprintf("article-%d", i)
		index := publicArticleIconIndex(title)
		if previous, ok := buckets[index]; ok {
			a, b = previous, title
			break
		}
		buckets[index] = title
	}
	if a == "" {
		t.Fatal("collision fixture missing")
	}
	items := []models.ShareItem{first, {Title: first.Title, ShareIdentify: "two"}, {Title: a, ShareIdentify: "a"}, {Title: b, ShareIdentify: "b"}, {Title: "", ShareIdentify: "empty"}}
	got := assignPublicArticleIcons(items)
	used := map[string]bool{}
	for _, item := range items {
		icon := got[item.ShareIdentify]
		if icon == "" || used[icon] {
			t.Fatal("same-page collision", item, icon)
		}
		used[icon] = true
	}
	for i, j := 0, len(items)-1; i < j; i, j = i+1, j-1 {
		items[i], items[j] = items[j], items[i]
	}
	if !reflect.DeepEqual(got, assignPublicArticleIcons(items)) {
		t.Fatal("sort order changed icons")
	}
	// Exercise every slot and the bounded fallback when there are more articles than icons.
	crowded := make([]models.ShareItem, len(publicArticleIcons)+1)
	for i := range crowded {
		crowded[i] = models.ShareItem{Title: "same", ShareIdentify: fmt.Sprintf("%05d", i)}
	}
	result := assignPublicArticleIcons(crowded)
	unique := map[string]bool{}
	for _, icon := range result {
		if icon == "" {
			t.Fatal("empty icon")
		}
		unique[icon] = true
	}
	if len(unique) != len(publicArticleIcons) {
		t.Fatal("pool was not fully used")
	}
}
