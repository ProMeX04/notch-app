package auth

import (
	"testing"
	"time"
)

func TestBuildUserResponseMatchesMeShape(t *testing.T) {
	email := "user@example.com"
	name := "Notch User"
	sessionID := "session_1"
	createdAt := time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)

	response := BuildUserResponse(User{
		ID:               "user_1",
		Email:            &email,
		Name:             &name,
		CreatedAt:        createdAt,
		IsPro:            true,
		LeaderboardOptIn: true,
	}, &sessionID, 3, PermissionPolicy{Version: 1, Features: map[string]string{"test": "free"}})

	if response.Email != email || response.Name == nil || *response.Name != name {
		t.Fatalf("unexpected identity response: %#v", response)
	}
	if response.CurrentSessionID == nil || *response.CurrentSessionID != sessionID {
		t.Fatalf("unexpected session id: %#v", response.CurrentSessionID)
	}
	if !response.IsPro || !response.LeaderboardOptIn || response.MaxActiveDevices != 3 {
		t.Fatalf("unexpected account fields: %#v", response)
	}
	if response.PermissionPolicy.Features == nil {
		t.Fatal("permission policy features map must be present")
	}
}
