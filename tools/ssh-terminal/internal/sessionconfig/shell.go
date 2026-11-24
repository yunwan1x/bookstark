package sessionconfig

import (
	"fmt"
	"path"
	"strings"
)

// ShellCommand accepts one program, never a command fragment or arguments.
// Empty means the account's default shell (an SSH shell request). Absolute
// paths may contain spaces/Unicode/quotes; POSIX quoting keeps them one word.
func ShellCommand(program string) (string, error) {
	if program == "" {
		return "", nil
	}
	switch program {
	case "sh", "bash", "zsh", "fish":
	default:
		if len(program) > 512 || !path.IsAbs(program) || strings.ContainsAny(program, "\x00\r\n") {
			return "", fmt.Errorf("invalid shell program")
		}
	}
	return "exec '" + strings.ReplaceAll(program, "'", "'\\''") + "' -l", nil
}
