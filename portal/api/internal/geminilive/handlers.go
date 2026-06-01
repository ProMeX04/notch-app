package geminilive

import (
	"bytes"
	"encoding/json"
	"net"
	"net/http"
	"strings"
	"time"

	"notch/portal/api/internal/auth"
	"notch/portal/api/internal/capabilities"
	"notch/portal/api/internal/events"
	"notch/portal/api/internal/httpjson"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Handler struct {
	DB         *pgxpool.Pool
	Logger     *events.Logger
	APIKey     string
	HTTPClient *http.Client
}

func NewHandler(db *pgxpool.Pool, logger *events.Logger, apiKey string) *Handler {
	transport := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   5 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		MaxIdleConns:          100,
		MaxIdleConnsPerHost:   100,
		IdleConnTimeout:       15 * time.Second,
		TLSHandshakeTimeout:   5 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
	}

	return &Handler{
		DB:     db,
		Logger: logger,
		APIKey: apiKey,
		HTTPClient: &http.Client{
			Transport: transport,
			Timeout:   10 * time.Second,
		},
	}
}

func (h *Handler) GetModels(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	authCtx, _ := ctx.Value(auth.AuthContextKey).(*auth.AuthContext)
	if authCtx == nil {
		h.logAppEvent(r, "gemini_live.models_rejected", "rejected", http.StatusUnauthorized, map[string]any{"reason": "invalid_session"})
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}

	repo := capabilities.NewPgxRepository(h.DB)
	policy, err := capabilities.GetRemotePermissionPolicy(ctx, repo)
	requirement := "pro"
	if err == nil && policy != nil {
		if reqVal, ok := policy.Features["talk_connection"]; ok {
			requirement = string(reqVal)
		}
	}

	if requirement == "disabled" {
		h.logAppEvent(r, "gemini_live.models_rejected", "rejected", http.StatusForbidden, map[string]any{"reason": "feature_disabled"})
		httpjson.Detail(w, http.StatusForbidden, "This feature is currently disabled.")
		return
	}
	if requirement == "pro" && !authCtx.User.IsPro {
		h.logAppEvent(r, "gemini_live.models_rejected", "rejected", http.StatusForbidden, map[string]any{"reason": "pro_required"})
		httpjson.Detail(w, http.StatusForbidden, "Notch Pro is required to list Gemini Live models.")
		return
	}

	models, err := ListAllowedGeminiLiveModels(ctx, h.DB)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to list allowed models")
		return
	}

	h.logAppEvent(r, "gemini_live.models_requested", "success", http.StatusOK, map[string]any{
		"modelCount":  len(models),
		"requirement": requirement,
	})

	httpjson.JSON(w, http.StatusOK, map[string]any{
		"models": models,
	})
}

func (h *Handler) GetHealth(w http.ResponseWriter, r *http.Request) {
	httpjson.JSON(w, http.StatusOK, map[string]any{
		"ok":         true,
		"apiVersion": "1",
		"mode":       "portal",
		"auth":       "bearer",
	})
}

type GeminiLiveSessionTokenRequest struct {
	Model              string   `json:"model"`
	SystemInstruction  *string  `json:"system_instruction"`
	VoiceName          *string  `json:"voice_name"`
	ThinkingLevel      *string  `json:"thinking_level"`
	ThinkingBudget     *int     `json:"thinking_budget"`
	MediaResolution    *string  `json:"media_resolution"`
	ResponseModalities []string `json:"response_modalities"`
}

type GoogleVoiceConfig struct {
	VoiceName string `json:"voiceName"`
}

type GooglePrebuiltVoiceConfig struct {
	PrebuiltVoiceConfig GoogleVoiceConfig `json:"prebuiltVoiceConfig"`
}

type GoogleSpeechConfig struct {
	VoiceConfig GooglePrebuiltVoiceConfig `json:"voiceConfig"`
}

type GooglePart struct {
	Text string `json:"text"`
}

type GoogleSystemInstruction struct {
	Parts []GooglePart `json:"parts"`
}

type GoogleThinkingConfig struct {
	ThinkingLevel  string `json:"thinkingLevel,omitempty"`
	ThinkingBudget int    `json:"thinkingBudget,omitempty"`
}

type GoogleLiveConfig struct {
	ResponseModalities []string                 `json:"responseModalities"`
	SpeechConfig       *GoogleSpeechConfig      `json:"speechConfig,omitempty"`
	SystemInstruction  *GoogleSystemInstruction `json:"systemInstruction,omitempty"`
	ThinkingConfig     *GoogleThinkingConfig    `json:"thinkingConfig,omitempty"`
	MediaResolution    string                   `json:"mediaResolution,omitempty"`
}

type GoogleGenerationConfig struct {
	ResponseModalities []string                 `json:"responseModalities"`
	SpeechConfig       *GoogleSpeechConfig      `json:"speechConfig,omitempty"`
	ThinkingConfig     *GoogleThinkingConfig    `json:"thinkingConfig,omitempty"`
	MediaResolution    string                   `json:"mediaResolution,omitempty"`
}

type GoogleBidiGenerateContentSetup struct {
	Model             string                   `json:"model"`
	GenerationConfig  GoogleGenerationConfig   `json:"generationConfig"`
	SystemInstruction *GoogleSystemInstruction `json:"systemInstruction,omitempty"`
}

type GoogleCreateTokenRequest struct {
	ExpireTime               string                         `json:"expireTime,omitempty"`
	NewSessionExpireTime     string                         `json:"newSessionExpireTime,omitempty"`
	Uses                     int                            `json:"uses,omitempty"`
	BidiGenerateContentSetup GoogleBidiGenerateContentSetup `json:"bidiGenerateContentSetup"`
	FieldMask                string                         `json:"fieldMask,omitempty"`
}

type GoogleCreateTokenResponse struct {
	Name string `json:"name"`
}

func (h *Handler) CreateSessionToken(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	authCtx, _ := ctx.Value(auth.AuthContextKey).(*auth.AuthContext)
	if authCtx == nil {
		h.logAppEvent(r, "gemini_live.session_token_rejected", "rejected", http.StatusUnauthorized, map[string]any{"reason": "invalid_session"})
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}

	repo := capabilities.NewPgxRepository(h.DB)
	policy, err := capabilities.GetRemotePermissionPolicy(ctx, repo)
	requirement := "pro"
	if err == nil && policy != nil {
		if reqVal, ok := policy.Features["talk_connection"]; ok {
			requirement = string(reqVal)
		}
	}

	if requirement == "disabled" {
		h.logAppEvent(r, "gemini_live.session_token_rejected", "rejected", http.StatusForbidden, map[string]any{"reason": "feature_disabled"})
		httpjson.Detail(w, http.StatusForbidden, "This feature is currently disabled.")
		return
	}
	if requirement == "pro" && !authCtx.User.IsPro {
		h.logAppEvent(r, "gemini_live.session_token_rejected", "rejected", http.StatusForbidden, map[string]any{"reason": "pro_required"})
		httpjson.Detail(w, http.StatusForbidden, "Notch Pro is required to create a Gemini Live session token.")
		return
	}

	var body GeminiLiveSessionTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		h.logAppEvent(r, "gemini_live.session_token_failed", "failure", http.StatusBadRequest, map[string]any{"errorName": "InvalidJSON"})
		httpjson.Detail(w, http.StatusBadRequest, "Invalid request payload.")
		return
	}

	modelStr := strings.TrimSpace(body.Model)
	if modelStr == "" {
		h.logAppEvent(r, "gemini_live.session_token_rejected", "rejected", http.StatusBadRequest, map[string]any{"reason": "missing_model"})
		httpjson.Detail(w, http.StatusBadRequest, "Model is required.")
		return
	}

	allowedModel, err := ResolveAllowedModel(ctx, h.DB, modelStr)
	if err != nil || allowedModel == nil {
		h.logAppEvent(r, "gemini_live.session_token_rejected", "rejected", http.StatusBadRequest, map[string]any{"reason": "model_not_allowed"})
		httpjson.Detail(w, http.StatusBadRequest, "Model is not allowed by this Gemini Live server.")
		return
	}

	resolvedModelID := allowedModel.ID
	now := time.Now()
	expireTime := now.Add(30 * time.Minute).UTC().Format(time.RFC3339)
	newSessionExpireTime := now.Add(1 * time.Minute).UTC().Format(time.RFC3339)
	uses := 1

	liveConfig, responseModalities, mediaRes := buildGeminiLiveConnectConfig(body, resolvedModelID)

	hasThinkingLevel := false
	hasThinkingBudget := false
	if modelUsesThinkingLevel(resolvedModelID) {
		hasThinkingLevel = body.ThinkingLevel != nil
	} else {
		hasThinkingBudget = body.ThinkingBudget != nil
	}

	hasVoice := false
	if body.VoiceName != nil && strings.TrimSpace(*body.VoiceName) != "" {
		hasVoice = true
	}

	h.logAppEvent(r, "gemini_live.session_token_requested", "success", http.StatusOK, map[string]any{
		"model":              resolvedModelID,
		"responseModalities": responseModalities,
		"modalityCount":      len(responseModalities),
		"hasVoice":           hasVoice,
		"hasThinkingLevel":   hasThinkingLevel,
		"hasThinkingBudget":  hasThinkingBudget,
		"mediaResolution":    mediaRes,
		"requirement":        requirement,
	})

	var maskParts []string
	maskParts = append(maskParts, "model")
	if len(responseModalities) > 0 {
		maskParts = append(maskParts, "generationConfig.responseModalities")
	}
	if mediaRes != "" {
		maskParts = append(maskParts, "generationConfig.mediaResolution")
	}
	if hasVoice {
		maskParts = append(maskParts, "generationConfig.speechConfig")
	}
	if hasThinkingLevel || hasThinkingBudget {
		maskParts = append(maskParts, "generationConfig.thinkingConfig")
	}
	if body.SystemInstruction != nil && strings.TrimSpace(*body.SystemInstruction) != "" {
		maskParts = append(maskParts, "systemInstruction.parts")
	}
	fieldMask := strings.Join(maskParts, ",")

	googleReq := GoogleCreateTokenRequest{
		ExpireTime:           expireTime,
		NewSessionExpireTime: newSessionExpireTime,
		Uses:                 uses,
		BidiGenerateContentSetup: GoogleBidiGenerateContentSetup{
			Model: allowedModel.Name,
			GenerationConfig: GoogleGenerationConfig{
				ResponseModalities: responseModalities,
				SpeechConfig:       liveConfig.SpeechConfig,
				ThinkingConfig:     liveConfig.ThinkingConfig,
				MediaResolution:    mediaRes,
			},
			SystemInstruction: liveConfig.SystemInstruction,
		},
		FieldMask: fieldMask,
	}

	reqBytes, err := json.Marshal(googleReq)
	if err != nil {
		h.logAppEvent(r, "gemini_live.session_token_failed", "failure", http.StatusInternalServerError, map[string]any{"errorName": "MarshalError"})
		httpjson.Detail(w, http.StatusInternalServerError, "Internal server error.")
		return
	}

	if h.APIKey == "" {
		h.logAppEvent(r, "gemini_live.session_token_failed", "failure", http.StatusInternalServerError, map[string]any{"errorName": "MissingAPIKey"})
		httpjson.Detail(w, http.StatusInternalServerError, "GEMINI_API_KEY is not configured on the server.")
		return
	}

	googleURL := "https://generativelanguage.googleapis.com/v1alpha/auth_tokens?key=" + h.APIKey
	httpReq, err := http.NewRequestWithContext(ctx, "POST", googleURL, bytes.NewBuffer(reqBytes))
	if err != nil {
		h.logAppEvent(r, "gemini_live.session_token_failed", "failure", http.StatusInternalServerError, map[string]any{"errorName": "RequestCreationError"})
		httpjson.Detail(w, http.StatusInternalServerError, "Internal server error.")
		return
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("x-goog-api-key", h.APIKey)

	client := h.HTTPClient
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(httpReq)
	if err != nil {
		h.logAppEvent(r, "gemini_live.session_token_failed", "failure", http.StatusInternalServerError, map[string]any{"errorName": "HTTPCallError"})
		httpjson.Detail(w, http.StatusInternalServerError, "Failed to connect to Google API.")
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errPayload struct {
			Error struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&errPayload)
		msg := errPayload.Error.Message
		if msg == "" {
			msg = "Failed to generate session token from Google."
		}
		h.logAppEvent(r, "gemini_live.session_token_failed", "failure", http.StatusInternalServerError, map[string]any{"errorName": "GoogleErrorResponse", "statusCode": resp.StatusCode})
		httpjson.Detail(w, http.StatusInternalServerError, msg)
		return
	}

	var googleResp GoogleCreateTokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&googleResp); err != nil {
		h.logAppEvent(r, "gemini_live.session_token_failed", "failure", http.StatusInternalServerError, map[string]any{"errorName": "DecodeError"})
		httpjson.Detail(w, http.StatusInternalServerError, "Internal server error.")
		return
	}

	httpjson.JSON(w, http.StatusOK, map[string]any{
		"name":                    googleResp.Name,
		"expire_time":             expireTime,
		"new_session_expire_time": newSessionExpireTime,
		"uses":                    uses,
	})
}

func (h *Handler) AdminGetModels(w http.ResponseWriter, r *http.Request) {
	configs, err := ListGeminiLiveModelAdminConfigs(r.Context(), h.DB)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch Gemini Live models")
		return
	}
	httpjson.JSON(w, http.StatusOK, configs)
}

func (h *Handler) AdminPostModels(w http.ResponseWriter, r *http.Request) {
	var body map[string]any
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	actionVal, hasAction := body["action"]
	if hasAction {
		action, ok := actionVal.(string)
		if ok {
			if action == "restore_defaults" {
				res, err := RestoreDefaultGeminiLiveModelAdminConfigs(r.Context(), h.DB)
				if err != nil {
					httpjson.Error(w, http.StatusInternalServerError, "Failed to restore defaults")
					return
				}
				httpjson.JSON(w, http.StatusOK, res)
				return
			}
			if action == "sync_google" {
				res, err := SyncGeminiLiveModelsFromGoogle(r.Context(), h.DB, h.APIKey)
				if err != nil {
					httpjson.Error(w, http.StatusInternalServerError, err.Error())
					return
				}
				httpjson.JSON(w, http.StatusOK, res)
				return
			}
		}
	}

	modelId, _ := body["modelId"].(string)
	displayName, _ := body["displayName"].(string)
	isEnabled, _ := body["isEnabled"].(bool)
	sortOrderVal, hasSortOrder := body["sortOrder"]

	sortOrder := 0
	if hasSortOrder {
		if fVal, ok := sortOrderVal.(float64); ok {
			sortOrder = int(fVal)
		} else if iVal, ok := sortOrderVal.(int); ok {
			sortOrder = iVal
		}
	}

	if modelId == "" {
		httpjson.Error(w, http.StatusBadRequest, "Model ID is required")
		return
	}

	cfg, err := UpsertGeminiLiveModelAdminConfig(r.Context(), h.DB, modelId, displayName, isEnabled, sortOrder)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to update Gemini Live model")
		return
	}

	httpjson.JSON(w, http.StatusOK, cfg)
}

func (h *Handler) AdminDeleteModel(w http.ResponseWriter, r *http.Request) {
	modelId := r.URL.Query().Get("modelId")
	if modelId == "" {
		httpjson.Error(w, http.StatusBadRequest, "Model ID is required")
		return
	}

	err := DeleteGeminiLiveModelAdminConfig(r.Context(), h.DB, modelId)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to delete Gemini Live model")
		return
	}

	httpjson.JSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) logAppEvent(req *http.Request, eventType, outcome string, statusCode int, metadata map[string]any) {
	if h.Logger == nil {
		return
	}
	authCtx, _ := req.Context().Value(auth.AuthContextKey).(*auth.AuthContext)
	var actorUserID *string
	var sessionID *string
	var deviceID *string
	if authCtx != nil {
		actorUserID = &authCtx.User.ID
		sessionID = &authCtx.SessionID
		deviceID = authCtx.DeviceID
	}

	h.Logger.Log(req.Context(), req, events.Event{
		EventType:   eventType,
		Outcome:     outcome,
		Source:      "desktop", // Gemini Live requests are from the desktop client
		ActorUserID: actorUserID,
		SessionID:   sessionID,
		DeviceID:    deviceID,
		StatusCode:  &statusCode,
		Metadata:    metadata,
	})
}

func normalizeModality(raw string) string {
	raw = strings.ToUpper(strings.TrimSpace(raw))
	switch raw {
	case "AUDIO", "TEXT", "IMAGE":
		return raw
	default:
		return ""
	}
}

func normalizeMediaResolution(raw string) string {
	raw = strings.ToUpper(strings.TrimSpace(raw))
	switch raw {
	case "MEDIA_RESOLUTION_LOW", "MEDIA_RESOLUTION_MEDIUM", "MEDIA_RESOLUTION_HIGH":
		return raw
	default:
		return ""
	}
}

func normalizeThinkingLevel(raw string) string {
	raw = strings.ToUpper(strings.TrimSpace(raw))
	switch raw {
	case "MINIMAL", "LOW", "MEDIUM", "HIGH":
		return raw
	default:
		return ""
	}
}

func modelUsesThinkingLevel(model string) bool {
	model = strings.TrimPrefix(model, "models/")
	return strings.HasPrefix(strings.ToLower(model), "gemini-3")
}

func buildGeminiLiveConnectConfig(req GeminiLiveSessionTokenRequest, resolvedModelID string) (GoogleLiveConfig, []string, string) {
	var requestedModalities []string
	for _, m := range req.ResponseModalities {
		norm := normalizeModality(m)
		if norm != "" {
			requestedModalities = append(requestedModalities, norm)
		}
	}
	if len(requestedModalities) == 0 {
		requestedModalities = []string{"AUDIO"}
	}

	liveConfig := GoogleLiveConfig{
		ResponseModalities: requestedModalities,
	}

	if req.VoiceName != nil {
		voiceName := strings.TrimSpace(*req.VoiceName)
		if voiceName != "" {
			liveConfig.SpeechConfig = &GoogleSpeechConfig{
				VoiceConfig: GooglePrebuiltVoiceConfig{
					PrebuiltVoiceConfig: GoogleVoiceConfig{
						VoiceName: voiceName,
					},
				},
			}
		}
	}

	if req.SystemInstruction != nil {
		sysInst := strings.TrimSpace(*req.SystemInstruction)
		if sysInst != "" {
			liveConfig.SystemInstruction = &GoogleSystemInstruction{
				Parts: []GooglePart{
					{Text: sysInst},
				},
			}
		}
	}

	if modelUsesThinkingLevel(resolvedModelID) {
		if req.ThinkingLevel != nil {
			lvl := normalizeThinkingLevel(*req.ThinkingLevel)
			if lvl != "" {
				liveConfig.ThinkingConfig = &GoogleThinkingConfig{
					ThinkingLevel: lvl,
				}
			}
		}
	} else if req.ThinkingBudget != nil {
		budget := *req.ThinkingBudget
		if budget < 0 {
			budget = 0
		}
		liveConfig.ThinkingConfig = &GoogleThinkingConfig{
			ThinkingBudget: budget,
		}
	}

	mediaRes := ""
	if req.MediaResolution != nil {
		mediaRes = normalizeMediaResolution(*req.MediaResolution)
		if mediaRes != "" {
			liveConfig.MediaResolution = mediaRes
		}
	}

	return liveConfig, requestedModalities, mediaRes
}
