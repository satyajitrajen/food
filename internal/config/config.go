// Package config loads server configuration from the environment.
package config

import (
	"os"
	"strconv"
)

type Config struct {
	Port      string
	DSN       string
	JWTSecret string
	Seed      bool
	BcryptCost int
}

func Load() Config {
	return Config{
		Port:       env("FOODPOS_PORT", "8080"),
		DSN:       env("FOODPOS_DSN", ""),
		JWTSecret:  env("FOODPOS_JWT_SECRET", "dev-secret-change-me"),
		Seed:       env("FOODPOS_SEED", "0") == "1",
		BcryptCost: envInt("FOODPOS_BCRYPT_COST", 10),
	}
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
