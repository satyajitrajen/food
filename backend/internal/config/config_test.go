package config

import "testing"

func TestDevModeIsOptIn(t *testing.T) {
	t.Setenv("FOODPOS_DEV", "")
	t.Setenv("FOODPOS_ENV", "")
	t.Setenv("FOODPOS_JWT_SECRET", "")
	t.Setenv("FOODPOS_CORS_ORIGINS", "")
	c := Load()
	if c.Dev {
		t.Fatal("dev mode must be off unless FOODPOS_DEV=1")
	}
	if c.JWTSecret != "" {
		t.Fatalf("no default JWT secret outside dev, got %q", c.JWTSecret)
	}
	if err := c.Validate(); err == nil {
		t.Fatal("missing JWT secret must fail validation outside dev")
	}
	if c.CORSOrigins != "" {
		t.Fatalf("CORS must default to off, got %q", c.CORSOrigins)
	}
}

func TestDevModeOptIn(t *testing.T) {
	t.Setenv("FOODPOS_DEV", "1")
	t.Setenv("FOODPOS_ENV", "")
	t.Setenv("FOODPOS_JWT_SECRET", "")
	c := Load()
	if !c.Dev || c.JWTSecret != DevJWTSecret {
		t.Fatalf("FOODPOS_DEV=1 should enable dev with the dev secret: %+v", c.Dev)
	}
	if err := c.Validate(); err != nil {
		t.Fatalf("dev config should validate: %v", err)
	}
}

func TestProductionNeverDev(t *testing.T) {
	t.Setenv("FOODPOS_DEV", "1")
	t.Setenv("FOODPOS_ENV", "production")
	t.Setenv("FOODPOS_JWT_SECRET", DevJWTSecret)
	c := Load()
	if c.Dev {
		t.Fatal("production must ignore FOODPOS_DEV")
	}
	if err := c.Validate(); err == nil {
		t.Fatal("the dev JWT secret must be rejected in production")
	}
	t.Setenv("FOODPOS_JWT_SECRET", "a-long-and-random-production-secret")
	if err := Load().Validate(); err != nil {
		t.Fatalf("strong secret should validate: %v", err)
	}
}
