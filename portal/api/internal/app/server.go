package app

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"time"

	"notch/portal/api/internal/admin"
	"notch/portal/api/internal/auth"
	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/capabilities"
	"notch/portal/api/internal/config"
	"notch/portal/api/internal/db"
	"notch/portal/api/internal/events"
	"notch/portal/api/internal/focus"
	"notch/portal/api/internal/geminilive"
	"notch/portal/api/internal/httpjson"
	"notch/portal/api/internal/payments"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
)

type Server struct {
	cfg      config.Config
	db       *db.Pool
	logger   *slog.Logger
	eventLog *events.Logger
	http     *http.Server
}

func NewServer(cfg config.Config, database *db.Pool, logger *slog.Logger) *Server {
	eventLog := events.NewLogger(database.Raw(), logger, cfg.Observatory.EventLogIPSalt)
	router := chi.NewRouter()

	server := &Server{
		cfg:      cfg,
		db:       database,
		logger:   logger,
		eventLog: eventLog,
	}
	server.mount(router)
	server.http = &http.Server{
		Addr:              cfg.HTTP.Addr,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}
	return server
}

func (s *Server) ListenAndServe() error {
	return s.http.ListenAndServe()
}

func (s *Server) Shutdown(ctx context.Context) error {
	return s.http.Shutdown(ctx)
}

func (s *Server) mount(r chi.Router) {
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	if os.Getenv("NODE_ENV") != "production" {
		r.Use(middleware.Logger)
	}
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   s.cfg.HTTP.AllowedDevOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token", "X-Notch-Device-Id"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Get("/healthz", s.health)
	r.Get("/readyz", s.ready)

	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, s.cfg.HTTP.FrontendURL, http.StatusTemporaryRedirect)
	})
	r.Get("/oauth/authorize", func(w http.ResponseWriter, r *http.Request) {
		redirectURL := s.cfg.HTTP.FrontendURL + r.URL.Path
		if r.URL.RawQuery != "" {
			redirectURL += "?" + r.URL.RawQuery
		}
		http.Redirect(w, r, redirectURL, http.StatusTemporaryRedirect)
	})

	sessionRepo := auth.NewPgxSessionRepository(s.db.Raw())
	authHandler := auth.Handler{
		Authenticator: auth.Authenticator{
			Repo:      sessionRepo,
			JWTSecret: s.cfg.Auth.JWTSecret,
		},
		RefreshService: auth.RefreshService{
			Repo:             sessionRepo,
			JWTSecret:        s.cfg.Auth.JWTSecret,
			AccessTokenTTL:   s.cfg.Auth.AccessTokenTTL,
			RefreshTokenTTL:  s.cfg.Auth.RefreshTokenTTL,
			MaxActiveDevices: s.cfg.Auth.MaxActiveDevices,
		},
		CookieConfig: httpauth.CookieConfig{
			Secure: s.cfg.Auth.SecureCookies,
			Domain: s.cfg.Auth.CookieDomain,
		},
		MaxActiveDevices:       s.cfg.Auth.MaxActiveDevices,
		Repo:                   sessionRepo,
		GoogleClientID:         s.cfg.OAuth.GoogleClientID,
		GoogleClientSecret:     s.cfg.OAuth.GoogleClientSecret,
		DriveHandoffEncryptKey: s.cfg.OAuth.DriveHandoffEncryptKey,
		FrontendURL:            s.cfg.HTTP.FrontendURL,
		NativeClientID:         s.cfg.OAuth.NativeClientID,
		NativeRedirectURIs:     s.cfg.OAuth.NativeRedirectURIAllow,
	}

	focusRepo := focus.NewPgxRepository(s.db.Raw())
	focusHandler := focus.NewHandler(focusRepo, authHandler.Authenticator, s.eventLog, s.logger)

	paymentsHandler := payments.NewHandler(s.cfg.Payments, s.cfg.HTTP.FrontendURL, s.db, authHandler.Authenticator, s.eventLog)

	capabilitiesRepo := capabilities.NewPgxRepository(s.db.Raw())
	capabilitiesHandler := capabilities.NewHandler(capabilitiesRepo, s.db.Raw(), s.eventLog)

	adminHandler := admin.NewHandler(s.db.Raw(), s.eventLog)
	geminiLiveHandler := geminilive.NewHandler(s.db.Raw(), s.eventLog, s.cfg.Gemini.APIKey)

	r.Route("/api", func(api chi.Router) {
		api.Get("/healthz", s.health)
		api.Get("/auth/me", authHandler.Me)
		api.Post("/auth/refresh", authHandler.Refresh)
		api.Post("/auth/login", authHandler.Login)
		api.Post("/auth/register", authHandler.Register)
		api.Post("/auth/logout", authHandler.Logout)
		api.Patch("/auth/profile", authHandler.UpdateProfile)
		api.Get("/auth/sessions", authHandler.ListSessions)
		api.Delete("/auth/sessions/{id}", authHandler.RevokeSession)
		api.Patch("/auth/sessions", authHandler.PatchSessions)
		api.Get("/auth/google", authHandler.GoogleLogin)
		api.Get("/auth/google/callback", authHandler.GoogleCallback)
		api.Get("/auth/google-drive", authHandler.GoogleDriveAuth)
		api.Post("/auth/google-drive/exchange", authHandler.GoogleDriveExchange)
		api.Post("/auth/google-drive/refresh", authHandler.GoogleDriveRefresh)
		api.Post("/oauth/authorize", authHandler.OAuthAuthorize)
		api.Post("/oauth/token", authHandler.OAuthToken)

		api.Get("/focus/leaderboard", focusHandler.Leaderboard)
		api.Get("/focus/me", focusHandler.Me)
		api.Patch("/focus/profile", focusHandler.Profile)
		api.Post("/focus/sync", focusHandler.Sync)


		api.Post("/payments/vnpay/create", paymentsHandler.Create)
		api.Post("/payments/vnpay/create-guest", paymentsHandler.CreateGuest)
		api.Get("/payments/vnpay/ipn", paymentsHandler.IPN)
		api.Get("/payments/vnpay/return", paymentsHandler.Return)

		api.Get("/capabilities", capabilitiesHandler.GetCapabilities)

		api.Route("/gemini-live", func(gl chi.Router) {
			gl.Get("/health", geminiLiveHandler.GetHealth)
			gl.Group(func(authGL chi.Router) {
				authGL.Use(authHandler.Authenticator.Authenticate)
				authGL.Get("/models", geminiLiveHandler.GetModels)
				authGL.Post("/session-token", geminiLiveHandler.CreateSessionToken)
			})
		})

		api.Route("/admin", func(admin chi.Router) {
			admin.Use(authHandler.Authenticator.Authenticate)
			admin.Use(auth.AdminOnly)

			admin.Get("/stats", adminHandler.GetStats)

			admin.Get("/capabilities", capabilitiesHandler.AdminGetCapabilities)
			admin.Post("/capabilities", capabilitiesHandler.AdminPostCapabilities)

			admin.Get("/users", adminHandler.GetUsers)
			admin.Get("/users/{id}", adminHandler.GetUserDetail)
			admin.Patch("/users/{id}", adminHandler.UpdateUser)

			admin.Get("/gemini-live/models", geminiLiveHandler.AdminGetModels)
			admin.Post("/gemini-live/models", geminiLiveHandler.AdminPostModels)
			admin.Delete("/gemini-live/models", geminiLiveHandler.AdminDeleteModel)
		})

		api.NotFound(func(w http.ResponseWriter, r *http.Request) {
			httpjson.Error(w, http.StatusNotImplemented, "endpoint not migrated to Go yet")
		})
	})
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	httpjson.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) ready(w http.ResponseWriter, r *http.Request) {
	if err := s.db.Ping(r.Context()); err != nil {
		httpjson.JSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not_ready", "reason": err.Error()})
		return
	}
	httpjson.JSON(w, http.StatusOK, map[string]string{"status": "ready"})
}
