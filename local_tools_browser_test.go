package main

import "testing"

func TestLocalToolsBrowser(t *testing.T) {
	runIsolatedBrowser(t, "local_tools_browser_test.cjs")
}
