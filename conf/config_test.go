package conf

import (
	"os"
	"testing"
)

func TestAssetSecretLoadsFromYAML(t *testing.T) {
	unsetAssetSecretEnv(t)
	restoreApp := App
	t.Cleanup(func() {
		App = restoreApp
	})

	if err := loadFromBytes([]byte(`asset_secret: yaml-secret`)); err != nil {
		t.Fatalf("load config: %v", err)
	}

	if App.AssetSecret != "yaml-secret" {
		t.Fatalf("AssetSecret = %q, want %q", App.AssetSecret, "yaml-secret")
	}
}

func TestAssetSecretEnvOverridesYAML(t *testing.T) {
	t.Setenv("BOOKSTARK_ASSET_SECRET", "env-secret")
	restoreApp := App
	t.Cleanup(func() {
		App = restoreApp
	})

	if err := loadFromBytes([]byte(`asset_secret: yaml-secret`)); err != nil {
		t.Fatalf("load config: %v", err)
	}

	if App.AssetSecret != "env-secret" {
		t.Fatalf("AssetSecret = %q, want %q", App.AssetSecret, "env-secret")
	}
}

func TestAssetSecretDefaultsEmpty(t *testing.T) {
	unsetAssetSecretEnv(t)
	restoreApp := App
	t.Cleanup(func() {
		App = restoreApp
	})

	if err := loadFromBytes([]byte(`{}`)); err != nil {
		t.Fatalf("load config: %v", err)
	}

	if App.AssetSecret != "" {
		t.Fatalf("AssetSecret = %q, want empty string", App.AssetSecret)
	}
}

func unsetAssetSecretEnv(t *testing.T) {
	t.Helper()

	value, ok := os.LookupEnv("BOOKSTARK_ASSET_SECRET")
	if err := os.Unsetenv("BOOKSTARK_ASSET_SECRET"); err != nil {
		t.Fatalf("unset BOOKSTARK_ASSET_SECRET: %v", err)
	}
	t.Cleanup(func() {
		if ok {
			if err := os.Setenv("BOOKSTARK_ASSET_SECRET", value); err != nil {
				t.Errorf("restore BOOKSTARK_ASSET_SECRET: %v", err)
			}
			return
		}
		if err := os.Unsetenv("BOOKSTARK_ASSET_SECRET"); err != nil {
			t.Errorf("clear BOOKSTARK_ASSET_SECRET: %v", err)
		}
	})
}
