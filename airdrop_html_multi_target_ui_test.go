package main

import (
	"os"
	"strings"
	"testing"
)

const airdropHTMLPath = "tmp/share-1783432865442847645.html"

func readAirdropHTML(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(airdropHTMLPath)
	if err != nil {
		t.Fatalf("ReadFile(%s) error = %v", airdropHTMLPath, err)
	}
	return string(data)
}

func TestAirdropUsesExplicitMultiTargetSelection(t *testing.T) {
	html := readAirdropHTML(t)

	for _, required := range []string{
		`selectedTargetPeerIds:new Set()`,
		`function toggleTargetPeer(peerId)`,
		`aria-multiselectable="true"`,
		`id="flowSelectAllPeersBtn"`,
		`id="flowClearPeersBtn"`,
		`已选择 ${selected.length} 台设备`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("airdrop explicit multi-target UI missing %q", required)
		}
	}

	for _, forbidden := range []string{
		`selectedTargetPeerId:""`,
		`ready.length === 1 ? ready : []`,
		`state.selectedTargetPeerId = ready[0].id`,
	} {
		if strings.Contains(html, forbidden) {
			t.Fatalf("airdrop should not auto-select a single target, found %q", forbidden)
		}
	}
}

func TestAirdropCameraControlsAreInlineAndPerDevice(t *testing.T) {
	html := readAirdropHTML(t)

	for _, required := range []string{
		`id="flowMediaDock"`,
		`id="flowMediaRecipients"`,
		`id="flowStopAllMediaBtn"`,
		`id="flowMediaStopConfirm"`,
		`mediaTargetPeerIds:new Set()`,
		`mediaPeerStates:new Map()`,
		`async function addMediaTarget(peerId)`,
		`async function removeMediaTarget(peerId`,
		`async function retryMediaTarget(peerId)`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("airdrop inline media controls missing %q", required)
		}
	}

	for _, forbidden := range []string{
		`id="flowCameraSheet"`,
		`openFlowSheet("flowCameraSheet")`,
	} {
		if strings.Contains(html, forbidden) {
			t.Fatalf("airdrop camera controls should not use a modal, found %q", forbidden)
		}
	}
}

func TestAirdropMultiRecipientTransfersTrackResultsIndependently(t *testing.T) {
	html := readAirdropHTML(t)

	for _, required := range []string{
		`function createOutgoingTransfer(file, peer)`,
		`function sendTextToPeer(peer, value)`,
		`status:"发送失败"`,
		`peerId:peer.id`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("airdrop per-recipient transfer tracking missing %q", required)
		}
	}
}

func TestAirdropInvitationCopiesOneUsableLink(t *testing.T) {
	html := readAirdropHTML(t)

	for _, required := range []string{
		`id="flowCopyInviteLink"`,
		`>复制邀请链接</button>`,
		`async function copyInviteLink()`,
		`flowCopyInviteLink").disabled = !details.linkUsable`,
		`邀请链接已复制`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("airdrop invitation link behavior missing %q", required)
		}
	}

	for _, forbidden := range []string{
		`id="flowCopyInviteText"`,
		`function copyInviteText()`,
		`复制邀请文字`,
		`邀请文字已复制`,
	} {
		if strings.Contains(html, forbidden) {
			t.Fatalf("airdrop invitation should not retain text-copy action, found %q", forbidden)
		}
	}
}

func TestAirdropHasPerPeerWebRTCDiagnostics(t *testing.T) {
	html := readAirdropHTML(t)

	for _, required := range []string{
		`id="flowDiagnosticsBtn"`,
		`id="flowDiagnosticsPanel"`,
		`id="flowDiagnosticsPeerSelect"`,
		`id="flowDiagnosticsMetrics"`,
		`id="flowDiagnosticsAdvice"`,
		`id="flowDiagnosticsCopyBtn"`,
		`diagnostics:new Map()`,
		`diagnosticSamples:new Map()`,
		`async function collectPeerDiagnostics(peer)`,
		`peer.pc.getStats()`,
		`function classifyDiagnosticQuality(metrics`,
		`function renderDiagnosticsPanel()`,
		`function copyDiagnostics()`,
		`jitterBufferDelay`,
		`totalDecodeTime`,
		`availableOutgoingBitrate`,
	} {
		if !strings.Contains(html, required) {
			t.Fatalf("airdrop WebRTC diagnostics missing %q", required)
		}
	}

	if strings.Contains(html, `flow-sheet-backdrop" id="flowDiagnosticsPanel`) {
		t.Fatalf("airdrop diagnostics should be inline rather than a modal")
	}
}
