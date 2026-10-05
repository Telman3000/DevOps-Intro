package main

import "net/http"

// SecurityHeaders wraps next and sets baseline HTTP security headers on every response.
// Applied once at the router edge so handlers never need to set these individually.
func SecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
		// API-only app: no HTML/JS assets, so the strictest CSP is correct.
		h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'; base-uri 'none'")
		h.Set("X-Permitted-Cross-Domain-Policies", "none")
		// Spectre / site-isolation baselines for an API that never embeds third-party content.
		h.Set("Cross-Origin-Opener-Policy", "same-origin")
		h.Set("Cross-Origin-Resource-Policy", "same-origin")
		h.Set("Cross-Origin-Embedder-Policy", "require-corp")
		// JSON API responses must not be cached by shared caches/browsers.
		h.Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}
