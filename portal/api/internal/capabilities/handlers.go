package capabilities

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"notch/portal/api/internal/auth"
	"notch/portal/api/internal/events"
	"notch/portal/api/internal/httpjson"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Handler struct {
	Repo   Repository
	DB     *pgxpool.Pool
	Logger *events.Logger
}

func NewHandler(repo Repository, dbPool *pgxpool.Pool, logger *events.Logger) *Handler {
	return &Handler{
		Repo:   repo,
		DB:     dbPool,
		Logger: logger,
	}
}

func (h *Handler) GetCapabilities(w http.ResponseWriter, req *http.Request) {
	policy, err := GetRemotePermissionPolicy(req.Context(), h.Repo)
	if err != nil {
		if req.Context().Err() != nil || errors.Is(err, context.Canceled) {
			return
		}
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch capabilities")
		return
	}
	httpjson.JSON(w, http.StatusOK, policy)
}

func (h *Handler) AdminGetCapabilities(w http.ResponseWriter, req *http.Request) {
	configs, err := h.Repo.FindAll(req.Context())
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to fetch capabilities")
		return
	}
	merged := MergeDefaultFeatureConfigs(configs)
	httpjson.JSON(w, http.StatusOK, merged)
}

func (h *Handler) AdminPostCapabilities(w http.ResponseWriter, req *http.Request) {
	var body map[string]any
	if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	actionVal, hasAction := body["action"]
	if hasAction {
		action, ok := actionVal.(string)
		if ok && action == "restore_defaults" {
			defaults, err := RestoreDefaultCapabilities(req.Context(), h.DB)
			if err != nil {
				h.logAdminEvent(req, "admin.capabilities_failed", "failure", 500, map[string]any{
					"action":    "restore_defaults",
					"errorType": "DBError",
				})
				httpjson.Error(w, http.StatusInternalServerError, "Failed to restore default capabilities")
				return
			}

			h.logAdminEvent(req, "admin.capabilities_restore_defaults_succeeded", "success", 200, map[string]any{
				"defaultCount": len(defaults),
			})
			httpjson.JSON(w, http.StatusOK, defaults)
			return
		}
	}

	key, _ := body["key"].(string)
	name, _ := body["name"].(string)
	descVal, hasDesc := body["description"]
	var description *string
	if hasDesc && descVal != nil {
		dStr, ok := descVal.(string)
		if ok {
			description = &dStr
		}
	}
	isProOnly, _ := body["isProOnly"].(bool)
	isEnabled, _ := body["isEnabled"].(bool)

	if key == "" || name == "" {
		httpjson.Error(w, http.StatusBadRequest, "Key and Name are required")
		return
	}

	cfg := FeatureConfig{
		ID:          generateRandomString(24),
		Key:         key,
		Name:        name,
		Description: description,
		IsProOnly:   isProOnly,
		IsEnabled:   isEnabled,
	}

	err := h.Repo.Upsert(req.Context(), cfg)
	if err != nil {
		h.logAdminEvent(req, "admin.capabilities_failed", "failure", 500, map[string]any{
			"action":    "upsert",
			"key":       key,
			"errorType": "DBError",
		})
		httpjson.Error(w, http.StatusInternalServerError, "Failed to update capability")
		return
	}

	h.logAdminEvent(req, "admin.capability_upsert_succeeded", "success", 200, map[string]any{
		"key":     key,
		"enabled": isEnabled,
		"proOnly": isProOnly,
	})
	httpjson.JSON(w, http.StatusOK, cfg)
}

func (h *Handler) logAdminEvent(req *http.Request, eventType, outcome string, statusCode int, metadata map[string]any) {
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
		Source:      "web",
		ActorUserID: actorUserID,
		SessionID:   sessionID,
		DeviceID:    deviceID,
		StatusCode:  &statusCode,
		Metadata:    metadata,
	})
}
