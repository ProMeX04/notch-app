package capabilities

import "context"

// Repository defines the persistence interface for FeatureConfigs overrides.
type Repository interface {
	FindAll(ctx context.Context) ([]FeatureConfig, error)
	FindByKey(ctx context.Context, key string) (*FeatureConfig, error)
	Upsert(ctx context.Context, cfg FeatureConfig) error
}
