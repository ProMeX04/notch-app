package httpjson

import (
	"encoding/json"
	"net/http"
)

type ErrorResponse struct {
	Error  string `json:"error,omitempty"`
	Detail string `json:"detail,omitempty"`
}

func JSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func Error(w http.ResponseWriter, status int, message string) {
	JSON(w, status, ErrorResponse{Error: message})
}

func Detail(w http.ResponseWriter, status int, message string) {
	JSON(w, status, ErrorResponse{Detail: message})
}
