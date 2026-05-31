package capabilities

import (
	"context"
	"crypto/rand"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PgxRepository struct {
	db *pgxpool.Pool
}

func NewPgxRepository(db *pgxpool.Pool) *PgxRepository {
	return &PgxRepository{db: db}
}

func (r *PgxRepository) FindAll(ctx context.Context) ([]FeatureConfig, error) {
	if r == nil || r.db == nil {
		return nil, pgx.ErrNoRows
	}
	rows, err := r.db.Query(ctx, `
		SELECT "id", "key", "name", "description", "isProOnly", "isEnabled", "updatedAt"
		FROM "FeatureConfig"
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []FeatureConfig
	for rows.Next() {
		var c FeatureConfig
		err := rows.Scan(&c.ID, &c.Key, &c.Name, &c.Description, &c.IsProOnly, &c.IsEnabled, &c.UpdatedAt)
		if err != nil {
			return nil, err
		}
		list = append(list, c)
	}
	return list, nil
}

func (r *PgxRepository) FindByKey(ctx context.Context, key string) (*FeatureConfig, error) {
	if r == nil || r.db == nil {
		return nil, pgx.ErrNoRows
	}
	var c FeatureConfig
	err := r.db.QueryRow(ctx, `
		SELECT "id", "key", "name", "description", "isProOnly", "isEnabled", "updatedAt"
		FROM "FeatureConfig"
		WHERE "key" = $1
		LIMIT 1
	`, key).Scan(&c.ID, &c.Key, &c.Name, &c.Description, &c.IsProOnly, &c.IsEnabled, &c.UpdatedAt)
	if err == pgx.ErrNoRows {
		return nil, nil
	} else if err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *PgxRepository) Upsert(ctx context.Context, c FeatureConfig) error {
	if r == nil || r.db == nil {
		return pgx.ErrNoRows
	}
	_, err := r.db.Exec(ctx, `
		INSERT INTO "FeatureConfig" ("id", "key", "name", "description", "isProOnly", "isEnabled", "updatedAt")
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
		ON CONFLICT ("key")
		DO UPDATE SET
			"name" = EXCLUDED."name",
			"description" = EXCLUDED."description",
			"isProOnly" = EXCLUDED."isProOnly",
			"isEnabled" = EXCLUDED."isEnabled",
			"updatedAt" = NOW()
	`, c.ID, c.Key, c.Name, c.Description, c.IsProOnly, c.IsEnabled)
	return err
}

// MergeDefaultFeatureConfigs merges DB overrides with manifest defaults.
func MergeDefaultFeatureConfigs(dbConfigs []FeatureConfig) []FeatureConfig {
	manifest := GetDefaultManifest()
	mergedMap := make(map[string]FeatureConfig)

	// Load defaults from manifest
	for _, capDecl := range manifest.Capabilities {
		isProOnly := capDecl.Requirement == FeatureRequirementPro
		isEnabled := capDecl.Requirement != FeatureRequirementDisabled
		desc := capDecl.Description

		mergedMap[capDecl.Key] = FeatureConfig{
			ID:          "",
			Key:         capDecl.Key,
			Name:        capDecl.Name,
			Description: &desc,
			IsProOnly:   isProOnly,
			IsEnabled:   isEnabled,
			UpdatedAt:   time.Now(),
		}
	}

	// Overwrite with DB configs
	for _, dbCfg := range dbConfigs {
		mergedMap[dbCfg.Key] = dbCfg
	}

	// Convert to slice
	result := make([]FeatureConfig, 0, len(mergedMap))
	for _, v := range mergedMap {
		result = append(result, v)
	}

	// Sort alphabetically by name
	sort.Slice(result, func(i, j int) bool {
		return result[i].Name < result[j].Name
	})

	return result
}

// GetRemotePermissionPolicy returns capabilities mapped to free/pro/disabled requirements.
func GetRemotePermissionPolicy(ctx context.Context, repo Repository) (*RemotePolicyResponse, error) {
	dbConfigs, err := repo.FindAll(ctx)
	if err != nil {
		return nil, err
	}

	merged := MergeDefaultFeatureConfigs(dbConfigs)
	features := make(map[string]FeatureRequirement)

	for _, cfg := range merged {
		if !cfg.IsEnabled {
			features[cfg.Key] = FeatureRequirementDisabled
		} else if cfg.IsProOnly {
			features[cfg.Key] = FeatureRequirementPro
		} else {
			features[cfg.Key] = FeatureRequirementFree
		}
	}

	return &RemotePolicyResponse{
		Version:   1,
		Features:  features,
		UpdatedAt: time.Now(),
	}, nil
}

// GetUserPermissionPolicy resolves boolean entitlement mapping for a user based on Pro status.
func GetUserPermissionPolicy(ctx context.Context, repo Repository, isPro bool) (PermissionPolicy, error) {
	policy, err := GetRemotePermissionPolicy(ctx, repo)
	if err != nil {
		return PermissionPolicy{Features: map[string]bool{}}, err
	}

	featuresMap := make(map[string]bool)
	for key, req := range policy.Features {
		switch req {
		case FeatureRequirementFree:
			featuresMap[key] = true
		case FeatureRequirementPro:
			featuresMap[key] = isPro
		case FeatureRequirementDisabled:
			featuresMap[key] = false
		}
	}

	return PermissionPolicy{Features: featuresMap}, nil
}

// RestoreDefaultCapabilities restores all configurations to manifest defaults inside a transaction.
func RestoreDefaultCapabilities(ctx context.Context, dbPool *pgxpool.Pool) ([]FeatureConfig, error) {
	manifest := GetDefaultManifest()
	var defaultKeys []string
	for _, capDecl := range manifest.Capabilities {
		defaultKeys = append(defaultKeys, capDecl.Key)
	}

	tx, err := dbPool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Delete custom configs not in manifest
	if len(defaultKeys) > 0 {
		var placeholders []string
		var args []any
		for i, k := range defaultKeys {
			placeholders = append(placeholders, fmt.Sprintf("$%d", i+1))
			args = append(args, k)
		}
		query := fmt.Sprintf(`DELETE FROM "FeatureConfig" WHERE "key" NOT IN (%s)`, strings.Join(placeholders, ","))
		_, err = tx.Exec(ctx, query, args...)
		if err != nil {
			return nil, err
		}
	} else {
		_, err = tx.Exec(ctx, `DELETE FROM "FeatureConfig"`)
		if err != nil {
			return nil, err
		}
	}

	// Upsert manifest defaults
	for _, capDecl := range manifest.Capabilities {
		isProOnly := capDecl.Requirement == FeatureRequirementPro
		isEnabled := capDecl.Requirement != FeatureRequirementDisabled
		desc := capDecl.Description
		uuid := generateRandomString(24)

		_, err = tx.Exec(ctx, `
			INSERT INTO "FeatureConfig" ("id", "key", "name", "description", "isProOnly", "isEnabled", "updatedAt")
			VALUES ($1, $2, $3, $4, $5, $6, NOW())
			ON CONFLICT ("key")
			DO UPDATE SET
				"name" = EXCLUDED."name",
				"description" = EXCLUDED."description",
				"isProOnly" = EXCLUDED."isProOnly",
				"isEnabled" = EXCLUDED."isEnabled",
				"updatedAt" = NOW()
		`, uuid, capDecl.Key, capDecl.Name, &desc, isProOnly, isEnabled)
		if err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	// Return restored list
	repo := NewPgxRepository(dbPool)
	dbConfigs, err := repo.FindAll(ctx)
	if err != nil {
		return nil, err
	}

	return MergeDefaultFeatureConfigs(dbConfigs), nil
}

func generateRandomString(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	const letters = "abcdefghijklmnopqrstuvwxyz0123456789"
	var sb strings.Builder
	for _, bVal := range b {
		sb.WriteByte(letters[int(bVal)%len(letters)])
	}
	return sb.String()
}
