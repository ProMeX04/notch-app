package token

import "testing"

func TestEncodeDecodePortableSessionToken(t *testing.T) {
	token, err := EncodeSessionToken(PortableSession{
		AccessToken:      "access",
		ExpiresAt:        "2026-05-30T00:00:00.000Z",
		RefreshToken:     "refresh",
		RefreshExpiresAt: "2026-06-30T00:00:00.000Z",
	})
	if err != nil {
		t.Fatalf("EncodeSessionToken() error = %v", err)
	}
	decoded, err := DecodeSessionToken(token)
	if err != nil {
		t.Fatalf("DecodeSessionToken() error = %v", err)
	}
	if decoded.Kind != "portable" || decoded.AccessToken != "access" || decoded.RefreshToken != "refresh" {
		t.Fatalf("unexpected decoded token: %#v", decoded)
	}
}

func TestCreateBridgeBackedSessionToken(t *testing.T) {
	token, err := CreateBridgeBackedSessionToken("bridge", "2026-05-30T00:00:00.000Z")
	if err != nil {
		t.Fatalf("CreateBridgeBackedSessionToken() error = %v", err)
	}
	decoded, err := DecodeSessionToken(token)
	if err != nil {
		t.Fatalf("DecodeSessionToken() error = %v", err)
	}
	if decoded.Kind != "bridge" || decoded.BridgeToken != "bridge" {
		t.Fatalf("unexpected decoded bridge token: %#v", decoded)
	}
}

func TestDecodeSessionTokenRejectsInvalidShape(t *testing.T) {
	if _, err := DecodeSessionToken("not-a-token"); err == nil {
		t.Fatal("expected invalid prefix error")
	}
	token, err := EncodeSessionToken(map[string]any{"access_token": "access"})
	if err != nil {
		t.Fatalf("EncodeSessionToken() error = %v", err)
	}
	if _, err := DecodeSessionToken(token); err == nil {
		t.Fatal("expected invalid portable shape error")
	}
}
