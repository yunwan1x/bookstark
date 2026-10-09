package services

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"

	"bookstark/models"
)

type SSHRunner struct {
	Timeout time.Duration
}

func (r SSHRunner) TestConnection(host *models.AssetSSHHost, credential string) error {
	client, err := r.dial(host, credential)
	if err != nil {
		return err
	}
	return client.Close()
}

func (r SSHRunner) RunCommand(host *models.AssetSSHHost, credential string, command string) (string, error) {
	client, err := r.dial(host, credential)
	if err != nil {
		return "", err
	}
	defer client.Close()
	session, err := client.NewSession()
	if err != nil {
		return "", fmt.Errorf("create ssh session: %w", err)
	}
	defer session.Close()
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	session.Stdout = &stdout
	session.Stderr = &stderr
	if err := session.Run(command); err != nil {
		return stdout.String() + stderr.String(), fmt.Errorf("run remote command: %w", err)
	}
	return stdout.String() + stderr.String(), nil
}

func (r SSHRunner) StreamCommand(ctx context.Context, host *models.AssetSSHHost, credential string, command string, onChunk func([]byte) error) error {
	client, err := r.dial(host, credential)
	if err != nil {
		return err
	}
	defer client.Close()

	session, err := client.NewSession()
	if err != nil {
		return fmt.Errorf("create ssh session: %w", err)
	}
	defer session.Close()

	stdout, err := session.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := session.StderrPipe()
	if err != nil {
		return err
	}
	if err := session.Start(command); err != nil {
		return fmt.Errorf("run remote command: %w", err)
	}

	var callbackMu sync.Mutex
	copyErrs := make(chan error, 2)
	copyPipe := func(r io.Reader) {
		buf := make([]byte, 4096)
		for {
			n, readErr := r.Read(buf)
			if n > 0 && onChunk != nil {
				chunk := append([]byte(nil), buf[:n]...)
				callbackMu.Lock()
				writeErr := onChunk(chunk)
				callbackMu.Unlock()
				if writeErr != nil {
					copyErrs <- writeErr
					_ = session.Close()
					return
				}
			}
			if readErr != nil {
				if readErr == io.EOF {
					copyErrs <- nil
				} else {
					copyErrs <- readErr
				}
				return
			}
		}
	}
	go copyPipe(stdout)
	go copyPipe(stderr)

	waitErr := make(chan error, 1)
	go func() {
		waitErr <- session.Wait()
	}()
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			_ = session.Close()
		case <-done:
		}
	}()

	var firstCopyErr error
	for copyDone := 0; ; {
		select {
		case err := <-copyErrs:
			copyDone++
			if err != nil && firstCopyErr == nil {
				firstCopyErr = err
			}
			if copyDone == 2 && firstCopyErr != nil {
				return firstCopyErr
			}
		case err := <-waitErr:
			if ctx.Err() != nil {
				return nil
			}
			if firstCopyErr != nil {
				return firstCopyErr
			}
			if err != nil {
				return fmt.Errorf("run remote command: %w", err)
			}
			return nil
		case <-ctx.Done():
			_ = session.Close()
			return nil
		}
	}
}

func (r SSHRunner) dial(host *models.AssetSSHHost, credential string) (*ssh.Client, error) {
	auth, err := sshAuth(host.AuthType, credential)
	if err != nil {
		return nil, err
	}
	timeout := r.Timeout
	if timeout == 0 {
		timeout = 10 * time.Second
	}
	config := &ssh.ClientConfig{
		User:            host.Username,
		Auth:            []ssh.AuthMethod{auth},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         timeout,
	}
	client, err := ssh.Dial("tcp", net.JoinHostPort(host.Host, fmt.Sprintf("%d", host.Port)), config)
	if err != nil {
		return nil, sanitizeSSHError(err)
	}
	return client, nil
}

func sshAuth(authType string, credential string) (ssh.AuthMethod, error) {
	if authType == models.AssetAuthKey {
		signer, err := ssh.ParsePrivateKey([]byte(credential))
		if err != nil {
			var missing *ssh.PassphraseMissingError
			if errors.As(err, &missing) {
				return nil, fmt.Errorf("私钥需要密码")
			}
			return nil, fmt.Errorf("私钥解析失败")
		}
		return ssh.PublicKeys(signer), nil
	}
	return ssh.Password(credential), nil
}

func sanitizeSSHError(err error) error {
	log.Printf("asset SSH connection failed: %v", err)
	msg := err.Error()
	var netErr net.Error
	switch {
	case strings.Contains(msg, "unable to authenticate"):
		return fmt.Errorf("认证失败")
	case errors.Is(err, context.DeadlineExceeded), errors.As(err, &netErr) && netErr.Timeout(), strings.Contains(msg, "i/o timeout"):
		return fmt.Errorf("连接超时")
	default:
		return fmt.Errorf("SSH 连接失败")
	}
}

type dockerInspectRow struct {
	ID      string   `json:"Id"`
	Name    string   `json:"Name"`
	Created string   `json:"Created"`
	Path    string   `json:"Path"`
	Args    []string `json:"Args"`
	Config  struct {
		Hostname string   `json:"Hostname"`
		Image    string   `json:"Image"`
		Cmd      []string `json:"Cmd"`
	} `json:"Config"`
	State struct {
		Status     string `json:"Status"`
		Running    bool   `json:"Running"`
		ExitCode   int    `json:"ExitCode"`
		StartedAt  string `json:"StartedAt"`
		FinishedAt string `json:"FinishedAt"`
	} `json:"State"`
	HostConfig struct {
		RestartPolicy struct {
			Name string `json:"Name"`
		} `json:"RestartPolicy"`
	} `json:"HostConfig"`
	NetworkSettings struct {
		IPAddress string `json:"IPAddress"`
		Networks  map[string]struct {
			IPAddress string `json:"IPAddress"`
		} `json:"Networks"`
	} `json:"NetworkSettings"`
}

type DockerInspectSummary struct {
	ID            string   `json:"id"`
	Name          string   `json:"name"`
	Image         string   `json:"image"`
	Status        string   `json:"status"`
	Running       bool     `json:"running"`
	ExitCode      int      `json:"exit_code"`
	Created       string   `json:"created"`
	StartedAt     string   `json:"started_at"`
	FinishedAt    string   `json:"finished_at"`
	Hostname      string   `json:"hostname"`
	IPAddress     string   `json:"ip_address"`
	RestartPolicy string   `json:"restart_policy"`
	Command       []string `json:"command"`
}

type DockerContainerSummary struct {
	ID          string             `json:"id"`
	Name        string             `json:"name"`
	Image       string             `json:"image"`
	Command     string             `json:"command"`
	Ports       string             `json:"ports"`
	PortsDetail []DockerPortDetail `json:"ports_detail"`
	State       string             `json:"state"`
	StatusText  string             `json:"status_text,omitempty"`
}

type DockerPortDetail struct {
	HostIP        string `json:"host_ip,omitempty"`
	HostPort      string `json:"host_port,omitempty"`
	ContainerPort string `json:"container_port,omitempty"`
	Protocol      string `json:"protocol,omitempty"`
	Published     bool   `json:"published"`
	Raw           string `json:"raw"`
}

type DockerNetworkSummary struct {
	ID     string `json:"id,omitempty"`
	Name   string `json:"name"`
	Driver string `json:"driver,omitempty"`
	Scope  string `json:"scope,omitempty"`
}

type DockerVolumeSummary struct {
	Name       string `json:"name"`
	Driver     string `json:"driver,omitempty"`
	Scope      string `json:"scope,omitempty"`
	Mountpoint string `json:"mountpoint,omitempty"`
	Size       string `json:"size,omitempty"`
	CreatedAt  string `json:"created_at,omitempty"`
}

type DockerImageSummary struct {
	ID           string `json:"id"`
	Repository   string `json:"repository"`
	Tag          string `json:"tag"`
	Size         string `json:"size,omitempty"`
	CreatedSince string `json:"created_since,omitempty"`
	CreatedAt    string `json:"created_at,omitempty"`
	Containers   int64  `json:"containers,omitempty"`
}

type dockerPSRow struct {
	ID      string `json:"ID"`
	Image   string `json:"Image"`
	Command string `json:"Command"`
	Names   string `json:"Names"`
	Ports   string `json:"Ports"`
	State   string `json:"State"`
	Status  string `json:"Status"`
}

func ParseDockerInspectStatus(raw string) (status string, image string, err error) {
	info, err := ParseDockerInspect(raw)
	if err != nil {
		return "", "", err
	}
	return info.Status, info.Image, nil
}

func ParseDockerInspect(raw string) (DockerInspectSummary, error) {
	var rows []dockerInspectRow
	if err := json.Unmarshal([]byte(raw), &rows); err != nil {
		return DockerInspectSummary{}, fmt.Errorf("解析 docker inspect 输出失败")
	}
	if len(rows) == 0 {
		return DockerInspectSummary{}, fmt.Errorf("容器不存在")
	}
	row := rows[0]
	command := row.Config.Cmd
	if len(command) == 0 {
		command = append([]string{row.Path}, row.Args...)
	}
	ipAddress := strings.TrimSpace(row.NetworkSettings.IPAddress)
	if ipAddress == "" && len(row.NetworkSettings.Networks) > 0 {
		networkNames := make([]string, 0, len(row.NetworkSettings.Networks))
		for name := range row.NetworkSettings.Networks {
			networkNames = append(networkNames, name)
		}
		sort.Strings(networkNames)
		ips := make([]string, 0, len(networkNames))
		for _, name := range networkNames {
			ip := strings.TrimSpace(row.NetworkSettings.Networks[name].IPAddress)
			if ip == "" {
				continue
			}
			ips = append(ips, ip)
		}
		ipAddress = strings.Join(ips, ", ")
	}
	return DockerInspectSummary{
		ID:            row.ID,
		Name:          strings.TrimPrefix(row.Name, "/"),
		Image:         row.Config.Image,
		Status:        row.State.Status,
		Running:       row.State.Running,
		ExitCode:      row.State.ExitCode,
		Created:       row.Created,
		StartedAt:     row.State.StartedAt,
		FinishedAt:    row.State.FinishedAt,
		Hostname:      row.Config.Hostname,
		IPAddress:     ipAddress,
		RestartPolicy: row.HostConfig.RestartPolicy.Name,
		Command:       command,
	}, nil
}

func ParseDockerPS(raw string) ([]DockerContainerSummary, error) {
	scanner := bufio.NewScanner(strings.NewReader(raw))
	scanner.Buffer(make([]byte, 1024), 1024*1024)

	containers := make([]DockerContainerSummary, 0)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var row dockerPSRow
		if err := json.Unmarshal([]byte(line), &row); err != nil {
			return nil, fmt.Errorf("解析 docker ps 输出失败")
		}
		containers = append(containers, DockerContainerSummary{
			ID:          row.ID,
			Name:        row.Names,
			Image:       row.Image,
			Command:     row.Command,
			Ports:       row.Ports,
			PortsDetail: ParseDockerPorts(row.Ports),
			State:       row.State,
			StatusText:  row.Status,
		})
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("读取 docker ps 输出失败")
	}
	return containers, nil
}

func ParseDockerNetworks(raw string) []DockerNetworkSummary {
	scanner := bufio.NewScanner(strings.NewReader(raw))
	scanner.Buffer(make([]byte, 1024), 1024*1024)
	networks := make([]DockerNetworkSummary, 0)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.TrimSpace(line) == "" {
			continue
		}
		var row struct {
			ID     string `json:"ID"`
			Name   string `json:"Name"`
			Driver string `json:"Driver"`
			Scope  string `json:"Scope"`
		}
		if err := json.Unmarshal([]byte(line), &row); err != nil {
			continue
		}
		name := strings.TrimSpace(row.Name)
		if name == "" {
			continue
		}
		networks = append(networks, DockerNetworkSummary{
			ID:     strings.TrimSpace(row.ID),
			Name:   name,
			Driver: strings.TrimSpace(row.Driver),
			Scope:  strings.TrimSpace(row.Scope),
		})
	}
	return networks
}

func ParseDockerVolumes(raw string) []DockerVolumeSummary {
	scanner := bufio.NewScanner(strings.NewReader(raw))
	scanner.Buffer(make([]byte, 1024), 1024*1024)
	volumes := make([]DockerVolumeSummary, 0)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var row struct {
			Name       string `json:"Name"`
			Driver     string `json:"Driver"`
			Scope      string `json:"Scope"`
			Mountpoint string `json:"Mountpoint"`
			Size       string `json:"Size"`
			CreatedAt  string `json:"CreatedAt"`
		}
		if err := json.Unmarshal([]byte(line), &row); err != nil {
			continue
		}
		name := strings.TrimSpace(row.Name)
		if name == "" {
			continue
		}
		volumes = append(volumes, DockerVolumeSummary{
			Name:       name,
			Driver:     strings.TrimSpace(row.Driver),
			Scope:      strings.TrimSpace(row.Scope),
			Mountpoint: strings.TrimSpace(row.Mountpoint),
			Size:       strings.TrimSpace(row.Size),
			CreatedAt:  strings.TrimSpace(row.CreatedAt),
		})
	}
	return volumes
}

func ParseDockerImages(raw string) []DockerImageSummary {
	scanner := bufio.NewScanner(strings.NewReader(raw))
	scanner.Buffer(make([]byte, 1024), 1024*1024)
	images := make([]DockerImageSummary, 0)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var row struct {
			ID           string `json:"ID"`
			Repository   string `json:"Repository"`
			Tag          string `json:"Tag"`
			Size         string `json:"Size"`
			CreatedSince string `json:"CreatedSince"`
			CreatedAt    string `json:"CreatedAt"`
			Containers   string `json:"Containers"`
		}
		if err := json.Unmarshal([]byte(line), &row); err != nil {
			continue
		}
		id := strings.TrimSpace(row.ID)
		repository := strings.TrimSpace(row.Repository)
		tag := strings.TrimSpace(row.Tag)
		if id == "" && repository == "" {
			continue
		}
		images = append(images, DockerImageSummary{
			ID:           id,
			Repository:   repository,
			Tag:          tag,
			Size:         strings.TrimSpace(row.Size),
			CreatedSince: strings.TrimSpace(row.CreatedSince),
			CreatedAt:    strings.TrimSpace(row.CreatedAt),
		})
	}
	return images
}

func ParseDockerPorts(raw string) []DockerPortDetail {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	ports := make([]DockerPortDetail, 0, len(parts))
	for _, part := range parts {
		item := strings.TrimSpace(part)
		if item == "" {
			continue
		}
		ports = append(ports, parseDockerPort(item))
	}
	return ports
}

func parseDockerPort(raw string) DockerPortDetail {
	port := DockerPortDetail{Raw: raw}
	mappingParts := strings.SplitN(raw, "->", 2)
	if len(mappingParts) != 2 {
		port.ContainerPort, port.Protocol = splitDockerPortProtocol(raw)
		return port
	}

	port.Published = true
	port.ContainerPort, port.Protocol = splitDockerPortProtocol(mappingParts[1])
	host := strings.TrimSpace(mappingParts[0])
	if host == "" {
		return port
	}
	if idx := strings.LastIndex(host, ":"); idx >= 0 {
		port.HostIP = strings.Trim(host[:idx], "[]")
		port.HostPort = strings.TrimSpace(host[idx+1:])
		return port
	}
	port.HostPort = host
	return port
}

func splitDockerPortProtocol(raw string) (string, string) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", ""
	}
	if idx := strings.LastIndex(raw, "/"); idx >= 0 {
		return strings.TrimSpace(raw[:idx]), strings.TrimSpace(raw[idx+1:])
	}
	return raw, ""
}
