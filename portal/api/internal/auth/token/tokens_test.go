package token

import (
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestHashTokenMatchesPortalSHA256Hex(t *testing.T) {
	got := HashToken("notch-refresh-token")
	want := "0ce3977b07d7f853bceae8ca86523689bea74bedb194281292fd37e754f6aaa9"
	if got != want {
		t.Fatalf("HashToken() = %s, want %s", got, want)
	}
}

func TestSignAndVerifyJWTUsesPortalCompatibleShape(t *testing.T) {
	email := "user@example.com"
	name := "Notch User"
	deviceID := "device_1"
	now := time.Unix(1_700_000_000, 0).UTC()
	payload := JWTPayload{
		UserID:           "user_1",
		Email:            &email,
		Name:             &name,
		IsPro:            true,
		IsAdmin:          false,
		LeaderboardOptIn: true,
		UserCreatedAt:    "2026-05-30T00:00:00.000Z",
		SessionID:        "session_1",
		DeviceID:         &deviceID,
	}

	token, err := SignJWT(payload, "secret", time.Hour, now)
	if err != nil {
		t.Fatalf("SignJWT() error = %v", err)
	}

	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("token has %d parts", len(parts))
	}
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		t.Fatalf("header decode error = %v", err)
	}
	var header map[string]string
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		t.Fatalf("header json error = %v", err)
	}
	if header["alg"] != "HS256" || header["typ"] != "JWT" {
		t.Fatalf("unexpected header: %#v", header)
	}

	verified, err := VerifyJWT(token, "secret", now.Add(10*time.Minute))
	if err != nil {
		t.Fatalf("VerifyJWT() error = %v", err)
	}
	if verified.UserID != payload.UserID || verified.SessionID != payload.SessionID || verified.ExpiresAt != now.Add(time.Hour).Unix() {
		t.Fatalf("unexpected payload: %#v", verified)
	}
}

func TestVerifyJWTRejectsExpiredToken(t *testing.T) {
	now := time.Unix(1_700_000_000, 0).UTC()
	token, err := SignJWT(JWTPayload{UserID: "user_1", SessionID: "session_1"}, "secret", time.Hour, now)
	if err != nil {
		t.Fatalf("SignJWT() error = %v", err)
	}
	if _, err := VerifyJWT(token, "secret", now.Add(time.Hour)); err == nil {
		t.Fatal("VerifyJWT() accepted an expired token")
	}
}
