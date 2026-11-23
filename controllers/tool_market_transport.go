package controllers

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"time"
)

// This transport serves marketplace protocol routes and explicitly scoped public
// static resource paths on a configured market origin. Pin resolved addresses, reject
// link-local/metadata addresses, never use a proxy or forward a redirect token.
func marketplaceHTTPClient() *http.Client {
	return &http.Client{Timeout: 2 * time.Minute, Transport: &http.Transport{Proxy: nil, DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
		host, port, err := net.SplitHostPort(address)
		if err != nil {
			return nil, err
		}
		ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
		if err != nil {
			return nil, err
		}
		if len(ips) == 0 {
			return nil, fmt.Errorf("no market address")
		}
		for _, a := range ips {
			ip := a.IP
			if ip.IsUnspecified() || ip.IsMulticast() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() || ip.String() == "100.100.100.200" {
				return nil, fmt.Errorf("invalid market address")
			}
		}
		return (&net.Dialer{Timeout: 10 * time.Second}).DialContext(ctx, network, net.JoinHostPort(ips[0].IP.String(), port))
	}}, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
}
