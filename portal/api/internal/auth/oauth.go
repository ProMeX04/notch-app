package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/auth/token"
	"notch/portal/api/internal/httpjson"
)

type OAuthAuthorizeRequest struct {
	ClientID            string `json:"client_id"`
	RedirectURI         string `json:"redirect_uri"`
	ResponseType        string `json:"response_type"`
	CodeChallenge       string `json:"code_challenge"`
	CodeChallengeMethod string `json:"code_challenge_method"`
	State               string `json:"state"`
}

type OAuthAuthorizeResponse struct {
	RedirectTo string `json:"redirect_to"`
	ExpiresAt  string `json:"expires_at"`
}

type OAuthTokenRequest struct {
	GrantType    string `json:"grant_type"`
	ClientID     string `json:"client_id"`
	RedirectURI  string `json:"redirect_uri"`
	Code         string `json:"code"`
	CodeVerifier string `json:"code_verifier"`
	RefreshToken string `json:"refresh_token"`
	DeviceID     string `json:"device_id"`
	DeviceName   string `json:"device_name"`
	Platform     string `json:"platform"`
	TrustDevice  any    `json:"trust_device"`
}

type OAuthTokenResponse struct {
	AccessToken           string             `json:"access_token"`
	TokenType             string             `json:"token_type"`
	ExpiresAt             string             `json:"expires_at"`
	RefreshToken          string             `json:"refresh_token"`
	RefreshExpiresAt      string             `json:"refresh_expires_at"`
	ExpiresIn             int64              `json:"expires_in"`
	RefreshTokenExpiresIn int64              `json:"refresh_token_expires_in"`
	Scope                 string             `json:"scope"`
	User                  AuthPayloadUser    `json:"user"`
	Session               AuthPayloadSession `json:"session"`
	MaxActiveDevices      int                `json:"max_active_devices"`
}

func generateRandomCode() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

func (h Handler) OAuthAuthorize(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	authCtx, err := h.Authenticator.AuthenticateRequest(req.Context(), req)
	if err != nil {
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}

	var body OAuthAuthorizeRequest
	if req.Body != nil {
		if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
			httpjson.Error(w, http.StatusBadRequest, "Invalid request body")
			return
		}
	}

	// Validate client configurations
	if body.ClientID != h.NativeClientID {
		httpjson.Error(w, http.StatusBadRequest, "Unsupported OAuth client.")
		return
	}

	redirectURIOk := false
	for _, uri := range h.NativeRedirectURIs {
		if uri == body.RedirectURI {
			redirectURIOk = true
			break
		}
	}
	if !redirectURIOk {
		httpjson.Error(w, http.StatusBadRequest, "Unsupported OAuth redirect URI.")
		return
	}

	if body.ResponseType != "code" {
		httpjson.Error(w, http.StatusBadRequest, "Unsupported OAuth response type.")
		return
	}

	if len(body.CodeChallenge) < 43 || len(body.CodeChallenge) > 128 {
		httpjson.Error(w, http.StatusBadRequest, "Invalid PKCE code challenge.")
		return
	}

	if body.CodeChallengeMethod != "S256" {
		httpjson.Error(w, http.StatusBadRequest, "Only PKCE S256 is supported.")
		return
	}

	code, err := generateRandomCode()
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Could not generate authorization code.")
		return
	}

	codeHash := token.HashToken(code)
	now := time.Now()
	expiresAt := now.Add(5 * time.Minute)

	oauthCode := &OAuthAuthorizationCode{
		ID:                  generateUUID(),
		CodeHash:            codeHash,
		ClientID:            body.ClientID,
		RedirectURI:         body.RedirectURI,
		CodeChallenge:       body.CodeChallenge,
		CodeChallengeMethod: body.CodeChallengeMethod,
		ExpiresAt:           expiresAt,
		CreatedAt:           now,
		UserID:              authCtx.User.ID,
	}

	err = h.Repo.CreateOAuthAuthorizationCode(req.Context(), oauthCode)
	if err != nil {
		httpjson.Error(w, http.StatusInternalServerError, "Could not save authorization code.")
		return
	}

	redirectURL := body.RedirectURI + "?code=" + code
	if body.State != "" {
		redirectURL += "&state=" + body.State
	}

	httpjson.JSON(w, http.StatusOK, OAuthAuthorizeResponse{
		RedirectTo: redirectURL,
		ExpiresAt:  expiresAt.UTC().Format(time.RFC3339Nano),
	})
}

func (h Handler) OAuthToken(w http.ResponseWriter, req *http.Request) {
	noStore(w)
	var body OAuthTokenRequest
	contentType := req.Header.Get("Content-Type")
	if strings.Contains(contentType, "application/x-www-form-urlencoded") {
		if err := req.ParseForm(); err != nil {
			httpjson.Error(w, http.StatusBadRequest, "Invalid form data")
			return
		}
		body.GrantType = req.PostFormValue("grant_type")
		body.ClientID = req.PostFormValue("client_id")
		body.RedirectURI = req.PostFormValue("redirect_uri")
		body.Code = req.PostFormValue("code")
		body.CodeVerifier = req.PostFormValue("code_verifier")
		body.RefreshToken = req.PostFormValue("refresh_token")
		body.DeviceID = req.PostFormValue("device_id")
		body.DeviceName = req.PostFormValue("device_name")
		body.Platform = req.PostFormValue("platform")
		body.TrustDevice = req.PostFormValue("trust_device")
	} else {
		if req.Body != nil {
			if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
				httpjson.Error(w, http.StatusBadRequest, "Invalid request body")
				return
			}
		}
	}

	if body.GrantType == "authorization_code" {
		if body.ClientID != h.NativeClientID {
			httpjson.Error(w, http.StatusBadRequest, "Unsupported OAuth client.")
			return
		}

		redirectURIOk := false
		for _, uri := range h.NativeRedirectURIs {
			if uri == body.RedirectURI {
				redirectURIOk = true
				break
			}
		}
		if !redirectURIOk {
			httpjson.Error(w, http.StatusBadRequest, "Unsupported OAuth redirect URI.")
			return
		}

		if body.Code == "" || body.CodeVerifier == "" {
			httpjson.Error(w, http.StatusBadRequest, "Missing authorization code exchange parameters.")
			return
		}

		codeHash := token.HashToken(body.Code)
		authCode, err := h.Repo.FindOAuthAuthorizationCode(req.Context(), codeHash)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Internal server error")
			return
		}

		now := time.Now()
		if authCode == nil || authCode.ConsumedAt != nil || authCode.ExpiresAt.Before(now) {
			httpjson.Detail(w, http.StatusUnauthorized, "OAuth code or token is invalid or expired.")
			return
		}

		if authCode.ClientID != body.ClientID || authCode.RedirectURI != body.RedirectURI {
			httpjson.Detail(w, http.StatusUnauthorized, "OAuth code or token is invalid or expired.")
			return
		}

		hash := sha256.Sum256([]byte(body.CodeVerifier))
		computedChallenge := base64.RawURLEncoding.EncodeToString(hash[:])
		if computedChallenge != authCode.CodeChallenge {
			httpjson.Detail(w, http.StatusUnauthorized, "OAuth code or token is invalid or expired.")
			return
		}

		err = h.Repo.ConsumeOAuthAuthorizationCode(req.Context(), authCode.ID, now)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Internal server error")
			return
		}

		// Create session and return OAuthTokenResponse
		sessionID := generateUUID()
		refreshToken, err := token.GenerateRefreshToken()
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		refreshTokenHash := token.HashToken(refreshToken)

		accessTTL := h.RefreshService.AccessTokenTTL
		if accessTTL <= 0 {
			accessTTL = time.Hour
		}
		refreshTTL := h.RefreshService.RefreshTokenTTL
		if refreshTTL <= 0 {
			refreshTTL = 30 * 24 * time.Hour
		}

		accessExpiresAt := now.Add(accessTTL)
		refreshExpiresAt := now.Add(refreshTTL)

		deviceInput := DeviceInput{
			DeviceID:    body.DeviceID,
			DeviceName:  body.DeviceName,
			Platform:    body.Platform,
			TrustDevice: parseTrustDevice(body.TrustDevice),
		}

		device := NormalizeDevice(req, deviceInput, authCode.User.ID+":"+sessionID, nil)
		var trustedAt *time.Time
		if device.TrustDevice {
			trustedAt = &now
		}

		accessToken, err := token.SignJWT(token.JWTPayload{
			UserID:           authCode.User.ID,
			Email:            authCode.User.Email,
			Name:             authCode.User.Name,
			DisplayName:      authCode.User.DisplayName,
			AvatarURL:        authCode.User.AvatarURL,
			IsPro:            authCode.User.IsPro,
			IsAdmin:          authCode.User.IsAdmin,
			LeaderboardOptIn: authCode.User.LeaderboardOptIn,
			UserCreatedAt:    authCode.User.CreatedAt.UTC().Format(time.RFC3339Nano),
			SessionID:        sessionID,
			DeviceID:         &device.DeviceID,
		}, h.RefreshService.JWTSecret, accessTTL, now)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		accessTokenHash := token.HashToken(accessToken)

		err = h.Repo.CreateSession(req.Context(), sessionID, authCode.User.ID, refreshTokenHash, &accessTokenHash, device, refreshExpiresAt, &accessExpiresAt, trustedAt, now)
		if err != nil {
			httpjson.Error(w, http.StatusInternalServerError, "Internal server error")
			return
		}

		httpauth.ApplyAuthCookies(w, req, h.CookieConfig, httpauth.AuthCookiePayload{
			AccessToken:      accessToken,
			AccessExpiresAt:  accessExpiresAt,
			RefreshToken:     refreshToken,
			RefreshExpiresAt: refreshExpiresAt,
		})

		policy := h.getPermissionPolicy(req.Context(), authCode.User.IsPro)
		payload := BuildAuthPayload(authCode.User, RotatedSession{
			ID:         sessionID,
			DeviceID:   device.DeviceID,
			DeviceName: device.DeviceName,
			Platform:   device.Platform,
			TrustedAt:  trustedAt,
		}, accessToken, accessExpiresAt, refreshToken, refreshExpiresAt, h.MaxActiveDevices, policy)

		response := OAuthTokenResponse{
			AccessToken:           payload.AccessToken,
			TokenType:             payload.TokenType,
			ExpiresAt:             payload.ExpiresAt,
			RefreshToken:          payload.RefreshToken,
			RefreshExpiresAt:      payload.RefreshExpiresAt,
			ExpiresIn:             int64(accessTTL.Seconds()),
			RefreshTokenExpiresIn: int64(refreshTTL.Seconds()),
			Scope:                 "notch",
			User:                  payload.User,
			Session:               payload.Session,
			MaxActiveDevices:      payload.MaxActiveDevices,
		}

		httpjson.JSON(w, http.StatusOK, response)
		return
	}

	if body.GrantType == "refresh_token" {
		if body.ClientID != h.NativeClientID {
			httpjson.Error(w, http.StatusBadRequest, "Unsupported OAuth client.")
			return
		}

		if body.RefreshToken == "" {
			httpjson.Error(w, http.StatusBadRequest, "Missing refresh token parameters.")
			return
		}

		deviceInput := DeviceInput{
			DeviceID:    body.DeviceID,
			DeviceName:  body.DeviceName,
			Platform:    body.Platform,
			TrustDevice: parseTrustDevice(body.TrustDevice),
		}

		payload, err := h.RefreshService.RefreshWithToken(req.Context(), req, body.RefreshToken, deviceInput)
		if err != nil {
			httpjson.Detail(w, http.StatusUnauthorized, "Refresh token is invalid or expired.")
			return
		}

		applyPayloadCookies(w, req, h.CookieConfig, payload)

		accessTTL := h.RefreshService.AccessTokenTTL
		if accessTTL <= 0 {
			accessTTL = time.Hour
		}
		refreshTTL := h.RefreshService.RefreshTokenTTL
		if refreshTTL <= 0 {
			refreshTTL = 30 * 24 * time.Hour
		}

		response := OAuthTokenResponse{
			AccessToken:           payload.AccessToken,
			TokenType:             payload.TokenType,
			ExpiresAt:             payload.ExpiresAt,
			RefreshToken:          payload.RefreshToken,
			RefreshExpiresAt:      payload.RefreshExpiresAt,
			ExpiresIn:             int64(accessTTL.Seconds()),
			RefreshTokenExpiresIn: int64(refreshTTL.Seconds()),
			Scope:                 "notch",
			User:                  payload.User,
			Session:               payload.Session,
			MaxActiveDevices:      payload.MaxActiveDevices,
		}

		httpjson.JSON(w, http.StatusOK, response)
		return
	}

	httpjson.Error(w, http.StatusBadRequest, "Unsupported OAuth grant type.")
}
