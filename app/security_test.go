package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSecurityHeaders_PresentOnAllRoutes(t *testing.T) {
	srv := newTestServer(t)
	routes := []struct {
		method string
		path   string
	}{
		{http.MethodGet, "/health"},
		{http.MethodGet, "/notes"},
		{http.MethodGet, "/metrics"},
	}

	want := map[string]string{
		"X-Content-Type-Options":            "nosniff",
		"X-Frame-Options":                   "DENY",
		"Referrer-Policy":                   "no-referrer",
		"Content-Security-Policy":           "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
		"X-Permitted-Cross-Domain-Policies": "none",
		"Cache-Control":                     "no-store",
		"Cross-Origin-Resource-Policy":      "same-origin",
	}

	for _, rt := range routes {
		t.Run(rt.method+" "+rt.path, func(t *testing.T) {
			req := httptest.NewRequest(rt.method, rt.path, nil)
			rec := httptest.NewRecorder()
			srv.Routes().ServeHTTP(rec, req)
			for k, v := range want {
				if got := rec.Header().Get(k); got != v {
					t.Errorf("%s: got %q, want %q", k, got, v)
				}
			}
		})
	}
}

// TestSecurityHeaders_FailsWithoutMiddleware guards the fix: if SecurityHeaders is
// removed from Routes(), this assertion fails.
func TestSecurityHeaders_FailsWithoutMiddleware(t *testing.T) {
	srv := newTestServer(t)
	// Rebuild a bare mux the same way Routes does, WITHOUT SecurityHeaders.
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", srv.wrap(srv.handleHealth))

	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Header().Get("X-Content-Type-Options") != "" {
		t.Fatal("bare mux unexpectedly has X-Content-Type-Options — test setup wrong")
	}

	rec2 := httptest.NewRecorder()
	srv.Routes().ServeHTTP(rec2, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec2.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatal("Routes() missing SecurityHeaders middleware — X-Content-Type-Options not set")
	}
}
