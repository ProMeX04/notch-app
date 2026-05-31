package geminilive

import (
	"testing"
)

func TestNormalizeModality(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"audio", "AUDIO"},
		{"  text  ", "TEXT"},
		{"IMAGE", "IMAGE"},
		{"invalid", ""},
		{"", ""},
	}

	for _, tt := range tests {
		got := normalizeModality(tt.input)
		if got != tt.want {
			t.Errorf("normalizeModality(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestNormalizeMediaResolution(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"media_resolution_low", "MEDIA_RESOLUTION_LOW"},
		{"  MEDIA_RESOLUTION_MEDIUM  ", "MEDIA_RESOLUTION_MEDIUM"},
		{"MEDIA_RESOLUTION_HIGH", "MEDIA_RESOLUTION_HIGH"},
		{"invalid", ""},
		{"", ""},
	}

	for _, tt := range tests {
		got := normalizeMediaResolution(tt.input)
		if got != tt.want {
			t.Errorf("normalizeMediaResolution(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestNormalizeThinkingLevel(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"minimal", "MINIMAL"},
		{"low", "LOW"},
		{"medium", "MEDIUM"},
		{"high", "HIGH"},
		{"invalid", ""},
		{"", ""},
	}

	for _, tt := range tests {
		got := normalizeThinkingLevel(tt.input)
		if got != tt.want {
			t.Errorf("normalizeThinkingLevel(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestModelUsesThinkingLevel(t *testing.T) {
	tests := []struct {
		model string
		want  bool
	}{
		{"gemini-3.5-flash", true},
		{"models/gemini-3.0-ultra", true},
		{"gemini-2.5-flash", false},
		{"gemini-2.0-flash-exp", false},
	}

	for _, tt := range tests {
		got := modelUsesThinkingLevel(tt.model)
		if got != tt.want {
			t.Errorf("modelUsesThinkingLevel(%q) = %t, want %t", tt.model, got, tt.want)
		}
	}
}

func TestBuildGeminiLiveConnectConfig(t *testing.T) {
	// 1. Test standard Gemini 2.0/2.5 model (uses thinking budget)
	voice := "Puck"
	sysInst := "Act like a helper"
	budget := 1024
	mediaRes := "media_resolution_high"

	req := GeminiLiveSessionTokenRequest{
		Model:              "gemini-2.5-flash",
		VoiceName:          &voice,
		SystemInstruction:  &sysInst,
		ThinkingBudget:     &budget,
		MediaResolution:    &mediaRes,
		ResponseModalities: []string{"audio", "text"},
	}

	config, modalities, resolvedMediaRes := buildGeminiLiveConnectConfig(req, "gemini-2.5-flash")

	if len(modalities) != 2 || modalities[0] != "AUDIO" || modalities[1] != "TEXT" {
		t.Errorf("expected [AUDIO, TEXT] modalities, got %v", modalities)
	}

	if resolvedMediaRes != "MEDIA_RESOLUTION_HIGH" {
		t.Errorf("expected MEDIA_RESOLUTION_HIGH, got %q", resolvedMediaRes)
	}

	if config.SpeechConfig == nil || config.SpeechConfig.VoiceConfig.PrebuiltVoiceConfig.VoiceName != "Puck" {
		t.Errorf("unexpected voice name config: %+v", config.SpeechConfig)
	}

	if config.SystemInstruction == nil || len(config.SystemInstruction.Parts) != 1 || config.SystemInstruction.Parts[0].Text != "Act like a helper" {
		t.Errorf("unexpected system instruction: %+v", config.SystemInstruction)
	}

	if config.ThinkingConfig == nil || config.ThinkingConfig.ThinkingBudget != 1024 || config.ThinkingConfig.ThinkingLevel != "" {
		t.Errorf("unexpected thinking config for gemini-2.5: %+v", config.ThinkingConfig)
	}

	// 2. Test Gemini 3.0 model (uses thinking level)
	level := "high"
	req3 := GeminiLiveSessionTokenRequest{
		Model:              "gemini-3.0-flash",
		ThinkingLevel:      &level,
		ThinkingBudget:     &budget, // should be ignored
		ResponseModalities: []string{},
	}

	config3, modalities3, _ := buildGeminiLiveConnectConfig(req3, "gemini-3.0-flash")

	if len(modalities3) != 1 || modalities3[0] != "AUDIO" {
		t.Errorf("expected default AUDIO modality, got %v", modalities3)
	}

	if config3.ThinkingConfig == nil || config3.ThinkingConfig.ThinkingLevel != "HIGH" || config3.ThinkingConfig.ThinkingBudget != 0 {
		t.Errorf("unexpected thinking config for gemini-3.0: %+v", config3.ThinkingConfig)
	}
}
