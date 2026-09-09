package api

// Menu photo upload. Photos are written to the local upload dir (configured
// via FOODPOS_UPLOAD_DIR, default ./uploads) and served back under the public
// /media/* static route. The handler only stores the file and returns its URL
// — persisting image_url on the menu item still goes through the normal
// manager-gated PATCH /menu/{id} (offline-first outbox) so conflicts stay
// consistent.

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"foodpos/backend/internal/httpx"
	"foodpos/backend/internal/store"
)

var imageExts = map[string]string{
	"image/jpeg": ".jpg",
	"image/png":  ".png",
	"image/webp": ".webp",
	"image/gif":  ".gif",
}

const maxImageBytes = 5 << 20 // 5 MB

func (s *Server) handleUploadMenuImage(w http.ResponseWriter, r *http.Request) {
	if s.UploadDir == "" {
		httpx.ErrorJSON(w, r, httpx.NewError(503, "uploads_disabled", "Server uploads are not configured"))
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxImageBytes+1<<20)
	if err := r.ParseMultipartForm(maxImageBytes + 1<<20); err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "bad_upload", "Expected a multipart form with a file field named 'file'"))
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "bad_upload", "Missing file field 'file'"))
		return
	}
	defer file.Close()

	contentType := strings.ToLower(header.Header.Get("Content-Type"))
	ext, ok := imageExts[strings.TrimSpace(strings.Split(contentType, ";")[0])]
	if !ok {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "bad_type", "Only JPEG, PNG, WebP or GIF images are allowed"))
		return
	}

	data, err := io.ReadAll(io.LimitReader(file, maxImageBytes))
	if err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "read_failed", "Could not read the uploaded file"))
		return
	}
	if len(data) == 0 {
		httpx.ErrorJSON(w, r, httpx.NewError(400, "empty_file", "Uploaded file is empty"))
		return
	}

	dir := filepath.Join(s.UploadDir, "menu")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(500, "upload_failed", "Could not create the upload directory"))
		return
	}
	name := store.NewID("menu") + ext
	if err := os.WriteFile(filepath.Join(dir, name), data, 0o644); err != nil {
		httpx.ErrorJSON(w, r, httpx.NewError(500, "upload_failed", "Could not store the image"))
		return
	}

	imageURL := "/media/menu/" + name
	httpx.JSON(w, http.StatusOK, map[string]any{"image_url": imageURL})
}
