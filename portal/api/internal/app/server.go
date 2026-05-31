package app

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"notch/portal/api/internal/auth"
	"notch/portal/api/internal/auth/httpauth"
	"notch/portal/api/internal/config"
	"notch/portal/api/internal/db"
	"notch/portal/api/internal/events"
	"notch/portal/api/internal/focus"
	"notch/portal/api/internal/httpjson"

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
	server := &Server{cfg: cfg, db: database, logger: logger, eventLog: eventLog}
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
	}

	focusRepo := focus.NewPgxRepository(s.db.Raw())
	focusHandler := focus.NewHandler(focusRepo, authHandler.Authenticator, s.eventLog)

	r.Route("/api", func(api chi.Router) {
		api.Get("/healthz", s.health)
		api.Get("/auth/me", authHandler.Me)
		api.Post("/auth/refresh", authHandler.Refresh)
		api.Post("/auth/login", authHandler.Login)
		api.Post("/auth/register", authHandler.Register)
		api.Post("/auth/logout", authHandler.Logout)
		api.Get("/auth/sessions", authHandler.ListSessions)
		api.Delete("/auth/sessions/{id}", authHandler.RevokeSession)
		api.Get("/auth/google", authHandler.GoogleLogin)
		api.Get("/auth/google/callback", authHandler.GoogleCallback)

		api.Get("/focus/leaderboard", focusHandler.Leaderboard)
		api.Get("/focus/me", focusHandler.Me)
		api.Patch("/focus/profile", focusHandler.Profile)
		api.Post("/focus/sync", focusHandler.Sync)

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
