package capabilities

import "time"

// FeatureRequirement represents the resolved access requirement tier.
type FeatureRequirement string

const (
	FeatureRequirementDisabled FeatureRequirement = "disabled"
	FeatureRequirementFree     FeatureRequirement = "free"
	FeatureRequirementPro      FeatureRequirement = "pro"
)

// FeatureConfig represents a remote database entry override.
type FeatureConfig struct {
	ID          string    `json:"id"`
	Key         string    `json:"key"`
	Name        string    `json:"name"`
	Description *string   `json:"description"`
	IsProOnly   bool      `json:"isProOnly"`
	IsEnabled   bool      `json:"isEnabled"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

// CapabilityDeclaration maps the static default capabilities configuration.
type CapabilityDeclaration struct {
	Key         string             `json:"key"`
	Name        string             `json:"name"`
	Description string             `json:"description"`
	Requirement FeatureRequirement `json:"requirement"`
}

// CapabilitiesManifest maps the outer structure of the default capabilities JSON.
type CapabilitiesManifest struct {
	Version      int                     `json:"version"`
	Capabilities []CapabilityDeclaration `json:"capabilities"`
}

// RemotePolicyResponse matches the GET /api/capabilities schema.
type RemotePolicyResponse struct {
	Version   int                           `json:"version"`
	Features  map[string]FeatureRequirement `json:"features"`
	UpdatedAt time.Time                     `json:"updated_at"`
}

// PermissionPolicy contains the user-specific feature entitlement gating.
type PermissionPolicy struct {
	Features map[string]bool `json:"features"`
}
