// Package web embeds the built FoodPOS landing + console site and serves it
// at "/". API/media/ws routes are untouched — this handler only sees requests
// that matched nothing else (chi catch-all), so "/console/..." deep links and
// any marketing route fall back to index.html (SPA).
//
// The embedded files live in webroot/ (gitignored) and are produced by
// `make web` (builds ../landing then copies dist/).
package web

import (
	"embed"
	"io"
	"io/fs"
	"mime"
	"net/http"
	"path/filepath"
	"strings"
)

//go:embed all:webroot
var embedded embed.FS

// Handler serves the static site with an SPA fallback to index.html.
func Handler() http.Handler {
	sub, err := fs.Sub(embedded, "webroot")
	if err != nil {
		panic("web: embedded webroot missing — run `make web` before building: " + err.Error())
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		// Never swallow API/media endpoints with the SPA (unknown subpaths →
		// 404 so API clients still get a clean error).
		if strings.HasPrefix(path, "/api/") || strings.HasPrefix(path, "/media/") ||
			path == "/healthz" || path == "/ws" {
			http.NotFound(w, r)
			return
		}
		name := strings.TrimPrefix(path, "/")
		if name == "" {
			name = "index.html"
		}
		f, err := sub.Open(name)
		if err != nil {
			// SPA fallback for client-side routes (e.g. /console).
			name = "index.html"
			f, err = sub.Open(name)
			if err != nil {
				http.NotFound(w, r)
				return
			}
		}
		defer f.Close()
		body, err := io.ReadAll(f)
		if err != nil {
			http.NotFound(w, r)
			return
		}
		ct := mime.TypeByExtension(filepath.Ext(name))
		if ct == "" {
			ct = "application/octet-stream"
		}
		w.Header().Set("Content-Type", ct)
		_, _ = w.Write(body)
	})
}
