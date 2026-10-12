package models

import (
	"fmt"
	"reflect"
	"testing"
)

func TestPublicTagsConfiguration(t *testing.T) {
	initAssetTestDB(t)
	for i := 0; i < 12; i++ {
		b := &Blog{BlogTitle: fmt.Sprint(i), BlogIdentify: fmt.Sprintf("tag-%d", i), MemberID: 1, BlogType: "article", Visibility: 1}
		if err := b.Insert(); err != nil {
			t.Fatal(err)
		}
		if err := BindLabelsFromNames(b.BlogID, "blog", fmt.Sprintf("Tag%02d,Popular", i)); err != nil {
			t.Fatal(err)
		}
	}
	labels, err := PublicFeedLabels("article")
	if err != nil || len(labels) != 10 || labels[0] != "Popular" {
		t.Fatalf("auto: %v %v", labels, err)
	}
	if err := BatchUpdateSettings(map[string]string{"public_feed_tags_article": `{"mode":"manual","labels":["Tag11","Tag00","Missing"]}`}); err != nil {
		t.Fatal(err)
	}
	labels, err = PublicFeedLabels("article")
	if err != nil || !reflect.DeepEqual(labels, []string{"Tag11", "Tag00"}) {
		t.Fatalf("manual order: %v %v", labels, err)
	}
	if err := BatchUpdateSettings(map[string]string{"public_feed_tags_article": `{"mode":"manual","labels":[]}`}); err != nil {
		t.Fatal(err)
	}
	labels, err = PublicFeedLabels("article")
	if err != nil || len(labels) != 0 {
		t.Fatal("empty manual reverted to auto", labels, err)
	}
	if GetPublicTagConfig("note").Mode != "auto" {
		t.Fatal("settings crossed types")
	}
	for _, raw := range []string{`null`, `{"mode":"other"}`, `{"mode":"manual","labels":["x","x"]}`, `{"mode":"manual","labels":[""]}`} {
		if ValidatePublicTagConfig(raw) == nil {
			t.Fatalf("accepted %s", raw)
		}
	}
}
