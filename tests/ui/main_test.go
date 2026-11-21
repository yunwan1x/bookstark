package ui

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

// Go starts tests in the package directory. Walk to go.mod rather than depending
// on source paths (which may be stripped by -trimpath) or the invoking shell.
func TestMain(m *testing.M) {
	root, err := os.Getwd()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	for {
		if _, err := os.Stat(filepath.Join(root, "go.mod")); err == nil {
			break
		}
		parent := filepath.Dir(root)
		if parent == root {
			fmt.Fprintln(os.Stderr, "cannot locate repository go.mod")
			os.Exit(1)
		}
		root = parent
	}
	if err := os.Chdir(root); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	os.Exit(m.Run())
}
