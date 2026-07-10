package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

//go:embed static/index.html
var staticFiles embed.FS

type SecretDef struct {
	Name            string     `json:"name"`
	Label           string     `json:"label"`
	Description     string     `json:"description"`
	Link            string     `json:"link,omitempty"`
	Regex           string     `json:"regex,omitempty"`
	Validator       *Validator `json:"validator,omitempty"`
	RestartServices []string   `json:"restart_services,omitempty"`
}

type Validator struct {
	URL          string `json:"url"`
	Header       string `json:"header"`
	HeaderPrefix string `json:"header_prefix,omitempty"`
	Method       string `json:"method,omitempty"`
	ExpectStatus int    `json:"expect_status,omitempty"`
}

type SecretStatus struct {
	SecretDef
	Exists bool `json:"exists"`
}

var (
	credStore       string
	systemdCredsBin string
	systemctlBin    string
	secrets         []SecretDef
	httpClient      = &http.Client{Timeout: 8 * time.Second}
)

func main() {
	credStore = env("CRED_STORE", "/var/lib/credstore.encrypted")
	systemdCredsBin = env("SYSTEMD_CREDS_BIN", "systemd-creds")
	systemctlBin = env("SYSTEMCTL_BIN", "systemctl")
	configPath := env("SECRETS_CONFIG", "/etc/secrets-portal/secrets.json")
	listenAddr := env("LISTEN_ADDR", "unix:/run/secrets-portal/secrets-portal.sock")

	data, err := os.ReadFile(configPath)
	if err != nil {
		log.Fatalf("secrets-portal: cannot read config %s: %v", configPath, err)
	}
	if err := json.Unmarshal(data, &secrets); err != nil {
		log.Fatalf("secrets-portal: cannot parse config: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", serveIndex)
	mux.HandleFunc("GET /api/secrets", handleList)
	mux.HandleFunc("POST /api/validate", handleValidate)
	mux.HandleFunc("POST /api/seal", handleSeal)

	var ln net.Listener
	if strings.HasPrefix(listenAddr, "unix:") {
		sockPath := strings.TrimPrefix(listenAddr, "unix:")
		os.Remove(sockPath)
		ln, err = net.Listen("unix", sockPath)
		if err != nil {
			log.Fatalf("secrets-portal: cannot listen on %s: %v", listenAddr, err)
		}
		log.Printf("secrets-portal listening on unix:%s (%d secrets)", sockPath, len(secrets))
	} else {
		ln, err = net.Listen("tcp", listenAddr)
		if err != nil {
			log.Fatalf("secrets-portal: cannot listen on %s: %v", listenAddr, err)
		}
		log.Printf("secrets-portal listening on tcp:%s (%d secrets)", listenAddr, len(secrets))
	}

	if err := http.Serve(ln, mux); err != nil {
		log.Fatalf("secrets-portal: server error: %v", err)
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func serveIndex(w http.ResponseWriter, r *http.Request) {
	f, err := staticFiles.Open("static/index.html")
	if err != nil {
		http.Error(w, "internal error", 500)
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	io.Copy(w, f)
}

func handleList(w http.ResponseWriter, r *http.Request) {
	statuses := make([]SecretStatus, 0, len(secrets))
	for _, s := range secrets {
		_, err := os.Stat(fmt.Sprintf("%s/%s.cred", credStore, s.Name))
		statuses = append(statuses, SecretStatus{
			SecretDef: s,
			Exists:    err == nil,
		})
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(statuses)
}

type sealRequest struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

type validateResponse struct {
	Valid   bool   `json:"valid"`
	Message string `json:"message"`
}

type sealResponse struct {
	Success   bool     `json:"success"`
	Restarted []string `json:"restarted,omitempty"`
	Message   string   `json:"message,omitempty"`
}

// checkValidator runs the HTTP API check for a secret. Returns (valid, message).
func checkValidator(def *SecretDef, value string) (bool, string) {
	if def.Validator == nil {
		return true, "OK"
	}
	method := def.Validator.Method
	if method == "" {
		method = "GET"
	}
	apiReq, err := http.NewRequest(method, def.Validator.URL, nil)
	if err != nil {
		return false, "Validator-Konfigurationsfehler"
	}
	apiReq.Header.Set(def.Validator.Header, def.Validator.HeaderPrefix+value)
	apiReq.Header.Set("User-Agent", "secrets-portal/1.0")

	resp, err := httpClient.Do(apiReq)
	if err != nil {
		return false, "API nicht erreichbar"
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)

	expect := def.Validator.ExpectStatus
	if expect == 0 {
		expect = 200
	}
	if resp.StatusCode != expect && resp.StatusCode != 201 && resp.StatusCode != 202 {
		return false, fmt.Sprintf("API abgelehnt (HTTP %d)", resp.StatusCode)
	}
	return true, "OK"
}

func handleValidate(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var req sealRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", 400)
		return
	}
	def := findSecret(req.Name)
	if def == nil {
		http.Error(w, "unknown secret", 404)
		return
	}
	valid, msg := checkValidator(def, req.Value)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(validateResponse{Valid: valid, Message: msg})
}

func handleSeal(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var req sealRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", 400)
		return
	}
	def := findSecret(req.Name)
	if def == nil {
		http.Error(w, "unknown secret", 404)
		return
	}

	// Step 1: validate against real API
	if valid, msg := checkValidator(def, req.Value); !valid {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnprocessableEntity)
		json.NewEncoder(w).Encode(sealResponse{Success: false, Message: msg})
		return
	}

	// Step 2: encrypt with systemd-creds
	credPath := fmt.Sprintf("%s/%s.cred", credStore, def.Name)
	cmd := exec.Command(systemdCredsBin, "encrypt", "--name="+def.Name, "-", credPath)
	cmd.Stdin = strings.NewReader(req.Value)
	out, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("seal failed for %s: %v — %s", def.Name, err, out)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(sealResponse{Success: false, Message: "systemd-creds encrypt fehlgeschlagen"})
		return
	}

	// Step 3: verify credential file exists and has content
	info, err := os.Stat(credPath)
	if err != nil || info.Size() == 0 {
		log.Printf("seal verify failed for %s: stat=%v size=%d", def.Name, err, info.Size())
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(sealResponse{Success: false, Message: "Credential-Datei fehlt nach encrypt"})
		return
	}
	log.Printf("sealed: %s → %s (%d bytes)", def.Name, credPath, info.Size())

	// Step 4: restart associated services
	var restarted []string
	for _, svc := range def.RestartServices {
		if out, err := exec.Command(systemctlBin, "restart", svc).CombinedOutput(); err != nil {
			log.Printf("restart failed for %s: %v — %s", svc, err, out)
		} else {
			log.Printf("restarted: %s", svc)
			restarted = append(restarted, svc)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sealResponse{Success: true, Restarted: restarted})
}

func findSecret(name string) *SecretDef {
	for i := range secrets {
		if secrets[i].Name == name {
			return &secrets[i]
		}
	}
	return nil
}
