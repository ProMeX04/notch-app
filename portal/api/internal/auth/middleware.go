package auth

import (
	"context"
	"net/http"
	"notch/portal/api/internal/httpjson"
)

type contextKey string

const AuthContextKey contextKey = "authCtx"

// Authenticate is a middleware that authenticates the request and injects AuthContext into the context.
func (a Authenticator) Authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		authCtx, err := a.AuthenticateRequest(req.Context(), req)
		if err != nil {
			httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
			return
		}

		ctx := context.WithValue(req.Context(), AuthContextKey, authCtx)
		next.ServeHTTP(w, req.WithContext(ctx))
	})
}

// AdminOnly middleware gates routes so only authenticated administrators can access them.
func AdminOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		authCtx, ok := req.Context().Value(AuthContextKey).(*AuthContext)
		if !ok || authCtx == nil {
			httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
			return
		}

		if !authCtx.User.IsAdmin {
			httpjson.Detail(w, http.StatusForbidden, "Admin privileges are required for this action.")
			return
		}

		next.ServeHTTP(w, req)
	})
}
