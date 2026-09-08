package services

import (
	"fmt"
	"io"
	"io/fs"
	"net"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"

	"bookstark/models"
)

type AssetFileEntry struct {
	Name    string    `json:"name"`
	Path    string    `json:"path"`
	Type    string    `json:"type"`
	Size    int64     `json:"size"`
	Mode    string    `json:"mode"`
	ModTime time.Time `json:"mod_time"`
}

type AssetFileManager struct {
	Timeout time.Duration
}

type AssetFileReadHandle struct {
	file       *sftp.File
	sftpClient *sftp.Client
	sshClient  *ssh.Client
	Size       int64
}

func (h *AssetFileReadHandle) Read(p []byte) (int, error) {
	return h.file.Read(p)
}

func (h *AssetFileReadHandle) Seek(offset int64, whence int) (int64, error) {
	return h.file.Seek(offset, whence)
}

func (h *AssetFileReadHandle) Close() error {
	var err error
	if h.file != nil {
		err = h.file.Close()
	}
	if h.sftpClient != nil {
		if closeErr := h.sftpClient.Close(); err == nil {
			err = closeErr
		}
	}
	if h.sshClient != nil {
		if closeErr := h.sshClient.Close(); err == nil {
			err = closeErr
		}
	}
	return err
}

func (m AssetFileManager) List(host *models.AssetSSHHost, credential, remotePath string) ([]AssetFileEntry, error) {
	if remotePath == "" {
		remotePath = defaultRemotePath(host)
	}
	return withSFTPOrShell(m, host, credential, func(client *sftp.Client) ([]AssetFileEntry, error) {
		entries, err := client.ReadDir(remotePath)
		if err != nil {
			return nil, err
		}
		result := make([]AssetFileEntry, 0, len(entries))
		for _, entry := range entries {
			result = append(result, fileInfoEntry(remoteJoin(remotePath, entry.Name()), entry))
		}
		return result, nil
	}, func(r SSHRunner) ([]AssetFileEntry, error) {
		return m.shellList(r, host, credential, remotePath)
	})
}

func (m AssetFileManager) Mkdir(host *models.AssetSSHHost, credential, remotePath string) error {
	return m.withSFTPOrShellErr(host, credential, func(client *sftp.Client) error {
		return client.MkdirAll(remotePath)
	}, func(r SSHRunner) error {
		_, err := r.RunCommand(host, credential, "mkdir -p -- "+shellQuote(remotePath))
		return err
	})
}

func (m AssetFileManager) Rename(host *models.AssetSSHHost, credential, oldPath, newPath string) error {
	return m.withSFTPOrShellErr(host, credential, func(client *sftp.Client) error {
		return client.Rename(oldPath, newPath)
	}, func(r SSHRunner) error {
		_, err := r.RunCommand(host, credential, "mv -- "+shellQuote(oldPath)+" "+shellQuote(newPath))
		return err
	})
}

func (m AssetFileManager) Copy(host *models.AssetSSHHost, credential, srcPath, dstPath string) error {
	client, err := m.dial(host, credential)
	if err == nil {
		sftpClient, sftpErr := sftp.NewClient(client)
		if sftpErr == nil {
			info, statErr := sftpClient.Stat(srcPath)
			if statErr != nil {
				_ = sftpClient.Close()
				_ = client.Close()
				return statErr
			}
			if !info.IsDir() {
				copyErr := copySFTPFile(sftpClient, srcPath, dstPath)
				_ = sftpClient.Close()
				_ = client.Close()
				return copyErr
			}
			_ = sftpClient.Close()
		}
		_ = client.Close()
	} else {
		return err
	}
	r := SSHRunner{Timeout: m.timeout()}
	_, err = r.RunCommand(host, credential, "cp -a -- "+shellQuote(srcPath)+" "+shellQuote(dstPath))
	return err
}

func (m AssetFileManager) Remove(host *models.AssetSSHHost, credential, remotePath string, recursive bool) error {
	return m.withSFTPOrShellErr(host, credential, func(client *sftp.Client) error {
		info, err := client.Stat(remotePath)
		if err != nil {
			return err
		}
		if info.IsDir() {
			if !recursive {
				return client.RemoveDirectory(remotePath)
			}
			return removeSFTPDir(client, remotePath)
		}
		return client.Remove(remotePath)
	}, func(r SSHRunner) error {
		cmd := "rm -- " + shellQuote(remotePath)
		if recursive {
			cmd = "rm -rf -- " + shellQuote(remotePath)
		}
		_, err := r.RunCommand(host, credential, cmd)
		return err
	})
}

func (m AssetFileManager) Chmod(host *models.AssetSSHHost, credential, remotePath, mode string) error {
	parsed, err := strconv.ParseUint(mode, 8, 32)
	if err != nil || parsed > 07777 {
		return fmt.Errorf("权限格式无效")
	}
	return m.withSFTPOrShellErr(host, credential, func(client *sftp.Client) error {
		return client.Chmod(remotePath, fs.FileMode(parsed))
	}, func(r SSHRunner) error {
		_, err := r.RunCommand(host, credential, "chmod -- "+shellQuote(fmt.Sprintf("%04o", parsed))+" "+shellQuote(remotePath))
		return err
	})
}

func (m AssetFileManager) Download(host *models.AssetSSHHost, credential, remotePath string, w io.Writer) error {
	return m.withSFTPOrShellErr(host, credential, func(client *sftp.Client) error {
		f, err := client.Open(remotePath)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = io.Copy(w, f)
		return err
	}, func(r SSHRunner) error {
		return r.StreamCommand(noCancelContext{}, host, credential, "cat -- "+shellQuote(remotePath), func(chunk []byte) error {
			_, err := w.Write(chunk)
			return err
		})
	})
}

func (m AssetFileManager) OpenReadHandle(host *models.AssetSSHHost, credential, remotePath string) (*AssetFileReadHandle, error) {
	client, err := m.dial(host, credential)
	if err != nil {
		return nil, err
	}
	sftpClient, err := sftp.NewClient(client)
	if err != nil {
		_ = client.Close()
		return nil, err
	}
	f, err := sftpClient.Open(remotePath)
	if err != nil {
		_ = sftpClient.Close()
		_ = client.Close()
		return nil, err
	}
	info, err := f.Stat()
	if err != nil {
		_ = f.Close()
		_ = sftpClient.Close()
		_ = client.Close()
		return nil, err
	}
	if info.IsDir() {
		_ = f.Close()
		_ = sftpClient.Close()
		_ = client.Close()
		return nil, fs.ErrInvalid
	}
	return &AssetFileReadHandle{
		file:       f,
		sftpClient: sftpClient,
		sshClient:  client,
		Size:       info.Size(),
	}, nil
}

func (m AssetFileManager) Upload(host *models.AssetSSHHost, credential, remotePath string, r io.Reader) error {
	return m.withSFTPOrShellErr(host, credential, func(client *sftp.Client) error {
		f, err := client.Create(remotePath)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = io.Copy(f, r)
		return err
	}, func(_ SSHRunner) error {
		client, err := m.dial(host, credential)
		if err != nil {
			return err
		}
		defer client.Close()
		session, err := client.NewSession()
		if err != nil {
			return err
		}
		defer session.Close()
		stdin, err := session.StdinPipe()
		if err != nil {
			return err
		}
		copyErr := make(chan error, 1)
		go func() {
			_, err := io.Copy(stdin, r)
			_ = stdin.Close()
			copyErr <- err
		}()
		runErr := session.Run("cat > " + shellQuote(remotePath))
		if err := <-copyErr; err != nil {
			return err
		}
		return runErr
	})
}

func withSFTPOrShell[T any](m AssetFileManager, host *models.AssetSSHHost, credential string, sftpFn func(*sftp.Client) (T, error), shellFn func(SSHRunner) (T, error)) (T, error) {
	var zero T
	client, err := m.dial(host, credential)
	if err == nil {
		sftpClient, sftpErr := sftp.NewClient(client)
		if sftpErr == nil {
			defer sftpClient.Close()
			defer client.Close()
			value, opErr := sftpFn(sftpClient)
			if opErr == nil {
				return value, nil
			}
			return zero, opErr
		} else {
			_ = client.Close()
		}
	} else if shellFn == nil {
		return zero, err
	}
	if shellFn == nil {
		return zero, err
	}
	return shellFn(SSHRunner{Timeout: m.timeout()})
}

func (m AssetFileManager) withSFTPOrShellErr(host *models.AssetSSHHost, credential string, sftpFn func(*sftp.Client) error, shellFn func(SSHRunner) error) error {
	_, err := withSFTPOrShell(m, host, credential, func(client *sftp.Client) (struct{}, error) {
		return struct{}{}, sftpFn(client)
	}, func(r SSHRunner) (struct{}, error) {
		return struct{}{}, shellFn(r)
	})
	return err
}

func (m AssetFileManager) dial(host *models.AssetSSHHost, credential string) (*ssh.Client, error) {
	auth, err := sshAuth(host.AuthType, credential)
	if err != nil {
		return nil, err
	}
	config := &ssh.ClientConfig{
		User:            host.Username,
		Auth:            []ssh.AuthMethod{auth},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         m.timeout(),
	}
	client, err := ssh.Dial("tcp", net.JoinHostPort(host.Host, fmt.Sprintf("%d", host.Port)), config)
	if err != nil {
		return nil, sanitizeSSHError(err)
	}
	return client, nil
}

func (m AssetFileManager) timeout() time.Duration {
	if m.Timeout > 0 {
		return m.Timeout
	}
	return 10 * time.Second
}

func (m AssetFileManager) shellList(r SSHRunner, host *models.AssetSSHHost, credential, remotePath string) ([]AssetFileEntry, error) {
	cmd := "find " + shellQuote(remotePath) + " -mindepth 1 -maxdepth 1 -printf '%f\\0%p\\0%y\\0%s\\0%m\\0%T@\\0'"
	out, err := r.RunCommand(host, credential, cmd)
	if err != nil {
		return nil, err
	}
	parts := strings.Split(out, "\x00")
	result := []AssetFileEntry{}
	for i := 0; i+5 < len(parts); i += 6 {
		size, _ := strconv.ParseInt(parts[i+3], 10, 64)
		mode := parts[i+4]
		seconds, _ := strconv.ParseFloat(parts[i+5], 64)
		result = append(result, AssetFileEntry{
			Name:    parts[i],
			Path:    parts[i+1],
			Type:    shellFileType(parts[i+2]),
			Size:    size,
			Mode:    normalizeMode(mode),
			ModTime: time.Unix(int64(seconds), int64((seconds-float64(int64(seconds)))*1e9)),
		})
	}
	return result, nil
}

func fileInfoEntry(remotePath string, info interface {
	Name() string
	Size() int64
	Mode() fs.FileMode
	ModTime() time.Time
	IsDir() bool
}) AssetFileEntry {
	entryType := "file"
	mode := info.Mode()
	if info.IsDir() {
		entryType = "dir"
	} else if mode&fs.ModeSymlink != 0 {
		entryType = "symlink"
	} else if !mode.IsRegular() {
		entryType = "other"
	}
	return AssetFileEntry{
		Name:    info.Name(),
		Path:    remotePath,
		Type:    entryType,
		Size:    info.Size(),
		Mode:    fmt.Sprintf("%04o", uint32(mode.Perm())),
		ModTime: info.ModTime(),
	}
}

func removeSFTPDir(client *sftp.Client, remotePath string) error {
	entries, err := client.ReadDir(remotePath)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		child := remoteJoin(remotePath, entry.Name())
		if entry.IsDir() {
			if err := removeSFTPDir(client, child); err != nil {
				return err
			}
			continue
		}
		if err := client.Remove(child); err != nil {
			return err
		}
	}
	return client.RemoveDirectory(remotePath)
}

func copySFTPFile(client *sftp.Client, srcPath, dstPath string) error {
	src, err := client.Open(srcPath)
	if err != nil {
		return err
	}
	defer src.Close()
	dst, err := client.Create(dstPath)
	if err != nil {
		return err
	}
	defer dst.Close()
	_, err = io.Copy(dst, src)
	return err
}

func defaultRemotePath(host *models.AssetSSHHost) string {
	if strings.TrimSpace(host.Cwd) != "" {
		return strings.TrimSpace(host.Cwd)
	}
	return "."
}

func remoteJoin(base, name string) string {
	if base == "" || base == "." {
		return name
	}
	return path.Join(base, name)
}

func shellQuote(value string) string {
	if value == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func shellFileType(value string) string {
	switch value {
	case "d":
		return "dir"
	case "l":
		return "symlink"
	case "f":
		return "file"
	default:
		return "other"
	}
}

func normalizeMode(value string) string {
	if value == "" {
		return "0000"
	}
	n, err := strconv.ParseUint(value, 8, 32)
	if err != nil {
		return value
	}
	return fmt.Sprintf("%04o", n)
}

type noCancelContext struct{}

func (noCancelContext) Deadline() (time.Time, bool) { return time.Time{}, false }
func (noCancelContext) Done() <-chan struct{}       { return nil }
func (noCancelContext) Err() error                  { return nil }
func (noCancelContext) Value(any) any               { return nil }
