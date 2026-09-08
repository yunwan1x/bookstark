package services

import (
	"context"
	"errors"
	"io"
	"os"
	"path"
	"sync"
	"time"

	"bookstark/models"
	"golang.org/x/net/webdav"
)

type davMemberContextKey struct{}
type davRequestStateContextKey struct{}

type DAVRequestState struct {
	mu  sync.Mutex
	err error
}

func NewDAVRequestState() *DAVRequestState {
	return &DAVRequestState{}
}

func WithDAVRequestState(ctx context.Context, state *DAVRequestState) context.Context {
	return context.WithValue(ctx, davRequestStateContextKey{}, state)
}

func (s *DAVRequestState) Fail(err error) {
	if s == nil || err == nil {
		return
	}
	s.mu.Lock()
	if s.err == nil {
		s.err = err
	}
	s.mu.Unlock()
}

func (s *DAVRequestState) Err() error {
	if s == nil {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.err
}

func WithDAVMember(ctx context.Context, memberID int64) context.Context {
	return context.WithValue(ctx, davMemberContextKey{}, memberID)
}

type LocalDAVFileSystem struct{}

func (LocalDAVFileSystem) Mkdir(ctx context.Context, name string, _ os.FileMode) error {
	_, err := models.CreateDAVDirectory(davMemberID(ctx), name)
	return davFileError(err)
}

func (LocalDAVFileSystem) OpenFile(ctx context.Context, name string, flag int, _ os.FileMode) (webdav.File, error) {
	memberID := davMemberID(ctx)
	normalized, err := models.NormalizeDAVPath(name)
	if err != nil {
		return nil, davFileError(err)
	}
	node, statErr := models.GetDAVNode(memberID, normalized)
	if statErr == nil && node.IsDir {
		if flag&(os.O_WRONLY|os.O_RDWR|os.O_TRUNC|os.O_APPEND) != 0 {
			return nil, &os.PathError{Op: "open", Path: name, Err: errors.New("is a directory")}
		}
		children, err := models.ListDAVNodes(memberID, normalized)
		if err != nil {
			return nil, davFileError(err)
		}
		return &localDAVDirectory{node: *node, children: children}, nil
	}
	if statErr != nil && !errors.Is(statErr, models.ErrDAVNotFound) {
		return nil, davFileError(statErr)
	}
	writable := flag&(os.O_WRONLY|os.O_RDWR|os.O_CREATE|os.O_TRUNC|os.O_APPEND) != 0
	if statErr != nil && !writable {
		return nil, os.ErrNotExist
	}
	if statErr == nil && !writable {
		_, _, reader, err := models.ReadDAVFileContext(ctx, memberID, normalized)
		if err != nil {
			return nil, davFileError(err)
		}
		return &localDAVReadFile{
			reader: reader,
			node:   *node,
		}, nil
	}
	temp, err := os.CreateTemp("", "bookstark-webdav-open-*")
	if err != nil {
		return nil, err
	}
	cleanup := func() {
		_ = temp.Close()
		_ = os.Remove(temp.Name())
	}
	if statErr == nil && flag&os.O_TRUNC == 0 {
		_, _, reader, err := models.ReadDAVFileContext(ctx, memberID, normalized)
		if err != nil {
			cleanup()
			return nil, davFileError(err)
		}
		_, copyErr := io.Copy(temp, reader)
		_ = reader.Close()
		if copyErr != nil {
			cleanup()
			return nil, copyErr
		}
	}
	if flag&os.O_APPEND != 0 {
		_, err = temp.Seek(0, io.SeekEnd)
	} else {
		_, err = temp.Seek(0, io.SeekStart)
	}
	if err != nil {
		cleanup()
		return nil, err
	}
	if node == nil {
		node = &models.DAVNode{Name: path.Base(normalized), Path: normalized, MIMEType: "application/octet-stream", ModifyTime: time.Now()}
	}
	return &localDAVFile{
		File:         temp,
		ctx:          ctx,
		requestState: davRequestState(ctx),
		memberID:     memberID,
		path:         normalized,
		node:         *node,
		writable:     writable,
		maxBytes:     models.GetWebDAVSettings().FileMaxBytes,
	}, nil
}

func (LocalDAVFileSystem) RemoveAll(ctx context.Context, name string) error {
	return davFileError(models.DeleteDAVNode(davMemberID(ctx), name, true))
}

func (LocalDAVFileSystem) Rename(ctx context.Context, oldName, newName string) error {
	return davFileError(models.RenameDAVNode(davMemberID(ctx), oldName, newName))
}

func (LocalDAVFileSystem) Stat(ctx context.Context, name string) (os.FileInfo, error) {
	node, err := models.GetDAVNode(davMemberID(ctx), name)
	if err != nil {
		return nil, davFileError(err)
	}
	return davNodeInfo{node: *node}, nil
}

func davMemberID(ctx context.Context) int64 {
	value, _ := ctx.Value(davMemberContextKey{}).(int64)
	return value
}

func davRequestState(ctx context.Context) *DAVRequestState {
	value, _ := ctx.Value(davRequestStateContextKey{}).(*DAVRequestState)
	return value
}

func davFileError(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, models.ErrDAVNotFound):
		return os.ErrNotExist
	case errors.Is(err, models.ErrDAVAlreadyExists):
		return os.ErrExist
	case errors.Is(err, models.ErrDAVInvalidPath):
		return os.ErrInvalid
	case errors.Is(err, models.ErrDAVQuotaExceeded):
		return &os.PathError{Op: "write", Err: errors.New("quota exceeded")}
	case errors.Is(err, models.ErrDAVFileTooLarge):
		return &os.PathError{Op: "write", Err: errors.New("file too large")}
	default:
		return err
	}
}

type localDAVFile struct {
	*os.File
	ctx          context.Context
	requestState *DAVRequestState
	memberID     int64
	path         string
	node         models.DAVNode
	writable     bool
	maxBytes     int64
	closed       bool
	writeErr     error
}

func (f *localDAVFile) Write(content []byte) (int, error) {
	if f.closed {
		return 0, os.ErrClosed
	}
	if f.writeErr != nil {
		return 0, f.writeErr
	}
	if err := f.ctx.Err(); err != nil {
		f.writeErr = err
		return 0, err
	}
	position, err := f.File.Seek(0, io.SeekCurrent)
	if err != nil {
		f.writeErr = err
		return 0, err
	}
	currentSize := int64(0)
	if info, statErr := f.File.Stat(); statErr == nil {
		currentSize = info.Size()
	} else {
		f.writeErr = statErr
		return 0, statErr
	}
	finalSize := max(currentSize, position+int64(len(content)))
	if f.maxBytes > 0 && finalSize > f.maxBytes {
		f.writeErr = models.ErrDAVFileTooLarge
		if f.requestState != nil {
			f.requestState.Fail(f.writeErr)
		}
		return 0, f.writeErr
	}
	n, err := f.File.Write(content)
	if err == nil && n != len(content) {
		err = io.ErrShortWrite
	}
	if err != nil {
		f.writeErr = err
		if f.requestState != nil {
			f.requestState.Fail(err)
		}
	}
	return n, err
}

func (f *localDAVFile) Close() error {
	if f.closed {
		return nil
	}
	f.closed = true
	defer os.Remove(f.File.Name())
	if !f.writable {
		return f.File.Close()
	}
	if f.writeErr != nil {
		_ = f.File.Close()
		return davFileError(f.writeErr)
	}
	if err := f.ctx.Err(); err != nil {
		_ = f.File.Close()
		return err
	}
	if err := f.requestState.Err(); err != nil {
		_ = f.File.Close()
		return err
	}
	if _, err := f.File.Seek(0, io.SeekStart); err != nil {
		_ = f.File.Close()
		return err
	}
	settings := models.GetWebDAVSettings()
	_, _, err := models.PutDAVFileContext(f.ctx, f.memberID, f.path, f.node.MIMEType, f.File, settings.FileMaxBytes, settings.UserQuotaBytes)
	closeErr := f.File.Close()
	if err != nil {
		return davFileError(err)
	}
	return closeErr
}

type localDAVReadFile struct {
	reader models.DAVReadSeekCloser
	node   models.DAVNode
}

func (f *localDAVReadFile) Close() error {
	return f.reader.Close()
}

func (f *localDAVReadFile) Read(buffer []byte) (int, error) {
	return f.reader.Read(buffer)
}

func (f *localDAVReadFile) Write(_ []byte) (int, error) {
	return 0, &os.PathError{Op: "write", Path: f.node.Path, Err: errors.New("file is read-only")}
}

func (f *localDAVReadFile) Seek(offset int64, whence int) (int64, error) {
	return f.reader.Seek(offset, whence)
}

func (f *localDAVReadFile) Readdir(_ int) ([]os.FileInfo, error) {
	return nil, &os.PathError{Op: "readdir", Path: f.node.Path, Err: errors.New("not a directory")}
}

func (f *localDAVReadFile) Stat() (os.FileInfo, error) {
	return davNodeInfo{node: f.node}, nil
}

func (f *localDAVFile) Readdir(_ int) ([]os.FileInfo, error) {
	return nil, &os.PathError{Op: "readdir", Path: f.path, Err: errors.New("not a directory")}
}

func (f *localDAVFile) Stat() (os.FileInfo, error) {
	node, err := models.GetDAVNode(f.memberID, f.path)
	if err == nil {
		f.node = *node
	}
	return davNodeInfo{node: f.node}, nil
}

type localDAVDirectory struct {
	node     models.DAVNode
	children []models.DAVNode
	offset   int
	closed   bool
}

func (d *localDAVDirectory) Close() error {
	d.closed = true
	return nil
}

func (d *localDAVDirectory) Read(_ []byte) (int, error) {
	return 0, io.EOF
}

func (d *localDAVDirectory) Write(_ []byte) (int, error) {
	return 0, &os.PathError{Op: "write", Path: d.node.Path, Err: errors.New("is a directory")}
}

func (d *localDAVDirectory) Seek(_ int64, _ int) (int64, error) {
	return 0, &os.PathError{Op: "seek", Path: d.node.Path, Err: errors.New("is a directory")}
}

func (d *localDAVDirectory) Readdir(count int) ([]os.FileInfo, error) {
	if d.closed {
		return nil, os.ErrClosed
	}
	if d.offset >= len(d.children) {
		if count > 0 {
			return nil, io.EOF
		}
		return []os.FileInfo{}, nil
	}
	end := len(d.children)
	if count > 0 && d.offset+count < end {
		end = d.offset + count
	}
	result := make([]os.FileInfo, 0, end-d.offset)
	for _, node := range d.children[d.offset:end] {
		result = append(result, davNodeInfo{node: node})
	}
	d.offset = end
	return result, nil
}

func (d *localDAVDirectory) Stat() (os.FileInfo, error) {
	return davNodeInfo{node: d.node}, nil
}

type davNodeInfo struct {
	node models.DAVNode
}

func (i davNodeInfo) Name() string {
	if i.node.Name == "" {
		return "/"
	}
	return i.node.Name
}

func (i davNodeInfo) Size() int64        { return i.node.Size }
func (i davNodeInfo) ModTime() time.Time { return i.node.ModifyTime }
func (i davNodeInfo) IsDir() bool        { return i.node.IsDir }
func (i davNodeInfo) Sys() any           { return nil }
func (i davNodeInfo) Mode() os.FileMode {
	if i.node.IsDir {
		return os.ModeDir | 0o755
	}
	return 0o644
}
