package capabilities

import (
	"context"
	"testing"
)

type mockRepository struct {
	configs []FeatureConfig
	err     error
}

func (m *mockRepository) FindAll(ctx context.Context) ([]FeatureConfig, error) {
	if m.err != nil {
		return nil, m.err
	}
	return m.configs, nil
}

func (m *mockRepository) FindByKey(ctx context.Context, key string) (*FeatureConfig, error) {
	if m.err != nil {
		return nil, m.err
	}
	for _, c := range m.configs {
		if c.Key == key {
			return &c, nil
		}
	}
	return nil, nil
}

func (m *mockRepository) Upsert(ctx context.Context, cfg FeatureConfig) error {
	if m.err != nil {
		return m.err
	}
	for i, c := range m.configs {
		if c.Key == cfg.Key {
			m.configs[i] = cfg
			return nil
		}
	}
	m.configs = append(m.configs, cfg)
	return nil
}

func TestMergeDefaultFeatureConfigs(t *testing.T) {
	// Overriding one capability key
	dbConfigs := []FeatureConfig{
		{
			Key:       "talk_connection",
			Name:      "Gemini Live (Custom)",
			IsProOnly: false, // Override to free!
			IsEnabled: true,
		},
		{
			Key:       "focus_pomodoro",
			Name:      "Focus Pomodoro",
			IsProOnly: false,
			IsEnabled: false, // Override to disabled!
		},
	}

	merged := MergeDefaultFeatureConfigs(dbConfigs)

	var talkConnFound, focusPomFound bool
	for _, cfg := range merged {
		if cfg.Key == "talk_connection" {
			talkConnFound = true
			if cfg.IsProOnly {
				t.Error("expected talk_connection override to be free (IsProOnly = false)")
			}
			if cfg.Name != "Gemini Live (Custom)" {
				t.Errorf("expected custom name, got %q", cfg.Name)
			}
		}
		if cfg.Key == "focus_pomodoro" {
			focusPomFound = true
			if cfg.IsEnabled {
				t.Error("expected focus_pomodoro override to be disabled (IsEnabled = false)")
			}
		}
	}

	if !talkConnFound {
		t.Error("expected talk_connection in merged list")
	}
	if !focusPomFound {
		t.Error("expected focus_pomodoro in merged list")
	}
}

func TestGetUserPermissionPolicy(t *testing.T) {
	repo := &mockRepository{
		configs: []FeatureConfig{
			{
				Key:       "talk_connection",
				Name:      "Gemini Live",
				IsProOnly: true,
				IsEnabled: true,
			},
			{
				Key:       "focus_pomodoro",
				Name:      "Focus Pomodoro",
				IsProOnly: false,
				IsEnabled: true,
			},
			{
				Key:       "panel_shelf",
				Name:      "Shelf",
				IsProOnly: true,
				IsEnabled: false, // Disabled for everyone
			},
		},
	}

	ctx := context.Background()

	// Pro User
	proPolicy, err := GetUserPermissionPolicy(ctx, repo, true)
	if err != nil {
		t.Fatalf("failed to get user policy: %v", err)
	}

	if !proPolicy.Features["talk_connection"] {
		t.Error("expected pro user to have talk_connection enabled")
	}
	if !proPolicy.Features["focus_pomodoro"] {
		t.Error("expected pro user to have focus_pomodoro enabled")
	}
	if proPolicy.Features["panel_shelf"] {
		t.Error("expected panel_shelf to be false even for pro user because it is disabled in DB")
	}

	// Free User
	freePolicy, err := GetUserPermissionPolicy(ctx, repo, false)
	if err != nil {
		t.Fatalf("failed to get user policy: %v", err)
	}

	if freePolicy.Features["talk_connection"] {
		t.Error("expected free user to NOT have talk_connection enabled")
	}
	if !freePolicy.Features["focus_pomodoro"] {
		t.Error("expected free user to have focus_pomodoro enabled")
	}
	if freePolicy.Features["panel_shelf"] {
		t.Error("expected panel_shelf to be false for free user")
	}
}
