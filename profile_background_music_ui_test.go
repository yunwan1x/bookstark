package main

import (
	"os"
	"strings"
	"testing"
)

func TestBackgroundMusicIsProfileControlledAndGlobal(t *testing.T) {
	profile, err := os.ReadFile("templates/profile.html")
	if err != nil {
		t.Fatalf("ReadFile(profile.html) error = %v", err)
	}
	profileText := string(profile)
	for _, required := range []string{
		`id="background-music-toggle"`,
		`id="background-music-volume"`,
		`id="background-music-volume-value"`,
		`profile.field.background_music`,
		`profile.field.background_music_hint`,
		`profile.field.background_music_volume`,
		`window.BookStarkMusic.set(enabled)`,
		`window.BookStarkMusic.setVolume(value / 100)`,
		`window.BookStarkMusic.syncControl('background-music-toggle')`,
		`window.BookStarkMusic.syncVolumeControl('background-music-volume')`,
	} {
		if !strings.Contains(profileText, required) {
			t.Fatalf("profile background music control missing %q", required)
		}
	}

	js, err := os.ReadFile("static/js/theme.js")
	if err != nil {
		t.Fatalf("ReadFile(theme.js) error = %v", err)
	}
	jsText := string(js)
	for _, required := range []string{
		`MUSIC_STORAGE_KEY = 'bookstark-background-music'`,
		`MUSIC_VOLUME_STORAGE_KEY = 'bookstark-background-music-volume'`,
		`window.BookStarkMusic`,
		`AudioContext || window.webkitAudioContext`,
		`createOscillator`,
		`createGain`,
		`setInterval(scheduleCanonMidiMusic`,
		`master.gain.setValueAtTime(0.0001`,
		`CANON_MIDI_NOTE_EVENTS`,
		`scheduleCanonPianoNote`,
		`oscillator.type = 'sine'`,
		`oscillator.type = 'triangle'`,
		`stopBackgroundMusic`,
		`getMusicVolume`,
		`setBackgroundMusicVolume`,
		`applyBackgroundMusicVolume`,
		`syncMusicVolumeControl`,
		`syncMusicControl`,
		`getCanonMusicInfo`,
		`getInfo: getCanonMusicInfo`,
		`bindMusicResumeGesture`,
		`document.addEventListener('pointerdown', resumeBackgroundMusicOnGesture`,
		`document.addEventListener('keydown', resumeBackgroundMusicOnGesture`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("background music runtime missing %q", required)
		}
	}
}

func TestBackgroundMusicUsesCanonMidiNotes(t *testing.T) {
	js, err := os.ReadFile("static/js/theme.js")
	if err != nil {
		t.Fatalf("ReadFile(theme.js) error = %v", err)
	}
	text := string(js)

	for _, required := range []string{
		`MUSIC_MASTER_GAIN = 1`,
		`MUSIC_OUTPUT_GAIN_CAP = 1`,
		`MUSIC_DEFAULT_VOLUME = 0.35`,
		`MUSIC_PIANO_GAIN = 0.11`,
		`midiToFrequency`,
		`return MUSIC_MASTER_GAIN * MUSIC_OUTPUT_GAIN_CAP * getMusicVolume()`,
		`CANON_MIDI_SOURCE`,
		`CANON_MIDI_SECONDS`,
		`CANON_MIDI_NOTE_EVENTS`,
		`CANON_MIDI_NOTE_COUNT`,
		`getEffectiveMusicMasterGain`,
		`exponentialRampToValueAtTime(getEffectiveMusicMasterGain()`,
		`scheduleCanonPianoNote(cycleStart + event[0]`,
		`scheduleCanonMidiMusic`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("background music should use Mutopia Canon MIDI note material %q", required)
		}
	}

	for _, removed := range []string{
		`CANON_CHORD_PROGRESSION`,
		`canonPattern`,
	} {
		if strings.Contains(text, removed) {
			t.Fatalf("background music should not use hand-written Canon template %q", removed)
		}
	}
}

func TestBackgroundMusicUsesFullFourHandsPianoCanonMidiNotes(t *testing.T) {
	js, err := os.ReadFile("static/js/theme.js")
	if err != nil {
		t.Fatalf("ReadFile(theme.js) error = %v", err)
	}
	text := string(js)

	for _, required := range []string{
		`CANON_MIDI_SOURCE = 'Pachelbel Canon in D four-hands piano MIDI programmed by Randy Wilson`,
		`PACHELBEL\'S CANON IN D (FOR FOUR HANDS)`,
		`CANON_MIDI_SECONDS = 237`,
		`CANON_MIDI_NOTE_COUNT = 2571`,
		`[0,50,1.0379,117]`,
		`[16.6062,74,1.0379,117]`,
		`[232.4917,74,4.1516,127]`,
		`event[3] / 127`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("background music should use full four-hands piano Canon MIDI material %q", required)
		}
	}

	for _, removed := range []string{
		`MUTOPIA_CANON_MIDI_SOURCE`,
		`CANON_MIDI_SECONDS = 176`,
		`[0,74,2,127]`,
	} {
		if strings.Contains(text, removed) {
			t.Fatalf("background music should not keep the shortened Canon MIDI material %q", removed)
		}
	}
}

func TestBackgroundMusicIsLocalized(t *testing.T) {
	for _, tc := range []struct {
		path     string
		required []string
	}{
		{
			path: "i18n/zh.go",
			required: []string{
				`"profile.field.background_music":`,
				`"背景音乐"`,
				`"profile.field.background_music_hint":`,
				`"播放卡农 MIDI 钢琴背景音乐"`,
				`"profile.field.background_music_volume":`,
				`"音量"`,
			},
		},
		{
			path: "i18n/en.go",
			required: []string{
				`"profile.field.background_music":`,
				`"Background music"`,
				`"profile.field.background_music_hint":`,
				`"Play Canon MIDI piano background music"`,
				`"profile.field.background_music_volume":`,
				`"Volume"`,
			},
		},
	} {
		data, err := os.ReadFile(tc.path)
		if err != nil {
			t.Fatalf("ReadFile(%s) error = %v", tc.path, err)
		}
		text := string(data)
		for _, required := range tc.required {
			if !strings.Contains(text, required) {
				t.Fatalf("%s missing background music localization %q", tc.path, required)
			}
		}
	}
}
