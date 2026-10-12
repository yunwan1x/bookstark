package controllers

import (
	"fmt"
	"reflect"
	"testing"
)

func TestPublicTagIconsUniqueAndStable(t *testing.T) {
	labels := []string{}
	for i := 0; i < 100; i++ {
		labels = append(labels, fmt.Sprintf("标签%d", i))
	}
	icons := assignPublicLabelIcons(labels)
	used := map[string]bool{"fa-border-all": true}
	for _, name := range labels {
		icon := icons[name]
		if icon == "" || used[icon] {
			t.Fatalf("missing or repeated icon: %s %s", name, icon)
		}
		used[icon] = true
	}
	for i, j := 0, len(labels)-1; i < j; i, j = i+1, j-1 {
		labels[i], labels[j] = labels[j], labels[i]
	}
	if !reflect.DeepEqual(icons, assignPublicLabelIcons(labels)) {
		t.Fatal("ordering changed assignment")
	}
}
