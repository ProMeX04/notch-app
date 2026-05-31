package geminilive

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Model struct {
	ID                         string   `json:"id"`
	Name                       string   `json:"name"`
	DisplayName                string   `json:"displayName"`
	SupportedGenerationMethods []string `json:"supportedGenerationMethods"`
}

type AdminConfig struct {
	ID                         string   `json:"id"`
	Name                       string   `json:"name"`
	DisplayName                string   `json:"displayName"`
	SupportedGenerationMethods []string `json:"supportedGenerationMethods"`
	ConfigID                   *string  `json:"configId"`
	IsEnabled                  bool     `json:"isEnabled"`
	SortOrder                  int      `json:"sortOrder"`
	Source                     string   `json:"source"`
	UpdatedAt                  *string  `json:"updatedAt"`
}

var defaultLiveModels = []Model{
	{
		ID:                         "gemini-3.1-flash-live-preview",
		Name:                       "models/gemini-3.1-flash-live-preview",
		DisplayName:                "Gemini 3.1 Flash Live Preview",
		SupportedGenerationMethods: []string{"bidiGenerateContent"},
	},
	{
		ID:                         "gemini-2.5-flash-native-audio-preview-12-2025",
		Name:                       "models/gemini-2.5-flash-native-audio-preview-12-2025",
		DisplayName:                "Gemini 2.5 Flash Native Audio Preview",
		SupportedGenerationMethods: []string{"bidiGenerateContent"},
	},
}

func normalizeGeminiLiveModelID(val string) string {
	val = strings.TrimSpace(val)
	return strings.TrimPrefix(val, "models/")
}

func titleFromModelID(id string) string {
	id = strings.TrimPrefix(id, "gemini-")
	parts := strings.Split(id, "-")
	for i, part := range parts {
		if len(part) > 0 {
			parts[i] = strings.ToUpper(part[:1]) + part[1:]
		}
	}
	return "Gemini " + strings.Join(parts, " ")
}

func listConfiguredGeminiLiveModels() []Model {
	rawList := strings.TrimSpace(os.Getenv("NOTCH_GEMINI_LIVE_ALLOWED_MODELS"))
	if rawList == "" {
		return defaultLiveModels
	}
	parts := strings.Split(rawList, ",")
	var models []Model
	seen := make(map[string]bool)
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		subparts := strings.SplitN(part, "|", 2)
		id := normalizeGeminiLiveModelID(subparts[0])
		if id == "" {
			continue
		}
		if seen[id] {
			continue
		}
		seen[id] = true
		displayName := ""
		if len(subparts) > 1 {
			displayName = strings.TrimSpace(subparts[1])
		}
		if displayName == "" {
			displayName = titleFromModelID(id)
		}
		models = append(models, Model{
			ID:                         id,
			Name:                       "models/" + id,
			DisplayName:                displayName,
			SupportedGenerationMethods: []string{"bidiGenerateContent"},
		})
	}
	if len(models) == 0 {
		return defaultLiveModels
	}
	return models
}

func ListAllowedGeminiLiveModels(ctx context.Context, db *pgxpool.Pool) ([]Model, error) {
	rows, err := db.Query(ctx, `
		SELECT "modelId", "displayName", "supportedGenerationMethods", "isEnabled"
		FROM "GeminiLiveModelConfig"
		ORDER BY "sortOrder" ASC, "displayName" ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []Model
	for rows.Next() {
		var modelId, displayName string
		var methods []string
		var isEnabled bool
		err := rows.Scan(&modelId, &displayName, &methods, &isEnabled)
		if err != nil {
			return nil, err
		}
		if len(methods) == 0 {
			methods = []string{"bidiGenerateContent"}
		}
		if isEnabled {
			list = append(list, Model{
				ID:                         modelId,
				Name:                       "models/" + modelId,
				DisplayName:                displayName,
				SupportedGenerationMethods: methods,
			})
		}
	}

	if len(list) == 0 {
		var count int
		_ = db.QueryRow(ctx, `SELECT COUNT(*) FROM "GeminiLiveModelConfig"`).Scan(&count)
		if count == 0 {
			return listConfiguredGeminiLiveModels(), nil
		}
	}

	return list, nil
}

func ListGeminiLiveModelAdminConfigs(ctx context.Context, db *pgxpool.Pool) ([]AdminConfig, error) {
	rows, err := db.Query(ctx, `
		SELECT "id", "modelId", "displayName", "supportedGenerationMethods", "isEnabled", "sortOrder", "updatedAt"
		FROM "GeminiLiveModelConfig"
		ORDER BY "sortOrder" ASC, "displayName" ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []AdminConfig
	for rows.Next() {
		var id, modelId, displayName string
		var methods []string
		var isEnabled bool
		var sortOrder int
		var updatedAt time.Time
		err := rows.Scan(&id, &modelId, &displayName, &methods, &isEnabled, &sortOrder, &updatedAt)
		if err != nil {
			return nil, err
		}
		if len(methods) == 0 {
			methods = []string{"bidiGenerateContent"}
		}
		updatedAtStr := updatedAt.UTC().Format("2006-01-02T15:04:05.000Z")
		list = append(list, AdminConfig{
			ID:                         modelId,
			Name:                       "models/" + modelId,
			DisplayName:                displayName,
			SupportedGenerationMethods: methods,
			ConfigID:                   &id,
			IsEnabled:                  isEnabled,
			SortOrder:                  sortOrder,
			Source:                     "database",
			UpdatedAt:                  &updatedAtStr,
		})
	}

	if len(list) == 0 {
		configured := listConfiguredGeminiLiveModels()
		for i, m := range configured {
			sortOrder := i
			list = append(list, AdminConfig{
				ID:                         m.ID,
				Name:                       m.Name,
				DisplayName:                m.DisplayName,
				SupportedGenerationMethods: m.SupportedGenerationMethods,
				ConfigID:                   nil,
				IsEnabled:                  true,
				SortOrder:                  sortOrder,
				Source:                     "default",
				UpdatedAt:                  nil,
			})
		}
	}

	return list, nil
}

func UpsertGeminiLiveModelAdminConfig(ctx context.Context, db *pgxpool.Pool, modelId, displayName string, isEnabled bool, sortOrder int) (*AdminConfig, error) {
	modelId = normalizeGeminiLiveModelID(modelId)
	if displayName == "" {
		displayName = titleFromModelID(modelId)
	}
	methods := []string{"bidiGenerateContent"}

	var id string
	var updatedAt time.Time

	err := db.QueryRow(ctx, `
		INSERT INTO "GeminiLiveModelConfig" ("id", "modelId", "displayName", "supportedGenerationMethods", "isEnabled", "sortOrder", "updatedAt")
		VALUES (gen_random_uuid()::text, $1, $2, $3, $4, $5, NOW())
		ON CONFLICT ("modelId")
		DO UPDATE SET
			"displayName" = EXCLUDED."displayName",
			"supportedGenerationMethods" = EXCLUDED."supportedGenerationMethods",
			"isEnabled" = EXCLUDED."isEnabled",
			"sortOrder" = EXCLUDED."sortOrder",
			"updatedAt" = NOW()
		RETURNING "id", "updatedAt"
	`, modelId, displayName, methods, isEnabled, sortOrder).Scan(&id, &updatedAt)
	if err != nil {
		return nil, err
	}

	updatedAtStr := updatedAt.UTC().Format("2006-01-02T15:04:05.000Z")
	return &AdminConfig{
		ID:                         modelId,
		Name:                       "models/" + modelId,
		DisplayName:                displayName,
		SupportedGenerationMethods: methods,
		ConfigID:                   &id,
		IsEnabled:                  isEnabled,
		SortOrder:                  sortOrder,
		Source:                     "database",
		UpdatedAt:                  &updatedAtStr,
	}, nil
}

func DeleteGeminiLiveModelAdminConfig(ctx context.Context, db *pgxpool.Pool, modelId string) error {
	modelId = normalizeGeminiLiveModelID(modelId)
	_, err := db.Exec(ctx, `
		DELETE FROM "GeminiLiveModelConfig"
		WHERE "modelId" = $1
	`, modelId)
	return err
}

func RestoreDefaultGeminiLiveModelAdminConfigs(ctx context.Context, db *pgxpool.Pool) ([]AdminConfig, error) {
	tx, err := db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `DELETE FROM "GeminiLiveModelConfig"`)
	if err != nil {
		return nil, err
	}

	configured := listConfiguredGeminiLiveModels()
	methods := []string{"bidiGenerateContent"}
	for i, m := range configured {
		uuid := "gen_config_" + m.ID
		_, err = tx.Exec(ctx, `
			INSERT INTO "GeminiLiveModelConfig" ("id", "modelId", "displayName", "supportedGenerationMethods", "isEnabled", "sortOrder", "updatedAt")
			VALUES ($1, $2, $3, $4, true, $5, NOW())
		`, uuid, m.ID, m.DisplayName, methods, i)
		if err != nil {
			return nil, err
		}
	}

	err = tx.Commit(ctx)
	if err != nil {
		return nil, err
	}

	return ListGeminiLiveModelAdminConfigs(ctx, db)
}

type GoogleModel struct {
	Name                       string   `json:"name"`
	DisplayName                string   `json:"displayName"`
	SupportedGenerationMethods []string `json:"supportedGenerationMethods"`
}

type GoogleModelsResponse struct {
	Models        []GoogleModel `json:"models"`
	NextPageToken string        `json:"nextPageToken"`
	Error         *struct {
		Message string `json:"message"`
	} `json:"error"`
}

func discoverGoogleLiveModels(ctx context.Context, apiKey string) ([]Model, error) {
	var models []Model
	pageToken := ""

	client := &http.Client{Timeout: 10 * time.Second}

	for {
		urlStr := "https://generativelanguage.googleapis.com/v1beta/models?key=" + apiKey + "&pageSize=1000"
		if pageToken != "" {
			urlStr += "&pageToken=" + pageToken
		}

		req, err := http.NewRequestWithContext(ctx, "GET", urlStr, nil)
		if err != nil {
			return nil, err
		}

		resp, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			var errPayload struct {
				Error struct {
					Message string `json:"message"`
				} `json:"error"`
			}
			_ = json.NewDecoder(resp.Body).Decode(&errPayload)
			return nil, errors.New(errPayload.Error.Message)
		}

		var payload GoogleModelsResponse
		if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
			return nil, err
		}

		if payload.Error != nil {
			return nil, errors.New(payload.Error.Message)
		}

		for _, m := range payload.Models {
			id := normalizeGeminiLiveModelID(m.Name)
			if id == "" {
				continue
			}
			isLive := false
			for _, method := range m.SupportedGenerationMethods {
				if strings.ToLower(method) == "bidigeneratecontent" {
					isLive = true
					break
				}
			}
			if !isLive {
				continue
			}
			dispName := m.DisplayName
			if dispName == "" {
				dispName = titleFromModelID(id)
			}
			models = append(models, Model{
				ID:                         id,
				Name:                       "models/" + id,
				DisplayName:                dispName,
				SupportedGenerationMethods: []string{"bidiGenerateContent"},
			})
		}

		pageToken = payload.NextPageToken
		if pageToken == "" {
			break
		}
	}

	seen := make(map[string]bool)
	var unique []Model
	for _, m := range models {
		if seen[m.ID] {
			continue
		}
		seen[m.ID] = true
		unique = append(unique, m)
	}

	for i := 0; i < len(unique); i++ {
		for j := i + 1; j < len(unique); j++ {
			if strings.Compare(unique[i].DisplayName, unique[j].DisplayName) > 0 {
				unique[i], unique[j] = unique[j], unique[i]
			}
		}
	}

	return unique, nil
}

type SyncResult struct {
	Models          []AdminConfig `json:"models"`
	DiscoveredCount int           `json:"discoveredCount"`
	AddedCount      int           `json:"addedCount"`
}

func SyncGeminiLiveModelsFromGoogle(ctx context.Context, db *pgxpool.Pool, apiKey string) (*SyncResult, error) {
	if apiKey == "" {
		return nil, errors.New("GEMINI_API_KEY is not configured on the server")
	}

	discovered, err := discoverGoogleLiveModels(ctx, apiKey)
	if err != nil {
		return nil, err
	}

	tx, err := db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	rows, err := tx.Query(ctx, `SELECT "modelId", "sortOrder" FROM "GeminiLiveModelConfig"`)
	if err != nil {
		return nil, err
	}
	existing := make(map[string]bool)
	maxSortOrder := -1
	for rows.Next() {
		var mId string
		var sort int
		if err := rows.Scan(&mId, &sort); err == nil {
			existing[mId] = true
			if sort > maxSortOrder {
				maxSortOrder = sort
			}
		}
	}
	rows.Close()

	if len(existing) == 0 {
		configured := listConfiguredGeminiLiveModels()
		methods := []string{"bidiGenerateContent"}
		for i, m := range configured {
			uuid := "gen_config_" + m.ID
			_, err = tx.Exec(ctx, `
				INSERT INTO "GeminiLiveModelConfig" ("id", "modelId", "displayName", "supportedGenerationMethods", "isEnabled", "sortOrder", "updatedAt")
				VALUES ($1, $2, $3, $4, true, $5, NOW())
				ON CONFLICT ("modelId") DO NOTHING
			`, uuid, m.ID, m.DisplayName, methods, i)
			if err != nil {
				return nil, err
			}
			existing[m.ID] = true
			if i > maxSortOrder {
				maxSortOrder = i
			}
		}
	}

	addedCount := 0
	nextSortOrder := maxSortOrder + 1
	methods := []string{"bidiGenerateContent"}
	for _, m := range discovered {
		if existing[m.ID] {
			continue
		}
		uuid := "gen_discover_" + m.ID
		_, err = tx.Exec(ctx, `
			INSERT INTO "GeminiLiveModelConfig" ("id", "modelId", "displayName", "supportedGenerationMethods", "isEnabled", "sortOrder", "updatedAt")
			VALUES ($1, $2, $3, $4, false, $5, NOW())
			ON CONFLICT ("modelId") DO NOTHING
		`, uuid, m.ID, m.DisplayName, methods, nextSortOrder)
		if err != nil {
			return nil, err
		}
		nextSortOrder++
		addedCount++
	}

	err = tx.Commit(ctx)
	if err != nil {
		return nil, err
	}

	adminConfigs, err := ListGeminiLiveModelAdminConfigs(ctx, db)
	if err != nil {
		return nil, err
	}

	return &SyncResult{
		Models:          adminConfigs,
		DiscoveredCount: len(discovered),
		AddedCount:      addedCount,
	}, nil
}

func ResolveAllowedModel(ctx context.Context, db *pgxpool.Pool, modelID string) (*Model, error) {
	normalized := normalizeGeminiLiveModelID(modelID)
	allowed, err := ListAllowedGeminiLiveModels(ctx, db)
	if err != nil {
		return nil, err
	}
	for _, m := range allowed {
		if m.ID == normalized {
			return &m, nil
		}
	}
	return nil, nil
}
