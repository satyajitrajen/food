// Package httpx holds shared HTTP plumbing: JSON helpers and the uniform
// error envelope { "error": { "code", "message", "request_id" } }.
package httpx

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5/middleware"
)

// AppError is a business error with an HTTP status and stable code.
type AppError struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *AppError) Error() string { return e.Code + ": " + e.Message }

func NewError(status int, code, message string) *AppError {
	return &AppError{Status: status, Code: code, Message: message}
}

var (
	ErrNotFound      = NewError(http.StatusNotFound, "not_found", "Resource not found")
	ErrBadRequest    = NewError(http.StatusBadRequest, "bad_request", "Invalid request body")
	ErrUnauthorized  = NewError(http.StatusUnauthorized, "unauthorized", "Authentication required")
	ErrForbidden     = NewError(http.StatusForbidden, "forbidden", "Insufficient role")
	ErrConflict      = NewError(http.StatusConflict, "conflict", "Conflicting state")
	ErrInvalidAmount = NewError(http.StatusBadRequest, "invalid_amount", "Amount must be greater than zero")
	ErrShortPayment  = NewError(http.StatusBadRequest, "short_payment", "Received amount is less than the grand total")
	ErrTableOccupied = NewError(http.StatusConflict, "table_occupied", "Table already has an active order")
	ErrInvalidState  = NewError(http.StatusConflict, "invalid_state", "Operation not allowed in current state")
)

// JSON writes v as a JSON response with the given status.
func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// ErrorJSON writes the uniform error envelope.
func ErrorJSON(w http.ResponseWriter, r *http.Request, err error) {
	status := http.StatusInternalServerError
	code := "internal_error"
	message := "Internal server error"

	var appErr *AppError
	if errors.As(err, &appErr) {
		status, code, message = appErr.Status, appErr.Code, appErr.Message
	} else {
		// Internal detail (SQL, driver, file paths) goes to the log only.
		slog.Error("internal error", "err", err, "method", r.Method, "path", r.URL.Path,
			"request_id", middleware.GetReqID(r.Context()))
	}

	JSON(w, status, map[string]any{
		"error": map[string]any{
			"code":       code,
			"message":    message,
			"request_id": middleware.GetReqID(r.Context()),
		},
	})
}

// MaxBodyBytes caps JSON request bodies.
const MaxBodyBytes = 1 << 20

// Decode reads and validates a JSON request body (at most MaxBodyBytes,
// unknown fields rejected) into dst.
func Decode(r *http.Request, dst any) error {
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, MaxBodyBytes))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return ErrBadRequest
	}
	return nil
}
