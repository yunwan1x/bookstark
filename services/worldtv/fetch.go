package worldtv

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

func publicIP(ip net.IP) bool {
	return ip.IsGlobalUnicast() && !ip.IsPrivate() && !ip.IsLoopback() && !ip.IsLinkLocalUnicast() && !ip.IsUnspecified() && !(ip.To4() != nil && ip.To4()[0] == 0) && !sharedRange.Contains(ip)
}

var _, sharedRange, _ = net.ParseCIDR("100.64.0.0/10")

func ValidateSource(raw string) error {
	u, e := url.Parse(raw)
	if e != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || u.Fragment != "" || len(raw) > 4096 || strings.ContainsAny(raw, "\r\n\t\\ ") {
		return errors.New("订阅地址须为不含账号密码的公网 HTTPS 地址")
	}
	if ip := net.ParseIP(u.Hostname()); ip != nil && !publicIP(ip) {
		return errors.New("订阅地址不能指向内网")
	}
	if strings.EqualFold(u.Hostname(), "localhost") {
		return errors.New("订阅地址不能指向本机")
	}
	return nil
}

// Resolve and pin public IPs at dial time; redirects go through the same checks.
// No environment proxy: the connection must use the IPs verified here.
func NewHTTPClient() *http.Client {
	transport := &http.Transport{TLSHandshakeTimeout: 10 * time.Second, ResponseHeaderTimeout: 20 * time.Second, IdleConnTimeout: 30 * time.Second,
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			host, port, e := net.SplitHostPort(address)
			if e != nil {
				return nil, e
			}
			ips, e := net.DefaultResolver.LookupIPAddr(ctx, host)
			if e != nil {
				return nil, errors.New("订阅域名解析失败")
			}
			if len(ips) == 0 {
				return nil, errors.New("订阅域名没有可用地址")
			}
			for _, ip := range ips {
				if !publicIP(ip.IP) {
					return nil, errors.New("订阅地址解析到了非公网地址")
				}
			}
			d := net.Dialer{Timeout: 10 * time.Second}
			for _, ip := range ips {
				conn, err := d.DialContext(ctx, network, net.JoinHostPort(ip.IP.String(), port))
				if err == nil {
					return conn, nil
				}
				e = err
			}
			return nil, e
		}}
	return &http.Client{Transport: transport, Timeout: 60 * time.Second, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 5 {
			return errors.New("订阅重定向次数过多")
		}
		return ValidateSource(req.URL.String())
	}}
}
