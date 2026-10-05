package main

import (
	"fmt"
	"net/http"
	"time"

	spinhttp "github.com/spinframework/spin-go-sdk/v3/http"
)

func init() {
	spinhttp.Handle(handleTime)
}

// handleTime returns Moscow (UTC+3) wall-clock fields as JSON.
// Spin 4.x scaffold uses Go + componentize-go (not TinyGo wasip1).
// Avoid time.LoadLocation (no tzdata) and map[string]any JSON (TinyGo reflection gaps).
func handleTime(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		fmt.Fprint(w, `{"error":"method not allowed"}`)
		return
	}

	// FixedZone keeps the correct Unix instant while shifting wall-clock to UTC+3.
	// LoadLocation("Europe/Moscow") needs tzdata, which WASM often lacks.
	moscow := time.Now().In(time.FixedZone("Europe/Moscow", 3*60*60))
	body := fmt.Sprintf(
		`{"unix":%d,"iso":%q,"hour_minute":%q,"timezone":"Europe/Moscow","utc_offset":"+03:00"}`,
		moscow.Unix(), moscow.Format(time.RFC3339), moscow.Format("15:04"),
	)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, body)
}

// main must exist for the compiler; Spin invokes the registered handler.
func main() {}
