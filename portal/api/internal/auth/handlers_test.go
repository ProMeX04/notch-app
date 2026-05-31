package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/auth/token"

	"golang.org/x/crypto/bcrypt"
)

func TestHandlerRegisterSucceeds(t *testing.T) {
	repo := &fakeSessionRepo{
		byID:         make(map[string]*Session),
		usersByEmail: make(map[string]*User),
	}
	handler := Handler{
		Repo: repo,
		Authenticator: Authenticator{
			Repo:      repo,
			JWTSecret: "testsecret",
		},
		RefreshService: RefreshService{
			Repo:            repo,
			JWTSecret:       "testsecret",
			AccessTokenTTL:  time.Hour,
			RefreshTokenTTL: 24 * time.Hour,
		},
		CookieConfig: httpauth.CookieConfig{
			Secure: false,
			Domain: "localhost",
		},
		MaxActiveDevices: 3,
	}

	reqBody := RegisterRequest{
		Email:      "newuser@example.com",
		Password:   "password123",
		Name:       "New User",
		DeviceID:   "device_1",
		DeviceName: "Test Device",
		Platform:   "macOS",
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req := httptest.NewRequest(http.MethodPost, "/api/auth/register", bytes.NewReader(bodyBytes))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status 201, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp UserResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if resp.Email != "newuser@example.com" {
		t.Errorf("expected email %q, got %q", "newuser@example.com", resp.Email)
	}

	if resp.CurrentSessionID == nil || *resp.CurrentSessionID == "" {
		t.Error("expected session ID to be returned")
	}

	// Verify user is in repo
	user, err := repo.FindUserByEmail(context.Background(), "newuser@example.com")
	if err != nil || user == nil {
		t.Fatalf("user was not saved in repo")
	}

	// Verify session is in repo
	session, err := repo.FindSessionByID(context.Background(), *resp.CurrentSessionID)
	if err != nil || session == nil {
		t.Fatalf("session was not created in repo")
	}

	// Check cookies are set
	cookies := rec.Result().Cookies()
	var hasAccess, hasRefresh bool
	for _, c := range cookies {
		if c.Name == httpauth.AccessCookieName {
			hasAccess = true
		}
		if c.Name == httpauth.RefreshCookieName {
			hasRefresh = true
		}
	}
	if !hasAccess || !hasRefresh {
		t.Errorf("cookies not set properly: access=%t, refresh=%t", hasAccess, hasRefresh)
	}
}

func TestHandlerRegisterFailsEmailInUse(t *testing.T) {
	hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("password123"), 10)
	email := "existing@example.com"
	existingUser := &User{
		ID:        "user_1",
		Email:     &email,
		Password:  ptrStr(string(hashedPassword)),
		CreatedAt: time.Now(),
	}

	repo := &fakeSessionRepo{
		byID: make(map[string]*Session),
		usersByEmail: map[string]*User{
			"existing@example.com": existingUser,
		},
	}
	handler := Handler{
		Repo: repo,
	}

	reqBody := RegisterRequest{
		Email:    "existing@example.com",
		Password: "password123",
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req := httptest.NewRequest(http.MethodPost, "/api/auth/register", bytes.NewReader(bodyBytes))
	rec := httptest.NewRecorder()

	handler.Register(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	if !strings.Contains(rec.Body.String(), "Email này đã được sử dụng") {
		t.Errorf("expected error message for email in use, got: %s", rec.Body.String())
	}
}

func TestHandlerLoginSucceeds(t *testing.T) {
	hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("password123"), 10)
	email := "user@example.com"
	existingUser := &User{
		ID:        "user_1",
		Email:     &email,
		Password:  ptrStr(string(hashedPassword)),
		CreatedAt: time.Now(),
	}

	repo := &fakeSessionRepo{
		byID: make(map[string]*Session),
		usersByEmail: map[string]*User{
			"user@example.com": existingUser,
		},
	}
	handler := Handler{
		Repo: repo,
		Authenticator: Authenticator{
			Repo:      repo,
			JWTSecret: "testsecret",
		},
		RefreshService: RefreshService{
			Repo:            repo,
			JWTSecret:       "testsecret",
			AccessTokenTTL:  time.Hour,
			RefreshTokenTTL: 24 * time.Hour,
		},
		CookieConfig: httpauth.CookieConfig{
			Secure: false,
			Domain: "localhost",
		},
		MaxActiveDevices: 3,
	}

	reqBody := LoginRequest{
		Email:    "user@example.com",
		Password: "password123",
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req := httptest.NewRequest(http.MethodPost, "/api/auth/login", bytes.NewReader(bodyBytes))
	rec := httptest.NewRecorder()

	handler.Login(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	var resp UserResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if resp.Email != "user@example.com" {
		t.Errorf("expected email %q, got %q", "user@example.com", resp.Email)
	}

	if resp.CurrentSessionID == nil || *resp.CurrentSessionID == "" {
		t.Error("expected session ID to be returned")
	}
}

func TestHandlerLoginFailsIncorrectPassword(t *testing.T) {
	hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("password123"), 10)
	email := "user@example.com"
	existingUser := &User{
		ID:        "user_1",
		Email:     &email,
		Password:  ptrStr(string(hashedPassword)),
		CreatedAt: time.Now(),
	}

	repo := &fakeSessionRepo{
		byID: make(map[string]*Session),
		usersByEmail: map[string]*User{
			"user@example.com": existingUser,
		},
	}
	handler := Handler{
		Repo: repo,
	}

	reqBody := LoginRequest{
		Email:    "user@example.com",
		Password: "wrongpassword",
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req := httptest.NewRequest(http.MethodPost, "/api/auth/login", bytes.NewReader(bodyBytes))
	rec := httptest.NewRecorder()

	handler.Login(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected status 401, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	if !strings.Contains(rec.Body.String(), "Email hoặc mật khẩu không chính xác") {
		t.Errorf("expected error message for invalid credentials, got: %s", rec.Body.String())
	}
}

func TestHandlerLogout(t *testing.T) {
	now := time.Now()
	email := "user@example.com"
	user := User{ID: "user_1", Email: &email, CreatedAt: now}
	accessToken, _ := token.SignJWT(token.JWTPayload{
		UserID:    "user_1",
		SessionID: "session_1",
	}, "testsecret", time.Hour, now)
	accessTokenHash := token.HashToken(accessToken)

	session := &Session{
		ID:              "session_1",
		TokenHash:       token.HashToken("refresh-token"),
		AccessTokenHash: &accessTokenHash,
		ExpiresAt:       now.Add(24 * time.Hour),
		AccessExpiresAt: ptrTime(now.Add(time.Hour)),
		UserID:          "user_1",
		User:            user,
	}

	repo := &fakeSessionRepo{
		byID: map[string]*Session{
			"session_1": session,
		},
		usersByEmail: map[string]*User{
			"user@example.com": &user,
		},
	}

	handler := Handler{
		Repo: repo,
		Authenticator: Authenticator{
			Repo:      repo,
			JWTSecret: "testsecret",
		},
		CookieConfig: httpauth.CookieConfig{
			Secure: false,
			Domain: "localhost",
		},
	}

	req := httptest.NewRequest(http.MethodPost, "/api/auth/logout", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	rec := httptest.NewRecorder()

	handler.Logout(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected status 204, got %d. Body: %s", rec.Code, rec.Body.String())
	}

	// Verify session was revoked in repo
	sess := repo.byID["session_1"]
	if sess.RevokedAt == nil {
		t.Error("expected session to be marked revoked")
	}

	// Check clear cookies header
	cookies := rec.Result().Cookies()
	var clearedAccess, clearedRefresh bool
	for _, c := range cookies {
		if c.Name == httpauth.AccessCookieName && c.Value == "" {
			clearedAccess = true
		}
		if c.Name == httpauth.RefreshCookieName && c.Value == "" {
			clearedRefresh = true
		}
	}
	if !clearedAccess || !clearedRefresh {
		t.Errorf("cookies not cleared properly: access=%t, refresh=%t", clearedAccess, clearedRefresh)
	}
}

func ptrStr(s string) *string {
	return &s
}

func ptrTime(t time.Time) *time.Time {
	return &t
}
