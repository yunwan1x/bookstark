package services

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	containertypes "github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	imagetypes "github.com/docker/docker/api/types/image"
	networktypes "github.com/docker/docker/api/types/network"
	volumetypes "github.com/docker/docker/api/types/volume"
	dockerclient "github.com/docker/docker/client"
	"github.com/docker/docker/pkg/stdcopy"
	"github.com/docker/go-connections/nat"
	"github.com/docker/go-units"
	"github.com/gorilla/websocket"
	"golang.org/x/crypto/ssh"

	"bookstark/models"
)

const DefaultDockerSocketPath = "/var/run/docker.sock"

var ErrDockerAPIUnavailable = errors.New("docker api unavailable")

type DockerCommandRunner interface {
	RunCommand(host *models.AssetSSHHost, credential string, command string) (string, error)
	StreamCommand(ctx context.Context, host *models.AssetSSHHost, credential string, command string, onChunk func([]byte) error) error
}

type DockerClient interface {
	ListContainers(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerContainerSummary, error)
	ListNetworks(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerNetworkSummary, error)
	CreateNetwork(ctx context.Context, host *models.AssetSSHHost, credential string, name string, driver string) (string, error)
	RemoveNetwork(ctx context.Context, host *models.AssetSSHHost, credential string, name string) (string, error)
	ListVolumes(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerVolumeSummary, error)
	CreateVolume(ctx context.Context, host *models.AssetSSHHost, credential string, name string, driver string) (string, error)
	RemoveVolume(ctx context.Context, host *models.AssetSSHHost, credential string, name string) (string, error)
	ListImages(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerImageSummary, error)
	PullImage(ctx context.Context, host *models.AssetSSHHost, credential string, image string) (string, error)
	RemoveImage(ctx context.Context, host *models.AssetSSHHost, credential string, image string) (string, error)
	Prune(ctx context.Context, host *models.AssetSSHHost, credential string, resource string) (string, error)
	CreateContainer(ctx context.Context, host *models.AssetSSHHost, credential string, req DockerCreateRequest) (DockerCreateResult, error)
	InspectContainer(ctx context.Context, host *models.AssetSSHHost, credential string, container string) (DockerInspectSummary, error)
	OperateContainer(ctx context.Context, host *models.AssetSSHHost, credential string, container string, action string) (string, error)
	UpdateRestartPolicy(ctx context.Context, host *models.AssetSSHHost, credential string, container string, policy string) (string, error)
	Logs(ctx context.Context, host *models.AssetSSHHost, credential string, container string, tail int, follow bool) (io.ReadCloser, error)
	BridgeTerminal(ws *websocket.Conn, host *models.AssetSSHHost, credential string, container string, opts TerminalOptions) error
}

type DockerCreateRequest struct {
	Image            string                `json:"image"`
	Name             string                `json:"name"`
	Command          string                `json:"command"`
	StartAfterCreate *bool                 `json:"start_after_create"`
	RestartPolicy    string                `json:"restart_policy"`
	Ports            []DockerPortRequest   `json:"ports"`
	Volumes          []DockerVolumeRequest `json:"volumes"`
	Env              []DockerEnvRequest    `json:"env"`
	Network          string                `json:"network"`
	Privileged       bool                  `json:"privileged"`
	Memory           string                `json:"memory"`
	CPUs             string                `json:"cpus"`
}

type DockerPortRequest struct {
	HostIP        string `json:"host_ip"`
	HostPort      string `json:"host_port"`
	ContainerPort string `json:"container_port"`
	Protocol      string `json:"protocol"`
}

type DockerVolumeRequest struct {
	HostPath      string `json:"host_path"`
	ContainerPath string `json:"container_path"`
	Mode          string `json:"mode"`
}

type DockerEnvRequest struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

type DockerCreateResult struct {
	ID               string `json:"id,omitempty"`
	Image            string `json:"image"`
	Name             string `json:"name"`
	StartAfterCreate bool   `json:"start_after_create"`
	Output           string `json:"output"`
}

type SSHDockerFallbackClient struct {
	Primary  DockerClient
	Fallback DockerClient
}

func (c SSHDockerFallbackClient) ListContainers(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerContainerSummary, error) {
	items, err := c.Primary.ListContainers(ctx, host, credential)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.ListContainers(ctx, host, credential)
	}
	return items, err
}

func (c SSHDockerFallbackClient) ListNetworks(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerNetworkSummary, error) {
	items, err := c.Primary.ListNetworks(ctx, host, credential)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.ListNetworks(ctx, host, credential)
	}
	return items, err
}

func (c SSHDockerFallbackClient) CreateNetwork(ctx context.Context, host *models.AssetSSHHost, credential string, name string, driver string) (string, error) {
	output, err := c.Primary.CreateNetwork(ctx, host, credential, name, driver)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.CreateNetwork(ctx, host, credential, name, driver)
	}
	return output, err
}

func (c SSHDockerFallbackClient) RemoveNetwork(ctx context.Context, host *models.AssetSSHHost, credential string, name string) (string, error) {
	output, err := c.Primary.RemoveNetwork(ctx, host, credential, name)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.RemoveNetwork(ctx, host, credential, name)
	}
	return output, err
}

func (c SSHDockerFallbackClient) ListVolumes(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerVolumeSummary, error) {
	items, err := c.Primary.ListVolumes(ctx, host, credential)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.ListVolumes(ctx, host, credential)
	}
	return items, err
}

func (c SSHDockerFallbackClient) CreateVolume(ctx context.Context, host *models.AssetSSHHost, credential string, name string, driver string) (string, error) {
	output, err := c.Primary.CreateVolume(ctx, host, credential, name, driver)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.CreateVolume(ctx, host, credential, name, driver)
	}
	return output, err
}

func (c SSHDockerFallbackClient) RemoveVolume(ctx context.Context, host *models.AssetSSHHost, credential string, name string) (string, error) {
	output, err := c.Primary.RemoveVolume(ctx, host, credential, name)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.RemoveVolume(ctx, host, credential, name)
	}
	return output, err
}

func (c SSHDockerFallbackClient) ListImages(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerImageSummary, error) {
	items, err := c.Primary.ListImages(ctx, host, credential)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.ListImages(ctx, host, credential)
	}
	return items, err
}

func (c SSHDockerFallbackClient) PullImage(ctx context.Context, host *models.AssetSSHHost, credential string, image string) (string, error) {
	output, err := c.Primary.PullImage(ctx, host, credential, image)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.PullImage(ctx, host, credential, image)
	}
	return output, err
}

func (c SSHDockerFallbackClient) RemoveImage(ctx context.Context, host *models.AssetSSHHost, credential string, image string) (string, error) {
	output, err := c.Primary.RemoveImage(ctx, host, credential, image)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.RemoveImage(ctx, host, credential, image)
	}
	return output, err
}

func (c SSHDockerFallbackClient) Prune(ctx context.Context, host *models.AssetSSHHost, credential string, resource string) (string, error) {
	output, err := c.Primary.Prune(ctx, host, credential, resource)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.Prune(ctx, host, credential, resource)
	}
	return output, err
}

func (c SSHDockerFallbackClient) CreateContainer(ctx context.Context, host *models.AssetSSHHost, credential string, req DockerCreateRequest) (DockerCreateResult, error) {
	result, err := c.Primary.CreateContainer(ctx, host, credential, req)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.CreateContainer(ctx, host, credential, req)
	}
	return result, err
}

func (c SSHDockerFallbackClient) InspectContainer(ctx context.Context, host *models.AssetSSHHost, credential string, container string) (DockerInspectSummary, error) {
	info, err := c.Primary.InspectContainer(ctx, host, credential, container)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.InspectContainer(ctx, host, credential, container)
	}
	return info, err
}

func (c SSHDockerFallbackClient) OperateContainer(ctx context.Context, host *models.AssetSSHHost, credential string, container string, action string) (string, error) {
	output, err := c.Primary.OperateContainer(ctx, host, credential, container, action)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.OperateContainer(ctx, host, credential, container, action)
	}
	return output, err
}

func (c SSHDockerFallbackClient) UpdateRestartPolicy(ctx context.Context, host *models.AssetSSHHost, credential string, container string, policy string) (string, error) {
	output, err := c.Primary.UpdateRestartPolicy(ctx, host, credential, container, policy)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.UpdateRestartPolicy(ctx, host, credential, container, policy)
	}
	return output, err
}

func (c SSHDockerFallbackClient) Logs(ctx context.Context, host *models.AssetSSHHost, credential string, container string, tail int, follow bool) (io.ReadCloser, error) {
	reader, err := c.Primary.Logs(ctx, host, credential, container, tail, follow)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.Logs(ctx, host, credential, container, tail, follow)
	}
	return reader, err
}

func (c SSHDockerFallbackClient) BridgeTerminal(ws *websocket.Conn, host *models.AssetSSHHost, credential string, container string, opts TerminalOptions) error {
	err := c.Primary.BridgeTerminal(ws, host, credential, container, opts)
	if errors.Is(err, ErrDockerAPIUnavailable) {
		return c.Fallback.BridgeTerminal(ws, host, credential, container, opts)
	}
	return err
}

type SSHDockerAPIClient struct {
	Timeout time.Duration
}

type dockerAPIHandle struct {
	client    *dockerclient.Client
	sshClient *ssh.Client
}

func (h *dockerAPIHandle) Close() {
	if h.client != nil {
		_ = h.client.Close()
	}
	if h.sshClient != nil {
		_ = h.sshClient.Close()
	}
}

func (c SSHDockerAPIClient) connect(ctx context.Context, host *models.AssetSSHHost, credential string) (*dockerAPIHandle, error) {
	auth, err := sshAuth(host.AuthType, credential)
	if err != nil {
		return nil, err
	}
	timeout := c.Timeout
	if timeout <= 0 {
		timeout = 10 * time.Second
	}
	config := &ssh.ClientConfig{
		User:            host.Username,
		Auth:            []ssh.AuthMethod{auth},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         timeout,
	}
	sshClient, err := ssh.Dial("tcp", net.JoinHostPort(host.Host, fmt.Sprintf("%d", host.Port)), config)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrDockerAPIUnavailable, sanitizeSSHError(err))
	}
	socketPath := strings.TrimSpace(host.DockerSocketPath)
	if socketPath == "" {
		socketPath = DefaultDockerSocketPath
	}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			conn, err := sshClient.DialContext(ctx, "unix", socketPath)
			if err != nil {
				return nil, fmt.Errorf("%w: connect %s: %v", ErrDockerAPIUnavailable, socketPath, err)
			}
			return conn, nil
		},
	}
	httpClient := &http.Client{Transport: transport}
	cli, err := dockerclient.NewClientWithOpts(
		dockerclient.WithHost("http://docker"),
		dockerclient.WithHTTPClient(httpClient),
		dockerclient.WithAPIVersionNegotiation(),
	)
	if err != nil {
		_ = sshClient.Close()
		return nil, fmt.Errorf("%w: %v", ErrDockerAPIUnavailable, err)
	}
	handle := &dockerAPIHandle{client: cli, sshClient: sshClient}
	pingCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	if _, err := cli.Ping(pingCtx); err != nil {
		handle.Close()
		return nil, fmt.Errorf("%w: %v", ErrDockerAPIUnavailable, err)
	}
	return handle, nil
}

func (c SSHDockerAPIClient) ListContainers(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerContainerSummary, error) {
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	rows, err := handle.client.ContainerList(ctx, containertypes.ListOptions{All: true})
	if err != nil {
		return nil, err
	}
	items := make([]DockerContainerSummary, 0, len(rows))
	for _, row := range rows {
		items = append(items, dockerSummaryFromAPI(row))
	}
	return items, nil
}

func (c SSHDockerAPIClient) ListNetworks(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerNetworkSummary, error) {
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	rows, err := handle.client.NetworkList(ctx, networktypes.ListOptions{})
	if err != nil {
		return nil, err
	}
	items := make([]DockerNetworkSummary, 0, len(rows))
	for _, row := range rows {
		items = append(items, DockerNetworkSummary{ID: shortDockerID(row.ID), Name: row.Name, Driver: row.Driver, Scope: row.Scope})
	}
	return items, nil
}

func (c SSHDockerAPIClient) CreateNetwork(ctx context.Context, host *models.AssetSSHHost, credential string, name string, driver string) (string, error) {
	name = strings.TrimSpace(name)
	if !validDockerObjectName(name) {
		return "", fmt.Errorf("无效的 Docker 网络名称")
	}
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return "", err
	}
	defer handle.Close()
	resp, err := handle.client.NetworkCreate(ctx, name, networktypes.CreateOptions{Driver: strings.TrimSpace(driver)})
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(resp.ID), nil
}

func (c SSHDockerAPIClient) RemoveNetwork(ctx context.Context, host *models.AssetSSHHost, credential string, name string) (string, error) {
	name = strings.TrimSpace(name)
	if !validDockerObjectName(name) {
		return "", fmt.Errorf("无效的 Docker 网络名称")
	}
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return "", err
	}
	defer handle.Close()
	return "", handle.client.NetworkRemove(ctx, name)
}

func (c SSHDockerAPIClient) ListVolumes(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerVolumeSummary, error) {
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	rows, err := handle.client.VolumeList(ctx, volumetypes.ListOptions{})
	if err != nil {
		return nil, err
	}
	items := make([]DockerVolumeSummary, 0, len(rows.Volumes))
	for _, row := range rows.Volumes {
		if row == nil {
			continue
		}
		items = append(items, DockerVolumeSummary{
			Name:       row.Name,
			Driver:     row.Driver,
			Scope:      row.Scope,
			Mountpoint: row.Mountpoint,
			CreatedAt:  row.CreatedAt,
		})
	}
	return items, nil
}

func (c SSHDockerAPIClient) CreateVolume(ctx context.Context, host *models.AssetSSHHost, credential string, name string, driver string) (string, error) {
	name = strings.TrimSpace(name)
	if !validDockerObjectName(name) {
		return "", fmt.Errorf("无效的 Docker 存储名称")
	}
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return "", err
	}
	defer handle.Close()
	resp, err := handle.client.VolumeCreate(ctx, volumetypes.CreateOptions{Name: name, Driver: strings.TrimSpace(driver)})
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(resp.Name), nil
}

func (c SSHDockerAPIClient) RemoveVolume(ctx context.Context, host *models.AssetSSHHost, credential string, name string) (string, error) {
	name = strings.TrimSpace(name)
	if !validDockerObjectName(name) {
		return "", fmt.Errorf("无效的 Docker 存储名称")
	}
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return "", err
	}
	defer handle.Close()
	return "", handle.client.VolumeRemove(ctx, name, false)
}

func (c SSHDockerAPIClient) ListImages(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerImageSummary, error) {
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return nil, err
	}
	defer handle.Close()
	rows, err := handle.client.ImageList(ctx, imagetypes.ListOptions{All: true})
	if err != nil {
		return nil, err
	}
	items := make([]DockerImageSummary, 0, len(rows))
	for _, row := range rows {
		repo, tag := dockerImageRepoTag(row.RepoTags)
		items = append(items, DockerImageSummary{
			ID:         shortDockerID(strings.TrimPrefix(row.ID, "sha256:")),
			Repository: repo,
			Tag:        tag,
			Size:       units.HumanSize(float64(row.Size)),
			CreatedAt:  dockerUnixTime(row.Created),
			Containers: row.Containers,
		})
	}
	return items, nil
}

func (c SSHDockerAPIClient) PullImage(ctx context.Context, host *models.AssetSSHHost, credential string, image string) (string, error) {
	image = strings.TrimSpace(image)
	if !validDockerImageRef(image) {
		return "", fmt.Errorf("无效的 Docker 镜像")
	}
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return "", err
	}
	defer handle.Close()
	reader, err := handle.client.ImagePull(ctx, image, imagetypes.PullOptions{})
	if err != nil {
		return "", err
	}
	defer reader.Close()
	body, err := io.ReadAll(reader)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(body)), nil
}

func (c SSHDockerAPIClient) RemoveImage(ctx context.Context, host *models.AssetSSHHost, credential string, image string) (string, error) {
	image = strings.TrimSpace(image)
	if !validDockerImageRef(image) {
		return "", fmt.Errorf("无效的 Docker 镜像")
	}
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return "", err
	}
	defer handle.Close()
	_, err = handle.client.ImageRemove(ctx, image, imagetypes.RemoveOptions{PruneChildren: true})
	return "", err
}

func (c SSHDockerAPIClient) Prune(ctx context.Context, host *models.AssetSSHHost, credential string, resource string) (string, error) {
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return "", err
	}
	defer handle.Close()
	pruneFilters := filters.NewArgs()
	switch strings.TrimSpace(resource) {
	case "containers":
		report, err := handle.client.ContainersPrune(ctx, pruneFilters)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("Deleted containers: %d\nSpace reclaimed: %s", len(report.ContainersDeleted), units.HumanSize(float64(report.SpaceReclaimed))), nil
	case "networks":
		report, err := handle.client.NetworksPrune(ctx, pruneFilters)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("Deleted networks: %d", len(report.NetworksDeleted)), nil
	case "volumes":
		report, err := handle.client.VolumesPrune(ctx, pruneFilters)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("Deleted volumes: %d\nSpace reclaimed: %s", len(report.VolumesDeleted), units.HumanSize(float64(report.SpaceReclaimed))), nil
	case "images":
		report, err := handle.client.ImagesPrune(ctx, pruneFilters)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("Deleted images: %d\nSpace reclaimed: %s", len(report.ImagesDeleted), units.HumanSize(float64(report.SpaceReclaimed))), nil
	default:
		return "", fmt.Errorf("无效的 Docker 清理类型")
	}
}

func (c SSHDockerAPIClient) CreateContainer(ctx context.Context, host *models.AssetSSHHost, credential string, req DockerCreateRequest) (DockerCreateResult, error) {
	image := strings.TrimSpace(req.Image)
	if image == "" || strings.HasPrefix(image, "-") {
		return DockerCreateResult{}, fmt.Errorf("无效的 Docker 容器参数")
	}
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return DockerCreateResult{}, err
	}
	defer handle.Close()
	if err := ensureDockerImage(ctx, handle.client, image); err != nil {
		return DockerCreateResult{}, err
	}
	config, hostConfig, networkingConfig, err := dockerCreateAPIConfig(req)
	if err != nil {
		return DockerCreateResult{}, err
	}
	created, err := handle.client.ContainerCreate(ctx, config, hostConfig, networkingConfig, nil, strings.TrimSpace(req.Name))
	if err != nil {
		return DockerCreateResult{}, err
	}
	startAfterCreate := dockerStartAfterCreate(req)
	if startAfterCreate {
		if err := handle.client.ContainerStart(ctx, created.ID, containertypes.StartOptions{}); err != nil {
			return DockerCreateResult{}, err
		}
	}
	return DockerCreateResult{
		ID:               created.ID,
		Image:            image,
		Name:             strings.TrimSpace(req.Name),
		StartAfterCreate: startAfterCreate,
		Output:           strings.TrimSpace(created.ID),
	}, nil
}

func (c SSHDockerAPIClient) InspectContainer(ctx context.Context, host *models.AssetSSHHost, credential string, container string) (DockerInspectSummary, error) {
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return DockerInspectSummary{}, err
	}
	defer handle.Close()
	info, err := handle.client.ContainerInspect(ctx, container)
	if err != nil {
		return DockerInspectSummary{}, err
	}
	return dockerInspectFromAPI(info), nil
}

func (c SSHDockerAPIClient) OperateContainer(ctx context.Context, host *models.AssetSSHHost, credential string, container string, action string) (string, error) {
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return "", err
	}
	defer handle.Close()
	switch action {
	case "start":
		err = handle.client.ContainerStart(ctx, container, containertypes.StartOptions{})
	case "stop":
		err = handle.client.ContainerStop(ctx, container, containertypes.StopOptions{})
	case "restart":
		err = handle.client.ContainerRestart(ctx, container, containertypes.StopOptions{})
	case "delete":
		err = handle.client.ContainerRemove(ctx, container, containertypes.RemoveOptions{})
	default:
		return "", fmt.Errorf("无效的 Docker 操作")
	}
	if err != nil {
		return "", err
	}
	return "", nil
}

func (c SSHDockerAPIClient) UpdateRestartPolicy(ctx context.Context, host *models.AssetSSHHost, credential string, container string, policy string) (string, error) {
	if !IsAllowedDockerRestartPolicy(policy) {
		return "", fmt.Errorf("无效的重启策略")
	}
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return "", err
	}
	defer handle.Close()
	resp, err := handle.client.ContainerUpdate(ctx, container, containertypes.UpdateConfig{
		RestartPolicy: containertypes.RestartPolicy{Name: containertypes.RestartPolicyMode(policy)},
	})
	if err != nil {
		return "", err
	}
	return strings.Join(resp.Warnings, "\n"), nil
}

func (c SSHDockerAPIClient) Logs(ctx context.Context, host *models.AssetSSHHost, credential string, container string, tail int, follow bool) (io.ReadCloser, error) {
	handle, err := c.connect(ctx, host, credential)
	if err != nil {
		return nil, err
	}
	reader, err := handle.client.ContainerLogs(ctx, container, containertypes.LogsOptions{
		ShowStdout: true,
		ShowStderr: true,
		Tail:       strconv.Itoa(tail),
		Follow:     follow,
	})
	if err != nil {
		handle.Close()
		return nil, err
	}
	pipeReader, pipeWriter := io.Pipe()
	go func() {
		_, copyErr := stdcopy.StdCopy(pipeWriter, pipeWriter, reader)
		_ = reader.Close()
		_ = pipeWriter.CloseWithError(copyErr)
	}()
	return &dockerReadCloser{ReadCloser: pipeReader, close: handle.Close}, nil
}

func (c SSHDockerAPIClient) BridgeTerminal(ws *websocket.Conn, host *models.AssetSSHHost, credential string, container string, opts TerminalOptions) error {
	writer := &terminalWSWriter{ws: ws}
	configureTerminalWebSocket(ws)
	handle, err := c.connect(context.Background(), host, credential)
	if err != nil {
		return err
	}
	defer handle.Close()
	keepaliveStop := make(chan struct{})
	keepaliveErrors := make(chan error, 1)
	go runSSHKeepalive(handle.sshClient, terminalSSHKeepaliveInterval, keepaliveStop, keepaliveErrors)
	defer close(keepaliveStop)
	shell := strings.TrimSpace(opts.DefaultShell)
	if shell == "" {
		shell = "/bin/sh"
	}
	exec, err := handle.client.ContainerExecCreate(context.Background(), container, containertypes.ExecOptions{
		Cmd:          []string{shell},
		Tty:          true,
		AttachStdin:  true,
		AttachStdout: true,
		AttachStderr: true,
	})
	if err != nil {
		_ = writer.WriteJSON(TerminalMessage{Type: "error", Data: err.Error()})
		return err
	}
	attached, err := handle.client.ContainerExecAttach(context.Background(), exec.ID, containertypes.ExecAttachOptions{Tty: true})
	if err != nil {
		_ = writer.WriteJSON(TerminalMessage{Type: "error", Data: err.Error()})
		return err
	}
	defer attached.Close()
	_ = writer.WriteJSON(TerminalMessage{Type: "ready", Data: "connected"})

	done := make(chan struct{})
	var doneOnce sync.Once
	go func() {
		_, _ = io.Copy(&terminalDataWriter{writer: writer}, attached.Reader)
		doneOnce.Do(func() { close(done) })
	}()

	idle := opts.IdleTimeout
	if idle <= 0 {
		idle = 30 * time.Minute
	}
	timer := time.NewTimer(idle)
	defer timer.Stop()
	webSocketPingTicker := time.NewTicker(terminalWebSocketPingInterval)
	defer webSocketPingTicker.Stop()
	reads := make(chan terminalReadResult)
	readStop := make(chan struct{})
	defer close(readStop)
	go readTerminalMessages(ws, reads, readStop)
	for {
		select {
		case <-done:
			_ = writer.WriteJSON(TerminalMessage{Type: "closed", Data: "session closed"})
			return nil
		case <-timer.C:
			_ = writer.WriteJSON(TerminalMessage{Type: "closed", Data: "idle timeout"})
			return nil
		case <-webSocketPingTicker.C:
			if err := writer.WritePing(); err != nil {
				return nil
			}
		case err := <-keepaliveErrors:
			_ = writer.WriteJSON(TerminalMessage{Type: "closed", Data: "SSH connection lost"})
			return err
		case result := <-reads:
			if result.err != nil {
				return nil
			}
			resetTimer(timer, idle)
			switch result.msg.Type {
			case "close":
				return nil
			case "input":
				_, _ = io.WriteString(attached.Conn, result.msg.Data)
			case "resize":
				if result.msg.Cols > 0 && result.msg.Rows > 0 {
					_ = handle.client.ContainerExecResize(context.Background(), exec.ID, containertypes.ResizeOptions{Width: uint(result.msg.Cols), Height: uint(result.msg.Rows)})
				}
			}
		}
	}
}

type terminalDataWriter struct {
	writer *terminalWSWriter
}

func (w *terminalDataWriter) Write(p []byte) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	if err := w.writer.WriteJSON(TerminalMessage{Type: "output", Data: string(p)}); err != nil {
		return 0, err
	}
	return len(p), nil
}

type dockerReadCloser struct {
	io.ReadCloser
	close func()
}

func (r *dockerReadCloser) Close() error {
	err := r.ReadCloser.Close()
	if r.close != nil {
		r.close()
	}
	return err
}

type SSHDockerCLIClient struct {
	Runner DockerCommandRunner
}

func (c SSHDockerCLIClient) ListContainers(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerContainerSummary, error) {
	output, err := c.Runner.RunCommand(host, credential, "docker ps -a --format '{{json .}}'")
	if err != nil {
		return nil, err
	}
	return ParseDockerPS(output)
}

func (c SSHDockerCLIClient) ListNetworks(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerNetworkSummary, error) {
	output, err := c.Runner.RunCommand(host, credential, "docker network ls --format '{{json .}}'")
	if err != nil {
		return nil, err
	}
	return ParseDockerNetworks(output), nil
}

func (c SSHDockerCLIClient) CreateNetwork(ctx context.Context, host *models.AssetSSHHost, credential string, name string, driver string) (string, error) {
	command, ok := DockerNetworkCreateCommand(name, driver)
	if !ok {
		return "", fmt.Errorf("无效的 Docker 网络名称")
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	return strings.TrimSpace(output), err
}

func (c SSHDockerCLIClient) RemoveNetwork(ctx context.Context, host *models.AssetSSHHost, credential string, name string) (string, error) {
	command, ok := DockerNetworkRemoveCommand(name)
	if !ok {
		return "", fmt.Errorf("无效的 Docker 网络名称")
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	return strings.TrimSpace(output), err
}

func (c SSHDockerCLIClient) ListVolumes(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerVolumeSummary, error) {
	output, err := c.Runner.RunCommand(host, credential, "docker volume ls --format '{{json .}}'")
	if err != nil {
		return nil, err
	}
	return ParseDockerVolumes(output), nil
}

func (c SSHDockerCLIClient) CreateVolume(ctx context.Context, host *models.AssetSSHHost, credential string, name string, driver string) (string, error) {
	command, ok := DockerVolumeCreateCommand(name, driver)
	if !ok {
		return "", fmt.Errorf("无效的 Docker 存储名称")
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	return strings.TrimSpace(output), err
}

func (c SSHDockerCLIClient) RemoveVolume(ctx context.Context, host *models.AssetSSHHost, credential string, name string) (string, error) {
	command, ok := DockerVolumeRemoveCommand(name)
	if !ok {
		return "", fmt.Errorf("无效的 Docker 存储名称")
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	return strings.TrimSpace(output), err
}

func (c SSHDockerCLIClient) ListImages(ctx context.Context, host *models.AssetSSHHost, credential string) ([]DockerImageSummary, error) {
	output, err := c.Runner.RunCommand(host, credential, "docker image ls --format '{{json .}}'")
	if err != nil {
		return nil, err
	}
	return ParseDockerImages(output), nil
}

func (c SSHDockerCLIClient) PullImage(ctx context.Context, host *models.AssetSSHHost, credential string, image string) (string, error) {
	command, ok := DockerImagePullCommand(image)
	if !ok {
		return "", fmt.Errorf("无效的 Docker 镜像")
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	return strings.TrimSpace(output), err
}

func (c SSHDockerCLIClient) RemoveImage(ctx context.Context, host *models.AssetSSHHost, credential string, image string) (string, error) {
	command, ok := DockerImageRemoveCommand(image)
	if !ok {
		return "", fmt.Errorf("无效的 Docker 镜像")
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	return strings.TrimSpace(output), err
}

func (c SSHDockerCLIClient) Prune(ctx context.Context, host *models.AssetSSHHost, credential string, resource string) (string, error) {
	command, ok := DockerPruneCommand(resource)
	if !ok {
		return "", fmt.Errorf("无效的 Docker 清理类型")
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	return strings.TrimSpace(output), err
}

func (c SSHDockerCLIClient) CreateContainer(ctx context.Context, host *models.AssetSSHHost, credential string, req DockerCreateRequest) (DockerCreateResult, error) {
	command, startAfterCreate, ok := DockerCreateContainerCommand(req)
	if !ok {
		return DockerCreateResult{}, fmt.Errorf("无效的 Docker 容器参数")
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	if err != nil {
		return DockerCreateResult{}, err
	}
	return DockerCreateResult{
		Image:            strings.TrimSpace(req.Image),
		Name:             strings.TrimSpace(req.Name),
		StartAfterCreate: startAfterCreate,
		Output:           strings.TrimSpace(output),
	}, nil
}

func (c SSHDockerCLIClient) InspectContainer(ctx context.Context, host *models.AssetSSHHost, credential string, container string) (DockerInspectSummary, error) {
	output, err := c.Runner.RunCommand(host, credential, "docker inspect "+DockerShellQuote(container))
	if err != nil {
		return DockerInspectSummary{}, err
	}
	return ParseDockerInspect(output)
}

func (c SSHDockerCLIClient) OperateContainer(ctx context.Context, host *models.AssetSSHHost, credential string, container string, action string) (string, error) {
	command, ok := DockerContainerCommand(action, container)
	if !ok {
		return "", fmt.Errorf("无效的 Docker 操作")
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	return strings.TrimSpace(output), err
}

func (c SSHDockerCLIClient) UpdateRestartPolicy(ctx context.Context, host *models.AssetSSHHost, credential string, container string, policy string) (string, error) {
	command, ok := DockerRestartPolicyCommand(strings.TrimSpace(policy), container)
	if !ok {
		return "", fmt.Errorf("无效的重启策略")
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	return strings.TrimSpace(output), err
}

func (c SSHDockerCLIClient) Logs(ctx context.Context, host *models.AssetSSHHost, credential string, container string, tail int, follow bool) (io.ReadCloser, error) {
	command := fmt.Sprintf("docker logs --tail %d", tail)
	if follow {
		command += " -f"
	}
	command += " " + DockerShellQuote(container)
	if follow {
		pipeReader, pipeWriter := io.Pipe()
		go func() {
			err := c.Runner.StreamCommand(ctx, host, credential, command, func(chunk []byte) error {
				_, writeErr := pipeWriter.Write(chunk)
				return writeErr
			})
			_ = pipeWriter.CloseWithError(err)
		}()
		return pipeReader, nil
	}
	output, err := c.Runner.RunCommand(host, credential, command)
	if err != nil {
		return nil, err
	}
	return io.NopCloser(strings.NewReader(output)), nil
}

func (c SSHDockerCLIClient) BridgeTerminal(ws *websocket.Conn, host *models.AssetSSHHost, credential string, container string, opts TerminalOptions) error {
	opts.DockerContainer = container
	if strings.TrimSpace(opts.DefaultShell) == "" {
		opts.DefaultShell = "/bin/sh"
	}
	return bridgeSSHTerminal(ws, host, credential, opts)
}

func DockerContainerCommand(action string, container string) (string, bool) {
	quotedContainer := DockerShellQuote(container)
	switch action {
	case "start":
		return "docker start " + quotedContainer, true
	case "stop":
		return "docker stop " + quotedContainer, true
	case "restart":
		return "docker restart " + quotedContainer, true
	case "delete":
		return "docker rm " + quotedContainer, true
	default:
		return "", false
	}
}

func DockerRestartPolicyCommand(policy string, container string) (string, bool) {
	if !IsAllowedDockerRestartPolicy(policy) {
		return "", false
	}
	return "docker update --restart " + policy + " " + DockerShellQuote(container), true
}

func DockerNetworkCreateCommand(name string, driver string) (string, bool) {
	name = strings.TrimSpace(name)
	if !validDockerObjectName(name) {
		return "", false
	}
	args := []string{"docker", "network", "create"}
	if driver = strings.TrimSpace(driver); driver != "" {
		if strings.HasPrefix(driver, "-") || strings.ContainsAny(driver, "\r\n") {
			return "", false
		}
		args = append(args, "--driver", DockerShellQuote(driver))
	}
	args = append(args, DockerShellQuote(name))
	return strings.Join(args, " "), true
}

func DockerNetworkRemoveCommand(name string) (string, bool) {
	name = strings.TrimSpace(name)
	if !validDockerObjectName(name) {
		return "", false
	}
	return "docker network rm " + DockerShellQuote(name), true
}

func DockerVolumeCreateCommand(name string, driver string) (string, bool) {
	name = strings.TrimSpace(name)
	if !validDockerObjectName(name) {
		return "", false
	}
	args := []string{"docker", "volume", "create"}
	if driver = strings.TrimSpace(driver); driver != "" {
		if strings.HasPrefix(driver, "-") || strings.ContainsAny(driver, "\r\n") {
			return "", false
		}
		args = append(args, "--driver", DockerShellQuote(driver))
	}
	args = append(args, DockerShellQuote(name))
	return strings.Join(args, " "), true
}

func DockerVolumeRemoveCommand(name string) (string, bool) {
	name = strings.TrimSpace(name)
	if !validDockerObjectName(name) {
		return "", false
	}
	return "docker volume rm " + DockerShellQuote(name), true
}

func DockerImagePullCommand(image string) (string, bool) {
	image = strings.TrimSpace(image)
	if !validDockerImageRef(image) {
		return "", false
	}
	return "docker pull " + DockerShellQuote(image), true
}

func DockerImageRemoveCommand(image string) (string, bool) {
	image = strings.TrimSpace(image)
	if !validDockerImageRef(image) {
		return "", false
	}
	return "docker rmi " + DockerShellQuote(image), true
}

func DockerPruneCommand(resource string) (string, bool) {
	switch strings.TrimSpace(resource) {
	case "containers":
		return "docker container prune -f", true
	case "networks":
		return "docker network prune -f", true
	case "volumes":
		return "docker volume prune -f", true
	case "images":
		return "docker image prune -f", true
	default:
		return "", false
	}
}

func DockerCreateContainerCommand(req DockerCreateRequest) (string, bool, bool) {
	image := strings.TrimSpace(req.Image)
	if image == "" || strings.HasPrefix(image, "-") {
		return "", false, false
	}
	startAfterCreate := dockerStartAfterCreate(req)
	args := []string{"docker"}
	if startAfterCreate {
		args = append(args, "run", "-d")
	} else {
		args = append(args, "create")
	}
	if name := strings.TrimSpace(req.Name); name != "" {
		args = append(args, "--name", DockerShellQuote(name))
	}
	if policy := strings.TrimSpace(req.RestartPolicy); policy != "" {
		if !IsAllowedDockerRestartPolicy(policy) {
			return "", false, false
		}
		args = append(args, "--restart", policy)
	}
	for _, port := range req.Ports {
		value, ok := DockerCreatePortArg(port)
		if !ok {
			return "", false, false
		}
		if value != "" {
			args = append(args, "-p", DockerShellQuote(value))
		}
	}
	for _, volume := range req.Volumes {
		value, ok := DockerCreateVolumeArg(volume)
		if !ok {
			return "", false, false
		}
		if value != "" {
			args = append(args, "-v", DockerShellQuote(value))
		}
	}
	for _, env := range req.Env {
		value, ok := DockerCreateEnvArg(env)
		if !ok {
			return "", false, false
		}
		if value != "" {
			args = append(args, "-e", DockerShellQuote(value))
		}
	}
	if network := strings.TrimSpace(req.Network); network != "" {
		args = append(args, "--network", DockerShellQuote(network))
	}
	if req.Privileged {
		args = append(args, "--privileged")
	}
	if memory := strings.TrimSpace(req.Memory); memory != "" {
		args = append(args, "-m", DockerShellQuote(memory))
	}
	if cpus := strings.TrimSpace(req.CPUs); cpus != "" {
		args = append(args, "--cpus", DockerShellQuote(cpus))
	}
	args = append(args, DockerShellQuote(image))
	if command := strings.TrimSpace(req.Command); command != "" {
		args = append(args, DockerShellQuote(command))
	}
	return strings.Join(args, " "), startAfterCreate, true
}

func DockerCreatePortArg(port DockerPortRequest) (string, bool) {
	hostIP := strings.TrimSpace(port.HostIP)
	hostPort := strings.TrimSpace(port.HostPort)
	containerPort := strings.TrimSpace(port.ContainerPort)
	protocol := strings.ToLower(strings.TrimSpace(port.Protocol))
	if protocol == "" {
		protocol = "tcp"
	}
	if hostIP == "" && hostPort == "" && containerPort == "" {
		return "", true
	}
	if containerPort == "" || protocol != "tcp" && protocol != "udp" && protocol != "sctp" {
		return "", false
	}
	value := containerPort
	if hostPort != "" {
		value = hostPort + ":" + containerPort
		if hostIP != "" {
			value = hostIP + ":" + value
		}
	}
	return value + "/" + protocol, true
}

func DockerCreateVolumeArg(volume DockerVolumeRequest) (string, bool) {
	hostPath := strings.TrimSpace(volume.HostPath)
	containerPath := strings.TrimSpace(volume.ContainerPath)
	mode := strings.TrimSpace(volume.Mode)
	if hostPath == "" && containerPath == "" && mode == "" {
		return "", true
	}
	if hostPath == "" || containerPath == "" {
		return "", false
	}
	value := hostPath + ":" + containerPath
	if mode != "" {
		if mode != "ro" && mode != "rw" {
			return "", false
		}
		value += ":" + mode
	}
	return value, true
}

func DockerCreateEnvArg(env DockerEnvRequest) (string, bool) {
	key := strings.TrimSpace(env.Key)
	if key == "" && env.Value == "" {
		return "", true
	}
	if key == "" || strings.Contains(key, "=") {
		return "", false
	}
	return key + "=" + env.Value, true
}

func IsAllowedDockerRestartPolicy(policy string) bool {
	switch strings.TrimSpace(policy) {
	case "no", "always", "unless-stopped", "on-failure":
		return true
	default:
		return false
	}
}

func DockerShellQuote(value string) string {
	if value == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func dockerStartAfterCreate(req DockerCreateRequest) bool {
	if req.StartAfterCreate == nil {
		return true
	}
	return *req.StartAfterCreate
}

func dockerCreateAPIConfig(req DockerCreateRequest) (*containertypes.Config, *containertypes.HostConfig, *networktypes.NetworkingConfig, error) {
	exposedPorts := nat.PortSet{}
	portBindings := nat.PortMap{}
	for _, port := range req.Ports {
		value, ok := DockerCreatePortArg(port)
		if !ok {
			return nil, nil, nil, fmt.Errorf("无效的端口映射")
		}
		if value == "" {
			continue
		}
		portParts := strings.SplitN(value, "/", 2)
		protocol := "tcp"
		if len(portParts) == 2 {
			protocol = portParts[1]
		}
		mapping := portParts[0]
		hostIP := strings.TrimSpace(port.HostIP)
		hostPort := strings.TrimSpace(port.HostPort)
		containerPort := strings.TrimSpace(port.ContainerPort)
		dockerPort := nat.Port(containerPort + "/" + protocol)
		exposedPorts[dockerPort] = struct{}{}
		if strings.TrimSpace(mapping) != "" && hostPort != "" {
			portBindings[dockerPort] = append(portBindings[dockerPort], nat.PortBinding{HostIP: hostIP, HostPort: hostPort})
		}
	}

	binds := []string{}
	for _, volume := range req.Volumes {
		value, ok := DockerCreateVolumeArg(volume)
		if !ok {
			return nil, nil, nil, fmt.Errorf("无效的挂载配置")
		}
		if value != "" {
			binds = append(binds, value)
		}
	}
	env := []string{}
	for _, item := range req.Env {
		value, ok := DockerCreateEnvArg(item)
		if !ok {
			return nil, nil, nil, fmt.Errorf("无效的环境变量")
		}
		if value != "" {
			env = append(env, value)
		}
	}
	config := &containertypes.Config{
		Image:        strings.TrimSpace(req.Image),
		Env:          env,
		ExposedPorts: exposedPorts,
	}
	if command := strings.TrimSpace(req.Command); command != "" {
		config.Cmd = []string{command}
	}
	hostConfig := &containertypes.HostConfig{
		Binds:        binds,
		PortBindings: portBindings,
		Privileged:   req.Privileged,
	}
	if policy := strings.TrimSpace(req.RestartPolicy); policy != "" {
		if !IsAllowedDockerRestartPolicy(policy) {
			return nil, nil, nil, fmt.Errorf("无效的重启策略")
		}
		hostConfig.RestartPolicy = containertypes.RestartPolicy{Name: containertypes.RestartPolicyMode(policy)}
	}
	if networkName := strings.TrimSpace(req.Network); networkName != "" {
		hostConfig.NetworkMode = containertypes.NetworkMode(networkName)
	}
	if memory := strings.TrimSpace(req.Memory); memory != "" {
		bytes, err := units.RAMInBytes(memory)
		if err != nil {
			return nil, nil, nil, fmt.Errorf("无效的内存限制")
		}
		hostConfig.Memory = bytes
	}
	if cpus := strings.TrimSpace(req.CPUs); cpus != "" {
		value, err := strconv.ParseFloat(cpus, 64)
		if err != nil || value < 0 {
			return nil, nil, nil, fmt.Errorf("无效的 CPU 限制")
		}
		hostConfig.NanoCPUs = int64(value * 1e9)
	}
	networkingConfig := &networktypes.NetworkingConfig{}
	return config, hostConfig, networkingConfig, nil
}

func ensureDockerImage(ctx context.Context, cli *dockerclient.Client, image string) error {
	if _, err := cli.ImageInspect(ctx, image); err == nil {
		return nil
	}
	reader, err := cli.ImagePull(ctx, image, imagetypes.PullOptions{})
	if err != nil {
		return err
	}
	defer reader.Close()
	_, _ = io.Copy(io.Discard, reader)
	return nil
}

func dockerSummaryFromAPI(row containertypes.Summary) DockerContainerSummary {
	name := ""
	if len(row.Names) > 0 {
		name = strings.TrimPrefix(row.Names[0], "/")
	}
	ports := dockerPortsFromAPI(row.Ports)
	return DockerContainerSummary{
		ID:          shortDockerID(row.ID),
		Name:        name,
		Image:       row.Image,
		Command:     row.Command,
		Ports:       dockerPortDetailsText(ports),
		PortsDetail: ports,
		State:       string(row.State),
		StatusText:  row.Status,
	}
}

func dockerInspectFromAPI(info containertypes.InspectResponse) DockerInspectSummary {
	command := []string{}
	image := ""
	hostname := ""
	if info.Config != nil {
		command = append(command, info.Config.Cmd...)
		image = info.Config.Image
		hostname = info.Config.Hostname
	}
	if len(command) == 0 && info.Path != "" {
		command = append([]string{info.Path}, info.Args...)
	}
	restartPolicy := ""
	if info.HostConfig != nil {
		restartPolicy = string(info.HostConfig.RestartPolicy.Name)
	}
	ipAddress := ""
	if info.NetworkSettings != nil {
		ipAddress = strings.TrimSpace(info.NetworkSettings.IPAddress)
		if ipAddress == "" && len(info.NetworkSettings.Networks) > 0 {
			names := make([]string, 0, len(info.NetworkSettings.Networks))
			for name := range info.NetworkSettings.Networks {
				names = append(names, name)
			}
			sort.Strings(names)
			ips := make([]string, 0, len(names))
			for _, name := range names {
				if ip := strings.TrimSpace(info.NetworkSettings.Networks[name].IPAddress); ip != "" {
					ips = append(ips, ip)
				}
			}
			ipAddress = strings.Join(ips, ", ")
		}
	}
	status := ""
	running := false
	exitCode := 0
	startedAt := ""
	finishedAt := ""
	if info.State != nil {
		status = info.State.Status
		running = info.State.Running
		exitCode = info.State.ExitCode
		startedAt = info.State.StartedAt
		finishedAt = info.State.FinishedAt
	}
	return DockerInspectSummary{
		ID:            info.ID,
		Name:          strings.TrimPrefix(info.Name, "/"),
		Image:         image,
		Status:        status,
		Running:       running,
		ExitCode:      exitCode,
		Created:       info.Created,
		StartedAt:     startedAt,
		FinishedAt:    finishedAt,
		Hostname:      hostname,
		IPAddress:     ipAddress,
		RestartPolicy: restartPolicy,
		Command:       command,
	}
}

func dockerPortsFromAPI(ports []containertypes.Port) []DockerPortDetail {
	items := make([]DockerPortDetail, 0, len(ports))
	for _, port := range ports {
		containerPort := strconv.FormatUint(uint64(port.PrivatePort), 10)
		protocol := strings.TrimSpace(port.Type)
		detail := DockerPortDetail{
			HostIP:        strings.TrimSpace(port.IP),
			ContainerPort: containerPort,
			Protocol:      protocol,
		}
		if port.PublicPort > 0 {
			detail.HostPort = strconv.FormatUint(uint64(port.PublicPort), 10)
			detail.Published = true
		}
		detail.Raw = dockerPortDetailText(detail)
		items = append(items, detail)
	}
	return items
}

func dockerPortDetailsText(ports []DockerPortDetail) string {
	parts := make([]string, 0, len(ports))
	for _, port := range ports {
		if raw := dockerPortDetailText(port); raw != "" {
			parts = append(parts, raw)
		}
	}
	return strings.Join(parts, ", ")
}

func dockerPortDetailText(port DockerPortDetail) string {
	containerPort := strings.TrimSpace(port.ContainerPort)
	if containerPort == "" {
		return ""
	}
	protocol := strings.TrimSpace(port.Protocol)
	if protocol == "" {
		protocol = "tcp"
	}
	target := containerPort + "/" + protocol
	if !port.Published || strings.TrimSpace(port.HostPort) == "" {
		return target
	}
	host := strings.TrimSpace(port.HostPort)
	if ip := strings.TrimSpace(port.HostIP); ip != "" {
		host = ip + ":" + host
	}
	return host + "->" + target
}

func shortDockerID(id string) string {
	id = strings.TrimSpace(id)
	if len(id) > 12 {
		return id[:12]
	}
	return id
}

func validDockerObjectName(name string) bool {
	name = strings.TrimSpace(name)
	return name != "" && !strings.HasPrefix(name, "-") && !strings.ContainsAny(name, "\r\n")
}

func validDockerImageRef(image string) bool {
	image = strings.TrimSpace(image)
	return image != "" && !strings.HasPrefix(image, "-") && !strings.ContainsAny(image, "\r\n")
}

func dockerImageRepoTag(tags []string) (string, string) {
	if len(tags) == 0 || strings.TrimSpace(tags[0]) == "" || tags[0] == "<none>:<none>" {
		return "<none>", "<none>"
	}
	tag := strings.TrimSpace(tags[0])
	idx := strings.LastIndex(tag, ":")
	if idx <= 0 || strings.Contains(tag[idx+1:], "/") {
		return tag, "latest"
	}
	return tag[:idx], tag[idx+1:]
}

func dockerUnixTime(value int64) string {
	if value <= 0 {
		return ""
	}
	return time.Unix(value, 0).Format(time.RFC3339)
}
