//go:build wails

package main

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"net/http"
)

type clientRequest struct {
	BridgeToken string `json:"bridgeToken"`
	Operation   string `json:"operation"`
	Origin      string `json:"origin"`
	Ask         bool   `json:"ask"`
	Account     string `json:"account"`
	Password    string `json:"password"`
}

func (l *launcher) clientAction(request clientRequest) (any, error) {
	if !l.allowedClientOrigin(request.Origin) {
		return nil, errors.New("untrusted workspace")
	}
	l.settingsMu.Lock()
	if l.bridgeTokens == nil {
		l.bridgeTokens = map[string]string{}
	}
	if request.Operation == "info" && l.bridgeTokens[request.Origin] == "" {
		l.bridgeTokens[request.Origin] = rand.Text()
	}
	bridgeToken := l.bridgeTokens[request.Origin]
	l.settingsMu.Unlock()
	if request.Operation != "info" && (bridgeToken == "" || request.BridgeToken != bridgeToken) {
		return nil, errors.New("client handshake required")
	}
	switch request.Operation {
	case "info":
		p, err := l.preferences()
		return map[string]any{"ask": p.Ask, "last": p.Last, "remote": p.Remote, "local": request.Origin == "http://"+l.addr, "bridgeToken": bridgeToken}, err
	case "switch":
		return true, nil
	case "save":
		l.settingsMu.Lock()
		defer l.settingsMu.Unlock()
		p, err := l.preferences()
		if err != nil {
			return nil, err
		}
		p.Ask = request.Ask
		return true, l.savePreferences(p)
	case "credentials-load":
		return l.credential(request.Origin, nil, false)
	case "credentials-clear":
		return l.credential(request.Origin, nil, true)
	case "credentials-save":
		_, err := l.credential(request.Origin, &savedCredential{Account: request.Account, Password: request.Password}, false)
		return true, err
	default:
		return nil, errors.New("unsupported client operation")
	}
}

func (l *launcher) serveClient(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	var request clientRequest
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&request) != nil {
		http.Error(w, "invalid request", 400)
		return
	}
	result, err := l.clientAction(request)
	if err != nil {
		http.Error(w, "Client settings request failed", 400)
		return
	}
	json.NewEncoder(w).Encode(result)
}
