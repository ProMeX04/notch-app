package admin

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"notch/portal/api/internal/httpjson"

	"github.com/go-chi/chi/v5"
)

func TestUpdateUserInvalidJSON(t *testing.T) {
	h := NewHandler(nil, nil)

	r := httptest.NewRequest("PATCH", "/api/admin/users/123", bytes.NewBufferString("{invalid-json"))
	w := httptest.NewRecorder()

	// Put router context to mock URL param
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("id", "123")
	r = r.WithContext(context.WithValue(r.Context(), chi.RouteCtxKey, rctx))

	h.UpdateUser(w, r)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected status %d, got %d", http.StatusBadRequest, w.Code)
	}

	var resp httpjson.ErrorResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.Error != "Invalid request body" {
		t.Errorf("expected error %q, got %q", "Invalid request body", resp.Error)
	}
}

func TestUpdateUserMissingID(t *testing.T) {
	h := NewHandler(nil, nil)

	r := httptest.NewRequest("PATCH", "/api/admin/users/", bytes.NewBufferString(`{"isPro": true}`))
	w := httptest.NewRecorder()

	h.UpdateUser(w, r)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected status %d, got %d", http.StatusBadRequest, w.Code)
	}
}

func TestGetUserDetailMissingID(t *testing.T) {
	h := NewHandler(nil, nil)

	r := httptest.NewRequest("GET", "/api/admin/users/", nil)
	w := httptest.NewRecorder()

	h.GetUserDetail(w, r)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected status %d, got %d", http.StatusBadRequest, w.Code)
	}
}
