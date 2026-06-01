package auth

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"notch/portal/api/internal/auth/token"
	"notch/portal/api/internal/httpjson"
)

func (h Handler) GoogleDriveAuth(w http.ResponseWriter, req *http.Request) {
	q := req.URL.Query()
	desktopState := q.Get("state")
	codeChallenge := q.Get("code_challenge")

	if desktopState == "" || len(desktopState) > 256 {
		httpjson.Error(w, http.StatusBadRequest, "Missing or invalid Google Drive OAuth state")
		return
	}
	if len(codeChallenge) != 43 {
		httpjson.Error(w, http.StatusBadRequest, "Missing or invalid Google Drive handoff challenge")
		return
	}

	scheme := "http"
	if req.TLS != nil || req.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	redirectURL := fmt.Sprintf("%s://%s/api/auth/google?gdrive=true&state=%s&code_challenge=%s", scheme, req.Host, url.QueryEscape(desktopState), url.QueryEscape(codeChallenge))
	http.Redirect(w, req, redirectURL, http.StatusTemporaryRedirect)
}

type GoogleDriveExchangeRequest struct {
	HandoffToken string `json:"handoff_token"`
	CodeVerifier string `json:"code_verifier"`
}

type GoogleDriveExchangeResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	ExpiresIn    *int   `json:"expires_in,omitempty"`
}

func (h Handler) GoogleDriveExchange(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	var body GoogleDriveExchangeRequest
	if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	handoffToken := strings.TrimSpace(body.HandoffToken)
	codeVerifier := strings.TrimSpace(body.CodeVerifier)

	if handoffToken == "" || len(codeVerifier) < 43 || len(codeVerifier) > 128 {
		httpjson.Error(w, http.StatusBadRequest, "Missing handoff credentials")
		return
	}

	tokenHash := token.HashToken(handoffToken)
	handoff, err := h.Repo.FindGoogleDriveAuthHandoff(req.Context(), tokenHash)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Internal Server Error")
		return
	}

	now := time.Now()
	if handoff == nil || handoff.ConsumedAt != nil || handoff.ExpiresAt.Before(now) {
		httpjson.Error(w, http.StatusBadRequest, "Invalid or expired handoff token")
		return
	}

	hash := sha256.Sum256([]byte(codeVerifier))
	computedChallenge := base64.RawURLEncoding.EncodeToString(hash[:])
	if computedChallenge != handoff.CodeChallenge {
		httpjson.Error(w, http.StatusBadRequest, "Invalid or expired handoff token")
		return
	}

	accessToken, err := decryptGoogleDriveHandoffValue(handoff.AccessToken, h.DriveHandoffEncryptKey)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Internal Server Error")
		return
	}

	var refreshToken string
	if handoff.RefreshToken != nil && *handoff.RefreshToken != "" {
		refreshToken, err = decryptGoogleDriveHandoffValue(*handoff.RefreshToken, h.DriveHandoffEncryptKey)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Internal Server Error")
			return
		}
	}

	err = h.Repo.ConsumeGoogleDriveAuthHandoff(req.Context(), handoff.ID, now)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Internal Server Error")
		return
	}

	_ = h.Repo.DeleteExpiredGoogleDriveAuthHandoffs(req.Context(), now.Add(-60*time.Second))

	httpjson.JSON(w, http.StatusOK, GoogleDriveExchangeResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    handoff.ExpiresIn,
	})
}

type GoogleDriveRefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h Handler) GoogleDriveRefresh(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	var body GoogleDriveRefreshRequest
	if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
		httpjson.Error(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	refreshToken := strings.TrimSpace(body.RefreshToken)
	if refreshToken == "" {
		httpjson.Error(w, http.StatusBadRequest, "Missing refresh token")
		return
	}

	if h.GoogleClientID == "" || h.GoogleClientSecret == "" {
		httpjson.Error(w, http.StatusInternalServerError, "Google client credentials not configured")
		return
	}

	httpClient := h.HTTPClient
	if httpClient == nil {
		httpClient = http.DefaultClient
	}

	resp, err := httpClient.PostForm("https://oauth2.googleapis.com/token", url.Values{
		"client_id":     {h.GoogleClientID},
		"client_secret": {h.GoogleClientSecret},
		"refresh_token": {refreshToken},
		"grant_type":    {"refresh_token"},
	})
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Failed to refresh token")
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errData map[string]interface{}
		_ = json.NewDecoder(resp.Body).Decode(&errData)
		errorMsg := "Failed to refresh token"
		if errData != nil {
			if desc, ok := errData["error_description"].(string); ok {
				errorMsg = desc
			} else if e, ok := errData["error"].(string); ok {
				errorMsg = e
			}
		}
		httpjson.Error(w, resp.StatusCode, errorMsg)
		return
	}

	var data map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Internal Server Error")
		return
	}

	httpjson.JSON(w, http.StatusOK, data)
}
