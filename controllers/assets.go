package controllers

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"

	"bookstark/conf"
	"bookstark/middleware"
	"bookstark/models"
	"bookstark/services"
)

func AssetsPage(c *gin.Context) {
	data := commonData(c, "assets")
	data["AssetPageMode"] = "index"
	data["DockerHostID"] = ""
	data["FilesHostID"] = ""
	data["WebDAVServerID"] = ""
	c.HTML(http.StatusOK, "admin_assets.html", data)
}

func AssetDockerHostPage(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		c.String(http.StatusBadRequest, "invalid SSH host ID")
		return
	}
	data := commonData(c, "assets")
	data["AssetPageMode"] = "docker-host"
	data["DockerHostID"] = fmt.Sprintf("%d", id)
	data["FilesHostID"] = ""
	data["WebDAVServerID"] = ""
	c.HTML(http.StatusOK, "admin_assets.html", data)
}

var assetWSUpgrader = websocket.Upgrader{
	CheckOrigin: checkAssetWSOrigin,
}

type assetSSHHostRequest struct {
	Name             string `json:"name"`
	Host             string `json:"host"`
	Port             int    `json:"port"`
	Shell            string `json:"shell"`
	Cwd              string `json:"cwd"`
	DockerSocketPath string `json:"docker_socket_path"`
	CredentialID     int64  `json:"credential_id"`
	Username         string `json:"username"`
	AuthType         string `json:"auth_type"`
	Credential       string `json:"credential"`
	Status           string `json:"status"`
}

type assetCredentialRequest struct {
	Name       string `json:"name"`
	Username   string `json:"username"`
	AuthType   string `json:"auth_type"`
	Credential string `json:"credential"`
}

type assetDockerContainerResponse struct {
	ID          string                      `json:"id"`
	Name        string                      `json:"name"`
	Image       string                      `json:"image"`
	Command     string                      `json:"command"`
	SSHHostID   int64                       `json:"ssh_host_id"`
	SSHHostName string                      `json:"ssh_host_name"`
	Ports       string                      `json:"ports"`
	PortsDetail []services.DockerPortDetail `json:"ports_detail"`
	Status      string                      `json:"status"`
	StatusText  string                      `json:"status_text,omitempty"`
}

type assetDockerRestartPolicyRequest struct {
	Policy string `json:"policy"`
}

type assetDockerNamedObjectRequest struct {
	Name   string `json:"name"`
	Driver string `json:"driver"`
	Image  string `json:"image"`
}

type assetDockerCreateRequest = services.DockerCreateRequest
type assetDockerPortRequest = services.DockerPortRequest
type assetDockerVolumeRequest = services.DockerVolumeRequest
type assetDockerEnvRequest = services.DockerEnvRequest

type assetCommandRunner interface {
	TestConnection(host *models.AssetSSHHost, credential string) error
	RunCommand(host *models.AssetSSHHost, credential string, command string) (string, error)
	StreamCommand(ctx context.Context, host *models.AssetSSHHost, credential string, command string, onChunk func([]byte) error) error
}

type assetRunnerAdapter struct {
	test   func(host *models.AssetSSHHost, credential string) error
	run    func(host *models.AssetSSHHost, credential string, command string) (string, error)
	stream func(ctx context.Context, host *models.AssetSSHHost, credential string, command string, onChunk func([]byte) error) error
}

func (a assetRunnerAdapter) TestConnection(host *models.AssetSSHHost, credential string) error {
	return a.test(host, credential)
}

func (a assetRunnerAdapter) RunCommand(host *models.AssetSSHHost, credential string, command string) (string, error) {
	return a.run(host, credential, command)
}

func (a assetRunnerAdapter) StreamCommand(ctx context.Context, host *models.AssetSSHHost, credential string, command string, onChunk func([]byte) error) error {
	if a.stream == nil {
		return fmt.Errorf("stream command runner is not configured")
	}
	return a.stream(ctx, host, credential, command, onChunk)
}

var assetSSHRunner assetCommandRunner = services.SSHRunner{Timeout: 10 * time.Second}

func assetDockerClient() services.DockerClient {
	cli := services.SSHDockerCLIClient{Runner: assetSSHRunner}
	if _, ok := assetSSHRunner.(assetRunnerAdapter); ok {
		return cli
	}
	return services.SSHDockerFallbackClient{
		Primary:  services.SSHDockerAPIClient{Timeout: 10 * time.Second},
		Fallback: cli,
	}
}

func SetAssetSSHRunnerForTest(
	testFn func(host *models.AssetSSHHost, credential string) error,
	runFn func(host *models.AssetSSHHost, credential string, command string) (string, error),
	streamFn ...func(ctx context.Context, host *models.AssetSSHHost, credential string, command string, onChunk func([]byte) error) error,
) func() {
	prev := assetSSHRunner
	var stream func(ctx context.Context, host *models.AssetSSHHost, credential string, command string, onChunk func([]byte) error) error
	if len(streamFn) > 0 {
		stream = streamFn[0]
	}
	assetSSHRunner = assetRunnerAdapter{test: testFn, run: runFn, stream: stream}
	return func() {
		assetSSHRunner = prev
	}
}

func ListAssetSSHHosts(c *gin.Context) {
	hosts, err := models.ListAssetSSHHosts(models.AssetSSHHostFilter{
		Query:  strings.TrimSpace(c.Query("q")),
		Status: strings.TrimSpace(c.Query("status")),
	})
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询 SSH 主机失败")
		return
	}
	if err := fillAssetSSHHostCredentials(hosts); err != nil {
		apiError(c, http.StatusInternalServerError, "读取凭据失败")
		return
	}
	apiSuccess(c, hosts)
}

func CreateAssetSSHHost(c *gin.Context) {
	var req assetSSHHostRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	normalizeAssetSSHRequest(&req)
	if err := validateAssetSSHRequest(req, true); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	cred, err := resolveAssetSSHCredential(req, 0, middleware.GetMemberID(c), true)
	if err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	id, err := models.CreateAssetSSHHost(&models.AssetSSHHost{
		Name:             req.Name,
		Host:             req.Host,
		Port:             req.Port,
		Shell:            req.Shell,
		Cwd:              req.Cwd,
		DockerSocketPath: req.DockerSocketPath,
		CredentialID:     cred.CredentialID,
		Username:         cred.Username,
		AuthType:         cred.AuthType,
		CredentialCipher: cred.CredentialCipher,
		CredentialHint:   cred.CredentialHint,
		Status:           models.AssetStatusUnknown,
		CreatedBy:        middleware.GetMemberID(c),
	})
	if err != nil {
		apiError(c, http.StatusInternalServerError, "创建 SSH 主机失败")
		return
	}
	asset, err := models.GetAssetSSHHost(id)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 SSH 主机失败")
		return
	}
	if err := fillAssetSSHHostCredential(asset); err != nil {
		apiError(c, http.StatusInternalServerError, "读取凭据失败")
		return
	}
	apiSuccess(c, asset)
}

func UpdateAssetSSHHost(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的 SSH 主机 ID")
		return
	}
	var req assetSSHHostRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	normalizeAssetSSHRequest(&req)
	if err := validateAssetSSHRequest(req, false); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	existing, err := models.GetAssetSSHHost(id)
	if err == sql.ErrNoRows {
		apiError(c, http.StatusNotFound, "SSH 主机不存在")
		return
	}
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 SSH 主机失败")
		return
	}
	asset := &models.AssetSSHHost{
		HostID:           id,
		Name:             req.Name,
		Host:             req.Host,
		Port:             req.Port,
		Shell:            req.Shell,
		Cwd:              req.Cwd,
		DockerSocketPath: req.DockerSocketPath,
		CredentialID:     existing.CredentialID,
		Username:         existing.Username,
		AuthType:         existing.AuthType,
		Status:           existing.Status,
		LastCheckTime:    existing.LastCheckTime,
	}
	replaceCredential := req.CredentialID > 0 || strings.TrimSpace(req.Credential) != ""
	if replaceCredential {
		cred, err := resolveAssetSSHCredential(req, existing.CredentialID, middleware.GetMemberID(c), false)
		if err != nil {
			apiError(c, http.StatusBadRequest, err.Error())
			return
		}
		asset.CredentialID = cred.CredentialID
		asset.Username = cred.Username
		asset.AuthType = cred.AuthType
		asset.CredentialCipher = cred.CredentialCipher
		asset.CredentialHint = cred.CredentialHint
	}
	if err := models.UpdateAssetSSHHost(asset, replaceCredential); err != nil {
		apiError(c, http.StatusInternalServerError, "更新 SSH 主机失败")
		return
	}
	updated, err := models.GetAssetSSHHost(id)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 SSH 主机失败")
		return
	}
	if err := fillAssetSSHHostCredential(updated); err != nil {
		apiError(c, http.StatusInternalServerError, "读取凭据失败")
		return
	}
	apiSuccess(c, updated)
}

func ListAssetCredentials(c *gin.Context) {
	credentials, err := models.ListAssetCredentials()
	if err != nil {
		apiError(c, http.StatusInternalServerError, "查询凭据失败")
		return
	}
	if err := fillAssetCredentials(credentials); err != nil {
		apiError(c, http.StatusInternalServerError, "读取凭据失败")
		return
	}
	apiSuccess(c, credentials)
}

func CreateAssetCredential(c *gin.Context) {
	var req assetCredentialRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	normalizeAssetCredentialRequest(&req)
	if err := validateAssetCredentialRequest(req, true); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	encrypted, err := encodeAssetCredential(req.Credential)
	if err != nil {
		apiError(c, http.StatusInternalServerError, err.Error())
		return
	}
	id, err := models.CreateAssetCredential(&models.AssetCredential{
		Name:             req.Name,
		Username:         req.Username,
		AuthType:         req.AuthType,
		CredentialCipher: encrypted,
		CredentialHint:   services.CredentialHint(req.AuthType),
		CreatedBy:        middleware.GetMemberID(c),
	})
	if err != nil {
		apiError(c, http.StatusInternalServerError, "创建凭据失败")
		return
	}
	cred, err := models.GetAssetCredential(id)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取凭据失败")
		return
	}
	if err := fillAssetCredential(cred); err != nil {
		apiError(c, http.StatusInternalServerError, "读取凭据失败")
		return
	}
	apiSuccess(c, cred)
}

func UpdateAssetCredential(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的凭据 ID")
		return
	}
	existing, err := models.GetAssetCredential(id)
	if err == sql.ErrNoRows {
		apiError(c, http.StatusNotFound, "凭据不存在")
		return
	}
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取凭据失败")
		return
	}
	var req assetCredentialRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	normalizeAssetCredentialRequest(&req)
	if err := validateAssetCredentialRequest(req, false); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	existing.Name = req.Name
	existing.Username = req.Username
	existing.AuthType = req.AuthType
	if strings.TrimSpace(req.Credential) != "" {
		encrypted, err := encodeAssetCredential(req.Credential)
		if err != nil {
			apiError(c, http.StatusInternalServerError, err.Error())
			return
		}
		existing.CredentialCipher = encrypted
	}
	existing.CredentialHint = services.CredentialHint(req.AuthType)
	if err := models.UpdateAssetCredential(existing); err != nil {
		apiError(c, http.StatusInternalServerError, "更新凭据失败")
		return
	}
	updated, err := models.GetAssetCredential(id)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取凭据失败")
		return
	}
	if err := fillAssetCredential(updated); err != nil {
		apiError(c, http.StatusInternalServerError, "读取凭据失败")
		return
	}
	apiSuccess(c, updated)
}

func DeleteAssetCredential(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的凭据 ID")
		return
	}
	if err := models.DeleteAssetCredential(id); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	apiSuccessMsg(c, "删除成功")
}

func DeleteAssetSSHHost(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的 SSH 主机 ID")
		return
	}
	if err := models.DeleteAssetSSHHost(id); err != nil {
		apiError(c, http.StatusInternalServerError, "删除 SSH 主机失败")
		return
	}
	apiSuccessMsg(c, "删除成功")
}

func TestAssetSSHHost(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的 SSH 主机 ID")
		return
	}
	host, err := models.GetAssetSSHHost(id)
	if err == sql.ErrNoRows {
		apiError(c, http.StatusNotFound, "SSH 主机不存在")
		return
	}
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 SSH 主机失败")
		return
	}
	credential, err := decryptAssetCredential(host.CredentialCipher)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "解密凭据失败")
		return
	}

	status := models.AssetStatusOnline
	message := "连接成功"
	if err := assetSSHRunner.TestConnection(host, credential); err != nil {
		status = models.AssetStatusOffline
		message = err.Error()
	}
	checkedAt := time.Now()
	_ = models.UpdateAssetSSHHostStatus(id, status, checkedAt)
	apiSuccess(c, gin.H{"status": status, "message": message, "checked_at": checkedAt})
}

func AssetSSHTerminal(c *gin.Context) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的 SSH 主机 ID")
		return
	}
	host, err := models.GetAssetSSHHost(id)
	if err == sql.ErrNoRows {
		apiError(c, http.StatusNotFound, "SSH 主机不存在")
		return
	}
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 SSH 主机失败")
		return
	}
	credential, err := decryptAssetCredential(host.CredentialCipher)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "解密凭据失败")
		return
	}
	ws, err := assetWSUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	defer ws.Close()

	settings := models.GetAssetSettings()
	services.BridgeSSHTerminal(ws, host, credential, services.TerminalOptions{
		IdleTimeout:      time.Duration(settings.TerminalIdleTimeoutSeconds) * time.Second,
		DefaultShell:     host.Shell,
		WorkingDirectory: host.Cwd,
	})
}

func ListAssetDockerContainers(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	containers, err := assetDockerClient().ListContainers(c.Request.Context(), host, credential)
	if err != nil {
		apiError(c, http.StatusBadGateway, err.Error())
		return
	}
	items := make([]assetDockerContainerResponse, 0, len(containers))
	for _, container := range containers {
		items = append(items, assetDockerContainerResponse{
			ID:          container.ID,
			Name:        container.Name,
			Image:       container.Image,
			Command:     strings.TrimSpace(container.Command),
			SSHHostID:   host.HostID,
			SSHHostName: host.Name,
			Ports:       strings.TrimSpace(container.Ports),
			PortsDetail: container.PortsDetail,
			Status:      normalizeDockerInspectStatus(container.State),
			StatusText:  strings.TrimSpace(container.StatusText),
		})
	}
	apiSuccess(c, items)
}

func ListAssetDockerNetworks(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	networks, err := assetDockerClient().ListNetworks(c.Request.Context(), host, credential)
	if err != nil {
		apiError(c, http.StatusBadGateway, err.Error())
		return
	}
	apiSuccess(c, networks)
}

func CreateAssetDockerNetwork(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	var req assetDockerNamedObjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "无效的 Docker 网络参数")
		return
	}
	output, err := assetDockerClient().CreateNetwork(c.Request.Context(), host, credential, strings.TrimSpace(req.Name), strings.TrimSpace(req.Driver))
	if err != nil {
		status := http.StatusBadGateway
		if strings.Contains(err.Error(), "无效") {
			status = http.StatusBadRequest
		}
		apiError(c, status, err.Error())
		return
	}
	apiSuccess(c, gin.H{"name": strings.TrimSpace(req.Name), "output": strings.TrimSpace(output)})
}

func DeleteAssetDockerNetwork(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	name := strings.TrimSpace(c.Param("network"))
	output, err := assetDockerClient().RemoveNetwork(c.Request.Context(), host, credential, name)
	if err != nil {
		status := http.StatusBadGateway
		if strings.Contains(err.Error(), "无效") {
			status = http.StatusBadRequest
		}
		apiError(c, status, err.Error())
		return
	}
	apiSuccess(c, gin.H{"name": name, "output": strings.TrimSpace(output)})
}

func ListAssetDockerVolumes(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	volumes, err := assetDockerClient().ListVolumes(c.Request.Context(), host, credential)
	if err != nil {
		apiError(c, http.StatusBadGateway, err.Error())
		return
	}
	apiSuccess(c, volumes)
}

func CreateAssetDockerVolume(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	var req assetDockerNamedObjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "无效的 Docker 存储参数")
		return
	}
	output, err := assetDockerClient().CreateVolume(c.Request.Context(), host, credential, strings.TrimSpace(req.Name), strings.TrimSpace(req.Driver))
	if err != nil {
		status := http.StatusBadGateway
		if strings.Contains(err.Error(), "无效") {
			status = http.StatusBadRequest
		}
		apiError(c, status, err.Error())
		return
	}
	apiSuccess(c, gin.H{"name": strings.TrimSpace(req.Name), "output": strings.TrimSpace(output)})
}

func DeleteAssetDockerVolume(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	name := strings.TrimSpace(c.Param("volume"))
	output, err := assetDockerClient().RemoveVolume(c.Request.Context(), host, credential, name)
	if err != nil {
		status := http.StatusBadGateway
		if strings.Contains(err.Error(), "无效") {
			status = http.StatusBadRequest
		}
		apiError(c, status, err.Error())
		return
	}
	apiSuccess(c, gin.H{"name": name, "output": strings.TrimSpace(output)})
}

func ListAssetDockerImages(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	images, err := assetDockerClient().ListImages(c.Request.Context(), host, credential)
	if err != nil {
		apiError(c, http.StatusBadGateway, err.Error())
		return
	}
	apiSuccess(c, images)
}

func PullAssetDockerImage(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	var req assetDockerNamedObjectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "无效的 Docker 镜像参数")
		return
	}
	image := strings.TrimSpace(firstNonEmpty(req.Image, req.Name))
	output, err := assetDockerClient().PullImage(c.Request.Context(), host, credential, image)
	if err != nil {
		status := http.StatusBadGateway
		if strings.Contains(err.Error(), "无效") {
			status = http.StatusBadRequest
		}
		apiError(c, status, err.Error())
		return
	}
	apiSuccess(c, gin.H{"image": image, "output": strings.TrimSpace(output)})
}

func DeleteAssetDockerImage(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	image := strings.Trim(strings.TrimSpace(c.Param("image")), "/")
	output, err := assetDockerClient().RemoveImage(c.Request.Context(), host, credential, image)
	if err != nil {
		status := http.StatusBadGateway
		if strings.Contains(err.Error(), "无效") {
			status = http.StatusBadRequest
		}
		apiError(c, status, err.Error())
		return
	}
	apiSuccess(c, gin.H{"image": image, "output": strings.TrimSpace(output)})
}

func PruneAssetDocker(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	resource := strings.TrimSpace(c.Param("resource"))
	output, err := assetDockerClient().Prune(c.Request.Context(), host, credential, resource)
	if err != nil {
		status := http.StatusBadGateway
		if strings.Contains(err.Error(), "无效") {
			status = http.StatusBadRequest
		}
		apiError(c, status, err.Error())
		return
	}
	apiSuccess(c, gin.H{"resource": resource, "output": strings.TrimSpace(output)})
}

func CreateAssetDockerContainer(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	var req assetDockerCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "无效的 Docker 容器参数")
		return
	}
	if _, _, ok := services.DockerCreateContainerCommand(req); !ok {
		apiError(c, http.StatusBadRequest, "无效的 Docker 容器参数")
		return
	}
	result, err := assetDockerClient().CreateContainer(c.Request.Context(), host, credential, req)
	if err != nil {
		apiError(c, http.StatusBadGateway, err.Error())
		return
	}
	apiSuccess(c, gin.H{
		"id":                 result.ID,
		"image":              result.Image,
		"name":               result.Name,
		"start_after_create": result.StartAfterCreate,
		"output":             result.Output,
	})
}

func InspectAssetDockerContainer(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	container := strings.TrimSpace(c.Param("container"))
	if container == "" {
		apiError(c, http.StatusBadRequest, "无效的 Docker 容器标识")
		return
	}
	info, err := assetDockerClient().InspectContainer(c.Request.Context(), host, credential, container)
	if err != nil {
		apiError(c, http.StatusBadGateway, err.Error())
		return
	}
	now := time.Now()
	apiSuccess(c, gin.H{
		"id":             firstNonEmpty(info.ID, container),
		"name":           firstNonEmpty(info.Name, container),
		"image":          info.Image,
		"status":         normalizeDockerInspectStatus(info.Status),
		"raw_status":     info.Status,
		"running":        info.Running,
		"exit_code":      info.ExitCode,
		"created":        info.Created,
		"started_at":     info.StartedAt,
		"finished_at":    info.FinishedAt,
		"hostname":       info.Hostname,
		"ip_address":     info.IPAddress,
		"restart_policy": info.RestartPolicy,
		"command":        info.Command,
		"checked_at":     now,
	})
}

func OperateAssetDockerContainer(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	container := strings.TrimSpace(c.Param("container"))
	if container == "" {
		apiError(c, http.StatusBadRequest, "无效的 Docker 容器标识")
		return
	}
	action := strings.TrimSpace(c.Param("action"))
	if action == "restart-policy" {
		var req assetDockerRestartPolicyRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			apiError(c, http.StatusBadRequest, "无效的重启策略")
			return
		}
		policy := strings.TrimSpace(req.Policy)
		if !services.IsAllowedDockerRestartPolicy(policy) {
			apiError(c, http.StatusBadRequest, "无效的重启策略")
			return
		}
		output, err := assetDockerClient().UpdateRestartPolicy(c.Request.Context(), host, credential, container, policy)
		if err != nil {
			apiError(c, http.StatusBadGateway, err.Error())
			return
		}
		apiSuccess(c, gin.H{"id": container, "action": action, "policy": policy, "output": strings.TrimSpace(output)})
		return
	}

	output, err := assetDockerClient().OperateContainer(c.Request.Context(), host, credential, container, action)
	if err != nil {
		status := http.StatusBadGateway
		if strings.Contains(err.Error(), "无效") {
			status = http.StatusBadRequest
		}
		apiError(c, status, err.Error())
		return
	}
	apiSuccess(c, gin.H{"id": container, "action": action, "output": strings.TrimSpace(output)})
}

func dockerRestartPolicyCommand(policy string, container string) (string, bool) {
	if !isAllowedDockerRestartPolicy(policy) {
		return "", false
	}
	return "docker update --restart " + policy + " " + shellQuote(container), true
}

func AssetDockerLogs(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	container := strings.TrimSpace(c.Param("container"))
	if container == "" {
		apiError(c, http.StatusBadRequest, "无效的 Docker 容器标识")
		return
	}
	tail, ok := parseDockerLogTail(c.DefaultQuery("tail", "200"))
	if !ok {
		apiError(c, http.StatusBadRequest, "日志行数必须在 1-10000 之间")
		return
	}
	reader, err := assetDockerClient().Logs(c.Request.Context(), host, credential, container, tail, false)
	if err != nil {
		apiError(c, http.StatusBadGateway, err.Error())
		return
	}
	defer reader.Close()
	output, err := io.ReadAll(reader)
	if err != nil {
		apiError(c, http.StatusBadGateway, err.Error())
		return
	}
	apiSuccess(c, gin.H{"id": container, "tail": tail, "logs": string(output)})
}

func AssetDockerLogStream(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	container := strings.TrimSpace(c.Param("container"))
	if container == "" {
		apiError(c, http.StatusBadRequest, "无效的 Docker 容器标识")
		return
	}
	tail, ok := parseDockerLogTail(c.DefaultQuery("tail", "200"))
	if !ok {
		apiError(c, http.StatusBadRequest, "日志行数必须在 1-10000 之间")
		return
	}
	flusher := setSSEHeaders(c)
	if flusher == nil {
		return
	}
	_ = writeAssetSSE(c, flusher, "status", gin.H{"state": "connecting"})
	reader, err := assetDockerClient().Logs(c.Request.Context(), host, credential, container, tail, true)
	if err != nil && c.Request.Context().Err() == nil {
		_ = writeAssetSSE(c, flusher, "log-error", gin.H{"message": err.Error()})
		return
	}
	defer reader.Close()
	buf := make([]byte, 4096)
	for {
		n, readErr := reader.Read(buf)
		if n > 0 {
			if err := writeAssetSSE(c, flusher, "log", gin.H{"data": string(buf[:n])}); err != nil {
				return
			}
		}
		if readErr != nil {
			if readErr != io.EOF && c.Request.Context().Err() == nil {
				_ = writeAssetSSE(c, flusher, "log-error", gin.H{"message": readErr.Error()})
			}
			return
		}
	}
}

func AssetDockerTerminal(c *gin.Context) {
	host, credential, ok := loadAssetDockerHost(c)
	if !ok {
		return
	}
	container := strings.TrimSpace(c.Param("container"))
	if container == "" {
		apiError(c, http.StatusBadRequest, "无效的 Docker 容器标识")
		return
	}
	ws, err := assetWSUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	defer ws.Close()

	settings := models.GetAssetSettings()
	_ = assetDockerClient().BridgeTerminal(ws, host, credential, container, services.TerminalOptions{
		IdleTimeout:  time.Duration(settings.TerminalIdleTimeoutSeconds) * time.Second,
		DefaultShell: "/bin/sh",
	})
}

func writeAssetSSE(c *gin.Context, flusher http.Flusher, event string, payload any) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	if strings.TrimSpace(event) != "" {
		if _, err := fmt.Fprintf(c.Writer, "event: %s\n", event); err != nil {
			return err
		}
	}
	if _, err := fmt.Fprintf(c.Writer, "data: %s\n\n", body); err != nil {
		return err
	}
	flusher.Flush()
	return nil
}

func GetAssetSettings(c *gin.Context) {
	apiSuccess(c, assetSettingsForResponse())
}

func UpdateAssetSettings(c *gin.Context) {
	var req models.AssetSettings
	if err := c.ShouldBindJSON(&req); err != nil {
		apiError(c, http.StatusBadRequest, "请求参数无效")
		return
	}
	req.CredentialSecret = strings.TrimSpace(req.CredentialSecret)
	if err := validateAssetCredentialSecret(req.CredentialSecret); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	oldSecret := effectiveAssetCredentialSecret()
	if err := updateAssetSettingsAndRewrapCredentials(req, oldSecret); err != nil {
		apiError(c, http.StatusBadRequest, err.Error())
		return
	}
	apiSuccess(c, assetSettingsForResponse())
}

func decryptAssetCredential(ciphertext string) (string, error) {
	return decodeAssetCredentialWithSecret(effectiveAssetCredentialSecret(), ciphertext)
}

func encodeAssetCredential(plaintext string) (string, error) {
	secret := effectiveAssetCredentialSecret()
	if secret == "" {
		return plaintext, nil
	}
	cipher, err := services.NewAssetCredentialCipher(secret)
	if err != nil {
		return "", err
	}
	return cipher.Encrypt(plaintext)
}

func decodeAssetCredentialWithSecret(secret, stored string) (string, error) {
	if secret == "" {
		return stored, nil
	}
	cipher, err := services.NewAssetCredentialCipher(secret)
	if err != nil {
		return "", err
	}
	return cipher.Decrypt(stored)
}

func encodeAssetCredentialWithSecret(secret, plaintext string) (string, error) {
	if secret == "" {
		return plaintext, nil
	}
	cipher, err := services.NewAssetCredentialCipher(secret)
	if err != nil {
		return "", err
	}
	return cipher.Encrypt(plaintext)
}

func effectiveAssetCredentialSecret() string {
	if value, ok := models.GetSettingValue("asset_credential_secret"); ok {
		return strings.TrimSpace(value)
	}
	return strings.TrimSpace(conf.App.AssetSecret)
}

func assetSettingsForResponse() models.AssetSettings {
	settings := models.GetAssetSettings()
	settings.CredentialSecret = effectiveAssetCredentialSecret()
	return settings
}

func validateAssetCredentialSecret(secret string) error {
	if secret == "" {
		return nil
	}
	if _, err := services.NewAssetCredentialCipher(secret); err != nil {
		return fmt.Errorf("凭据加密密钥无效")
	}
	return nil
}

func fillAssetSSHHostCredentials(hosts []models.AssetSSHHost) error {
	secret := effectiveAssetCredentialSecret()
	for i := range hosts {
		credential, err := decodeAssetCredentialWithSecret(secret, hosts[i].CredentialCipher)
		if err != nil {
			return err
		}
		hosts[i].Credential = credential
	}
	return nil
}

func fillAssetSSHHostCredential(host *models.AssetSSHHost) error {
	credential, err := decryptAssetCredential(host.CredentialCipher)
	if err != nil {
		return err
	}
	host.Credential = credential
	return nil
}

func fillAssetCredentials(credentials []models.AssetCredential) error {
	secret := effectiveAssetCredentialSecret()
	for i := range credentials {
		credential, err := decodeAssetCredentialWithSecret(secret, credentials[i].CredentialCipher)
		if err != nil {
			return err
		}
		credentials[i].Credential = credential
	}
	return nil
}

func fillAssetCredential(credential *models.AssetCredential) error {
	plain, err := decryptAssetCredential(credential.CredentialCipher)
	if err != nil {
		return err
	}
	credential.Credential = plain
	return nil
}

func resolveAssetSSHCredential(req assetSSHHostRequest, existingCredentialID, memberID int64, requireCredential bool) (*models.AssetCredential, error) {
	if req.CredentialID > 0 {
		cred, err := models.GetAssetCredential(req.CredentialID)
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("凭据不存在")
		}
		if err != nil {
			return nil, err
		}
		return cred, nil
	}

	if strings.TrimSpace(req.Credential) == "" {
		if existingCredentialID > 0 {
			cred, err := models.GetAssetCredential(existingCredentialID)
			if err != nil {
				return nil, err
			}
			return cred, nil
		}
		if requireCredential {
			return nil, fmt.Errorf("凭据不能为空")
		}
	}

	encrypted, err := encodeAssetCredential(req.Credential)
	if err != nil {
		return nil, err
	}
	name := req.Name + " 凭据"
	if existingCredentialID > 0 {
		cred, err := models.GetAssetCredential(existingCredentialID)
		if err != nil && err != sql.ErrNoRows {
			return nil, err
		}
		if cred != nil {
			cred.Name = name
			cred.Username = req.Username
			cred.AuthType = req.AuthType
			cred.CredentialCipher = encrypted
			cred.CredentialHint = services.CredentialHint(req.AuthType)
			if err := models.UpdateAssetCredential(cred); err != nil {
				return nil, err
			}
			return models.GetAssetCredential(existingCredentialID)
		}
	}
	id, err := models.CreateAssetCredential(&models.AssetCredential{
		Name:             name,
		Username:         req.Username,
		AuthType:         req.AuthType,
		CredentialCipher: encrypted,
		CredentialHint:   services.CredentialHint(req.AuthType),
		CreatedBy:        memberID,
	})
	if err != nil {
		return nil, err
	}
	return models.GetAssetCredential(id)
}

func updateAssetSettingsAndRewrapCredentials(settings models.AssetSettings, oldSecret string) error {
	if settings.TerminalIdleTimeoutSeconds < 1 || settings.TerminalIdleTimeoutSeconds > 86400 {
		return fmt.Errorf("terminal idle timeout out of range")
	}
	if settings.TerminalScrollbackLines == 0 {
		settings.TerminalScrollbackLines = 5000
	}
	if settings.TerminalScrollbackLines < 500 || settings.TerminalScrollbackLines > 50000 {
		return fmt.Errorf("terminal scrollback lines out of range")
	}
	newSecret := strings.TrimSpace(settings.CredentialSecret)
	tx, err := models.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if oldSecret != newSecret {
		rows, err := tx.Query("SELECT credential_id, credential_cipher FROM md_asset_credentials ORDER BY credential_id")
		if err != nil {
			return fmt.Errorf("list asset credentials: %w", err)
		}
		type credentialUpdate struct {
			credentialID int64
			value        string
		}
		updates := []credentialUpdate{}
		for rows.Next() {
			var credentialID int64
			var stored string
			if err := rows.Scan(&credentialID, &stored); err != nil {
				rows.Close()
				return err
			}
			plain, err := decodeAssetCredentialWithSecret(oldSecret, stored)
			if err != nil {
				rows.Close()
				return fmt.Errorf("解密已有资产凭据失败，请确认旧密钥正确")
			}
			rewrapped, err := encodeAssetCredentialWithSecret(newSecret, plain)
			if err != nil {
				rows.Close()
				return fmt.Errorf("重写资产凭据失败: %w", err)
			}
			updates = append(updates, credentialUpdate{credentialID: credentialID, value: rewrapped})
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return err
		}
		rows.Close()
		for _, update := range updates {
			if _, err := tx.Exec("UPDATE md_asset_credentials SET credential_cipher=?, modify_time=? WHERE credential_id=?", update.value, time.Now(), update.credentialID); err != nil {
				return fmt.Errorf("update asset credential: %w", err)
			}
		}
	}

	now := time.Now()
	settingsMap := map[string]string{
		"asset_terminal_idle_timeout_seconds": fmt.Sprintf("%d", settings.TerminalIdleTimeoutSeconds),
		"asset_terminal_scrollback_lines":     fmt.Sprintf("%d", settings.TerminalScrollbackLines),
		"asset_credential_secret":             newSecret,
	}
	for key, value := range settingsMap {
		if _, err := tx.Exec(`
			INSERT INTO md_settings (key, value, description, update_time)
			VALUES (?, ?, '', ?)
			ON CONFLICT(key) DO UPDATE SET value = excluded.value, update_time = excluded.update_time`,
			key, value, now,
		); err != nil {
			return fmt.Errorf("update setting %s: %w", key, err)
		}
	}
	return tx.Commit()
}

func normalizeAssetSSHRequest(req *assetSSHHostRequest) {
	req.Name = strings.TrimSpace(req.Name)
	req.Host = strings.TrimSpace(req.Host)
	req.Shell = strings.TrimSpace(req.Shell)
	req.Cwd = strings.TrimSpace(req.Cwd)
	req.DockerSocketPath = strings.TrimSpace(req.DockerSocketPath)
	req.Username = strings.TrimSpace(req.Username)
	req.AuthType = strings.TrimSpace(req.AuthType)
	req.Status = strings.TrimSpace(req.Status)
	if req.Port == 0 {
		req.Port = 22
	}
	if req.AuthType == "" {
		req.AuthType = models.AssetAuthPassword
	}
	if req.Shell == "" {
		req.Shell = "/bin/sh"
	}
	if req.DockerSocketPath == "" {
		req.DockerSocketPath = services.DefaultDockerSocketPath
	}
	if req.Status == "" {
		req.Status = models.AssetStatusUnknown
	}
}

func normalizeAssetCredentialRequest(req *assetCredentialRequest) {
	req.Name = strings.TrimSpace(req.Name)
	req.Username = strings.TrimSpace(req.Username)
	req.AuthType = strings.TrimSpace(req.AuthType)
	if req.AuthType == "" {
		req.AuthType = models.AssetAuthPassword
	}
}

func validateAssetSSHRequest(req assetSSHHostRequest, requireCredential bool) error {
	if req.Name == "" || req.Host == "" {
		return fmt.Errorf("名称和主机地址不能为空")
	}
	if req.Port < 1 || req.Port > 65535 {
		return fmt.Errorf("端口必须在 1-65535 之间")
	}
	if strings.ContainsAny(req.Shell, "\r\n") || strings.ContainsAny(req.Cwd, "\r\n") || strings.ContainsAny(req.DockerSocketPath, "\r\n") {
		return fmt.Errorf("Shell、工作目录和 Docker Socket 不能包含换行")
	}
	if !strings.HasPrefix(req.DockerSocketPath, "/") {
		return fmt.Errorf("Docker Socket 路径必须是绝对路径")
	}
	if req.CredentialID > 0 {
		return nil
	}
	if requireCredential && strings.TrimSpace(req.Credential) == "" {
		return fmt.Errorf("凭据不能为空")
	}
	if req.Username == "" {
		return fmt.Errorf("用户名不能为空")
	}
	if req.AuthType != models.AssetAuthPassword && req.AuthType != models.AssetAuthKey {
		return fmt.Errorf("认证方式无效")
	}
	if req.Status != models.AssetStatusUnknown && req.Status != models.AssetStatusOnline && req.Status != models.AssetStatusOffline {
		return fmt.Errorf("状态无效")
	}
	return nil
}

func validateAssetCredentialRequest(req assetCredentialRequest, requireCredential bool) error {
	if req.Name == "" || req.Username == "" {
		return fmt.Errorf("名称和用户名不能为空")
	}
	if req.AuthType != models.AssetAuthPassword && req.AuthType != models.AssetAuthKey {
		return fmt.Errorf("认证方式无效")
	}
	if requireCredential && strings.TrimSpace(req.Credential) == "" {
		return fmt.Errorf("凭据不能为空")
	}
	return nil
}

func normalizeDockerInspectStatus(status string) string {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "running":
		return "running"
	case "exited", "created", "dead", "paused", "restarting", "removing":
		return "stopped"
	default:
		return "unknown"
	}
}

func shellQuote(value string) string {
	if value == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func dockerContainerCommand(action string, container string) (string, bool) {
	quotedContainer := shellQuote(container)
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

func dockerCreateContainerCommand(req assetDockerCreateRequest) (string, bool, bool) {
	image := strings.TrimSpace(req.Image)
	if image == "" || strings.HasPrefix(image, "-") {
		return "", false, false
	}
	startAfterCreate := true
	if req.StartAfterCreate != nil {
		startAfterCreate = *req.StartAfterCreate
	}
	args := []string{"docker"}
	if startAfterCreate {
		args = append(args, "run", "-d")
	} else {
		args = append(args, "create")
	}
	if name := strings.TrimSpace(req.Name); name != "" {
		args = append(args, "--name", shellQuote(name))
	}
	if policy := strings.TrimSpace(req.RestartPolicy); policy != "" && policy != "no" {
		if !isAllowedDockerRestartPolicy(policy) {
			return "", false, false
		}
		args = append(args, "--restart", policy)
	} else if policy == "no" {
		args = append(args, "--restart", "no")
	}
	for _, port := range req.Ports {
		value, ok := dockerCreatePortArg(port)
		if !ok {
			return "", false, false
		}
		if value != "" {
			args = append(args, "-p", shellQuote(value))
		}
	}
	for _, volume := range req.Volumes {
		value, ok := dockerCreateVolumeArg(volume)
		if !ok {
			return "", false, false
		}
		if value != "" {
			args = append(args, "-v", shellQuote(value))
		}
	}
	for _, env := range req.Env {
		value, ok := dockerCreateEnvArg(env)
		if !ok {
			return "", false, false
		}
		if value != "" {
			args = append(args, "-e", shellQuote(value))
		}
	}
	if network := strings.TrimSpace(req.Network); network != "" {
		args = append(args, "--network", shellQuote(network))
	}
	if req.Privileged {
		args = append(args, "--privileged")
	}
	if memory := strings.TrimSpace(req.Memory); memory != "" {
		args = append(args, "-m", shellQuote(memory))
	}
	if cpus := strings.TrimSpace(req.CPUs); cpus != "" {
		args = append(args, "--cpus", shellQuote(cpus))
	}
	args = append(args, shellQuote(image))
	if command := strings.TrimSpace(req.Command); command != "" {
		args = append(args, shellQuote(command))
	}
	return strings.Join(args, " "), startAfterCreate, true
}

func isAllowedDockerRestartPolicy(policy string) bool {
	switch policy {
	case "no", "always", "unless-stopped", "on-failure":
		return true
	default:
		return false
	}
}

func dockerCreatePortArg(port assetDockerPortRequest) (string, bool) {
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

func dockerCreateVolumeArg(volume assetDockerVolumeRequest) (string, bool) {
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

func dockerCreateEnvArg(env assetDockerEnvRequest) (string, bool) {
	key := strings.TrimSpace(env.Key)
	if key == "" && env.Value == "" {
		return "", true
	}
	if key == "" || strings.Contains(key, "=") {
		return "", false
	}
	return key + "=" + env.Value, true
}

func parseDockerLogTail(value string) (int, bool) {
	tail, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || tail < 1 || tail > 10000 {
		return 0, false
	}
	return tail, true
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func checkAssetWSOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	return strings.EqualFold(u.Host, r.Host)
}

func loadAssetDockerHost(c *gin.Context) (*models.AssetSSHHost, string, bool) {
	id, ok := middleware.ParseID(c, "id")
	if !ok {
		apiError(c, http.StatusBadRequest, "无效的 SSH 主机 ID")
		return nil, "", false
	}
	host, err := models.GetAssetSSHHost(id)
	if err == sql.ErrNoRows {
		apiError(c, http.StatusNotFound, "SSH 主机不存在")
		return nil, "", false
	}
	if err != nil {
		apiError(c, http.StatusInternalServerError, "读取 SSH 主机失败")
		return nil, "", false
	}
	credential, err := decryptAssetCredential(host.CredentialCipher)
	if err != nil {
		apiError(c, http.StatusInternalServerError, "解密凭据失败")
		return nil, "", false
	}
	return host, credential, true
}
