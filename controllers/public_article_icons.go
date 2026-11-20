package controllers

import (
	"bookstark/models"
	"hash/fnv"
	"sort"
	"strings"
)

func publicArticleIconIndex(title string) int {
	hash := fnv.New64a()
	_, _ = hash.Write([]byte(strings.TrimSpace(title)))
	return int(hash.Sum64() % uint64(len(publicArticleIcons)))
}

// Resolve collisions within the visible result set in title/identity order so
// switching its sort order does not reshuffle icons. A different result set can
// change a collision's fallback; finite icons cannot be globally unique forever.
func assignPublicArticleIcons(items []models.ShareItem) map[string]string {
	ordered := append([]models.ShareItem(nil), items...)
	sort.Slice(ordered, func(i, j int) bool {
		a, b := strings.TrimSpace(ordered[i].Title), strings.TrimSpace(ordered[j].Title)
		if a == b {
			return ordered[i].ShareIdentify < ordered[j].ShareIdentify
		}
		return a < b
	})
	result := make(map[string]string, len(items))
	used := make([]bool, len(publicArticleIcons))
	for _, item := range ordered {
		index := publicArticleIconIndex(item.Title)
		for offset := 0; offset < len(publicArticleIcons); offset++ {
			candidate := (index + offset) % len(publicArticleIcons)
			if !used[candidate] {
				index = candidate
				used[index] = true
				break
			}
		}
		result[item.ShareIdentify] = publicArticleIcons[index]
	}
	return result
}
