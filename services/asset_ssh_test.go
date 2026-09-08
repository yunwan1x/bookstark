package services

import "testing"

func TestParseDockerInspectStatus(t *testing.T) {
	raw := `[{"Config":{"Image":"nginx:1.27-alpine"},"State":{"Status":"running"}}]`
	status, image, err := ParseDockerInspectStatus(raw)
	if err != nil {
		t.Fatalf("ParseDockerInspectStatus() error = %v", err)
	}
	if status != "running" || image != "nginx:1.27-alpine" {
		t.Fatalf("status=%q image=%q", status, image)
	}
}

func TestParseDockerInspectStatusRejectsEmpty(t *testing.T) {
	if _, _, err := ParseDockerInspectStatus(`[]`); err == nil {
		t.Fatal("ParseDockerInspectStatus([]) error = nil, want error")
	}
}

func TestParseDockerInspectStatusRejectsInvalidJSON(t *testing.T) {
	if _, _, err := ParseDockerInspectStatus(`not-json`); err == nil {
		t.Fatal("ParseDockerInspectStatus(invalid) error = nil, want error")
	}
}

func TestParseDockerInspect(t *testing.T) {
	raw := `[{
		"Id":"8f3d2f1a7b4c",
		"Name":"/nginx-edge",
		"Created":"2026-05-20T09:30:00Z",
		"Config":{"Hostname":"8f3d2f1a7b4c","Image":"nginx:1.27-alpine","Cmd":["nginx","-g","daemon off;"]},
		"State":{"Status":"running","Running":true,"ExitCode":0,"StartedAt":"2026-05-20T09:31:00Z","FinishedAt":"0001-01-01T00:00:00Z"},
		"HostConfig":{"RestartPolicy":{"Name":"unless-stopped"}},
		"NetworkSettings":{"IPAddress":"172.17.0.2"}
	}]`
	info, err := ParseDockerInspect(raw)
	if err != nil {
		t.Fatalf("ParseDockerInspect() error = %v", err)
	}
	if info.Name != "nginx-edge" || info.Image != "nginx:1.27-alpine" || !info.Running {
		t.Fatalf("inspect info = %#v", info)
	}
	if info.RestartPolicy != "unless-stopped" || info.IPAddress != "172.17.0.2" {
		t.Fatalf("inspect network/restart = %#v", info)
	}
	if len(info.Command) != 3 || info.Command[0] != "nginx" {
		t.Fatalf("command = %#v", info.Command)
	}
}

func TestParseDockerInspectUsesNetworkMapIP(t *testing.T) {
	raw := `[{
		"Id":"8f3d2f1a7b4c",
		"Name":"/nginx-edge",
		"Config":{"Hostname":"8f3d2f1a7b4c","Image":"nginx:1.27-alpine","Cmd":["nginx","-g","daemon off;"]},
		"State":{"Status":"running","Running":true,"ExitCode":0},
		"HostConfig":{"RestartPolicy":{"Name":"unless-stopped"}},
		"NetworkSettings":{
			"IPAddress":"",
			"Networks":{
				"app_net":{"IPAddress":"172.19.0.4"},
				"bridge":{"IPAddress":"172.17.0.2"}
			}
		}
	}]`
	info, err := ParseDockerInspect(raw)
	if err != nil {
		t.Fatalf("ParseDockerInspect() error = %v", err)
	}
	if info.IPAddress != "172.19.0.4, 172.17.0.2" {
		t.Fatalf("ip_address = %q", info.IPAddress)
	}
}

func TestParseDockerPS(t *testing.T) {
	raw := "{\"ID\":\"8f3d2f1a7b4c\",\"Image\":\"nginx:1.27-alpine\",\"Command\":\"nginx -g 'daemon off;'\",\"Names\":\"nginx-edge\",\"Ports\":\"0.0.0.0:80->80/tcp\",\"State\":\"running\",\"Status\":\"Up 2 hours\"}\n" +
		"{\"ID\":\"4ab21ce08c77\",\"Image\":\"redis:7\",\"Command\":\"docker-entrypoint.sh redis-server\",\"Names\":\"redis-cache\",\"Ports\":\"\",\"State\":\"exited\",\"Status\":\"Exited (0) 3 minutes ago\"}\n"
	containers, err := ParseDockerPS(raw)
	if err != nil {
		t.Fatalf("ParseDockerPS() error = %v", err)
	}
	if len(containers) != 2 {
		t.Fatalf("len(containers) = %d, want 2", len(containers))
	}
	if containers[0].ID != "8f3d2f1a7b4c" || containers[0].Name != "nginx-edge" {
		t.Fatalf("first container = %#v", containers[0])
	}
	if containers[1].State != "exited" || containers[1].Image != "redis:7" || containers[1].Command != "docker-entrypoint.sh redis-server" {
		t.Fatalf("second container = %#v", containers[1])
	}
	if len(containers[0].PortsDetail) != 1 {
		t.Fatalf("ports detail = %#v", containers[0].PortsDetail)
	}
	port := containers[0].PortsDetail[0]
	if !port.Published || port.HostIP != "0.0.0.0" || port.HostPort != "80" || port.ContainerPort != "80" || port.Protocol != "tcp" {
		t.Fatalf("parsed port = %#v", port)
	}
	if len(containers[1].PortsDetail) != 0 {
		t.Fatalf("empty ports detail = %#v", containers[1].PortsDetail)
	}
}

func TestParseDockerPorts(t *testing.T) {
	ports := ParseDockerPorts("0.0.0.0:8080->80/tcp, :::443->443/tcp, 6379/tcp, unknown-format")
	if len(ports) != 4 {
		t.Fatalf("len(ports) = %d, want 4: %#v", len(ports), ports)
	}
	if ports[0].HostIP != "0.0.0.0" || ports[0].HostPort != "8080" || ports[0].ContainerPort != "80" || ports[0].Protocol != "tcp" || !ports[0].Published {
		t.Fatalf("first port = %#v", ports[0])
	}
	if ports[1].HostIP != "::" || ports[1].HostPort != "443" || ports[1].ContainerPort != "443" || ports[1].Protocol != "tcp" || !ports[1].Published {
		t.Fatalf("second port = %#v", ports[1])
	}
	if ports[2].Published || ports[2].ContainerPort != "6379" || ports[2].Protocol != "tcp" {
		t.Fatalf("third port = %#v", ports[2])
	}
	if ports[3].Published || ports[3].Raw != "unknown-format" || ports[3].ContainerPort != "unknown-format" {
		t.Fatalf("raw fallback port = %#v", ports[3])
	}
}

func TestParseDockerNetworks(t *testing.T) {
	networks := ParseDockerNetworks("{\"Name\":\"bridge\",\"Driver\":\"bridge\",\"Scope\":\"local\"}\n" +
		"{\"Name\":\"host\",\"Driver\":\"host\",\"Scope\":\"local\"}\n" +
		"{\"Name\":\"custom_net\",\"Driver\":\"bridge\",\"Scope\":\"local\"}\n" +
		"{\"Name\":\"\",\"Driver\":\"bridge\",\"Scope\":\"local\"}\n" +
		"not-json\n")
	if len(networks) != 3 {
		t.Fatalf("len(networks) = %d, want 3: %#v", len(networks), networks)
	}
	if networks[0].Name != "bridge" || networks[0].Driver != "bridge" || networks[0].Scope != "local" {
		t.Fatalf("first network = %#v", networks[0])
	}
	if networks[2].Name != "custom_net" {
		t.Fatalf("third network = %#v", networks[2])
	}
}

func TestParseDockerPSRejectsInvalidJSONLine(t *testing.T) {
	if _, err := ParseDockerPS("{bad-json}\n"); err == nil {
		t.Fatal("ParseDockerPS(invalid) error = nil, want error")
	}
}
