package sessionconfig

import "testing"

func TestShellProgramDoesNotAcceptCommands(t *testing.T) {
	for _, program := range []string{"sh", "bash", "zsh", "fish", "/bin/bash", "/usr/local/bin/fish", "/home/用户/my shell", "/tmp/$(id); bash"} {
		command, err := ShellCommand(program)
		if err != nil || command != "exec '"+program+"' -l" {
			t.Fatalf("%q: %q %v", program, command, err)
		}
	}
	if command, err := ShellCommand(""); err != nil || command != "" {
		t.Fatalf("default shell %q %v", command, err)
	}
	if command, err := ShellCommand("/tmp/it's a shell"); err != nil || command != "exec '/tmp/it'\\''s a shell' -l" {
		t.Fatalf("unescaped path %q %v", command, err)
	}
	for _, program := range []string{"bash -c whoami", "/bin/zsh\nwhoami", "relative/shell", "-bash", "/bin/bash\x00"} {
		if _, err := ShellCommand(program); err == nil {
			t.Fatalf("accepted command fragment %q", program)
		}
	}
}
