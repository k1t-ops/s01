package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// HealthCheck represents a single health check result
type HealthCheck struct {
	Name    string `json:"name"`
	Status  string `json:"status"`
	Message string `json:"message,omitempty"`
	Value   string `json:"value,omitempty"`
}

// HealthMetrics contains system health metrics
type HealthMetrics struct {
	CPUUsage     float64       `json:"cpu_usage"`
	MemoryUsage  float64       `json:"memory_usage"`
	DiskUsage    float64       `json:"disk_usage"`
	NetworkOk    bool          `json:"network_ok"`
	Checks       []HealthCheck `json:"checks"`
	OverallScore int           `json:"overall_score"`
}

// HostStatus represents the status report from a host
type HostStatus struct {
	ServiceName   string         `json:"service_name"`
	InstanceName  string         `json:"instance_name"`
	IPAddress     string         `json:"ip_address"`
	Status        string         `json:"status"`
	Timestamp     time.Time      `json:"timestamp"`
	ClientCN      string         `json:"client_cn,omitempty"` // Certificate Common Name
	HealthMetrics *HealthMetrics `json:"health_metrics,omitempty"`
}

// HostHistory holds the history of statuses for a specific host
type HostHistory struct {
	ServiceName  string       `json:"service_name"`
	InstanceName string       `json:"instance_name"`
	Statuses     []HostStatus `json:"statuses"`
	LastSeen     time.Time    `json:"last_seen"`
	mutex        sync.RWMutex `json:"-"`
}

// HostHistoryResponse is used for JSON responses to avoid mutex copying
type HostHistoryResponse struct {
	ServiceName  string       `json:"service_name"`
	InstanceName string       `json:"instance_name"`
	Statuses     []HostStatus `json:"statuses"`
	LastSeen     time.Time    `json:"last_seen"`
}

// HostResponse represents a simplified host for public API responses
type HostResponse struct {
	ServiceName   string         `json:"service_name"`
	InstanceName  string         `json:"instance_name"`
	Status        string         `json:"status"`
	IPAddress     string         `json:"ip_address"`
	LastSeen      time.Time      `json:"last_seen"`
	HealthMetrics *HealthMetrics `json:"health_metrics,omitempty"`
	ClientCN      string         `json:"client_cn,omitempty"`
}

type DiscoveryServer struct {
	hosts      map[string]*HostHistory // key: service_name:instance_name
	maxHistory int
	mutex      sync.RWMutex
	logger     *slog.Logger
	config     *Config
	tlsConfig  *tls.Config
}

// Config holds server configuration
type Config struct {
	ServerPort     string
	HealthPort     string
	MaxHistory     int
	StaleTimeout   int // seconds after which a host is considered lost
	CertFile       string
	KeyFile        string
	CACertFile     string
	LogLevel       string
	ReadTimeout    int
	WriteTimeout   int
	RequestTimeout int
}

// StatusRequest represents the incoming status report
type StatusRequest struct {
	ServiceName   string         `json:"service_name"`
	InstanceName  string         `json:"instance_name"`
	Status        string         `json:"status"`
	HealthMetrics *HealthMetrics `json:"health_metrics,omitempty"`
}

// DiscoveryResponse represents the response from discovery queries
type DiscoveryResponse struct {
	Hosts []HostResponse `json:"hosts"`
	Total int            `json:"total"`
}

// NewDiscoveryServer creates a new discovery server instance
func NewDiscoveryServer(config *Config, logger *slog.Logger) (*DiscoveryServer, error) {
	tlsConfig, err := setupTLSConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to setup TLS: %v", err)
	}

	return &DiscoveryServer{
		hosts:      make(map[string]*HostHistory),
		maxHistory: config.MaxHistory,
		logger:     logger,
		config:     config,
		tlsConfig:  tlsConfig,
	}, nil
}

// setupTLSConfig configures mTLS for the server
func setupTLSConfig(config *Config) (*tls.Config, error) {
	// Load server certificate and key
	serverCert, err := tls.LoadX509KeyPair(config.CertFile, config.KeyFile)
	if err != nil {
		return nil, fmt.Errorf("failed to load server certificate: %v", err)
	}

	// Load CA certificate
	caCertPEM, err := os.ReadFile(config.CACertFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read CA certificate: %v", err)
	}

	caCertPool := x509.NewCertPool()
	if !caCertPool.AppendCertsFromPEM(caCertPEM) {
		return nil, fmt.Errorf("failed to parse CA certificate")
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{serverCert},
		ClientAuth:   tls.RequireAndVerifyClientCert,
		ClientCAs:    caCertPool,
		MinVersion:   tls.VersionTLS12,
		CipherSuites: []uint16{
			// HTTP/2 required cipher suites
			tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
			// Additional secure cipher suites
			tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,
			tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,
		},
	}

	return tlsConfig, nil
}

// getClientIP extracts the real client IP address
func getClientIP(r *http.Request) string {
	// Try X-Forwarded-For header first
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.TrimSpace(strings.Split(xff, ",")[0])
	}

	// Try X-Real-IP header
	if xri := r.Header.Get("X-Real-IP"); xri != "" {
		return xri
	}

	// Fall back to RemoteAddr
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return ip
}

// getClientCN extracts the Common Name from client certificate
func getClientCN(r *http.Request) string {
	if r.TLS != nil && len(r.TLS.PeerCertificates) > 0 {
		return r.TLS.PeerCertificates[0].Subject.CommonName
	}
	return ""
}

// parsePathParams extracts path parameters from URL path
func parsePathParams(path, pattern string) map[string]string {
	params := make(map[string]string)

	pathParts := strings.Split(strings.Trim(path, "/"), "/")
	patternParts := strings.Split(strings.Trim(pattern, "/"), "/")

	if len(pathParts) != len(patternParts) {
		return params
	}

	for i, part := range patternParts {
		if strings.HasPrefix(part, "{") && strings.HasSuffix(part, "}") {
			key := part[1 : len(part)-1]
			if i < len(pathParts) {
				params[key] = pathParts[i]
			}
		} else if part != pathParts[i] {
			return make(map[string]string) // Pattern doesn't match
		}
	}

	return params
}

// matchesPattern checks if a path matches a pattern
func matchesPattern(path, pattern string) bool {
	pathParts := strings.Split(strings.Trim(path, "/"), "/")
	patternParts := strings.Split(strings.Trim(pattern, "/"), "/")

	if len(pathParts) != len(patternParts) {
		return false
	}

	for i, part := range patternParts {
		if strings.HasPrefix(part, "{") && strings.HasSuffix(part, "}") {
			continue // Parameter - matches anything
		} else if i >= len(pathParts) || part != pathParts[i] {
			return false
		}
	}

	return true
}

// reportStatus handles incoming status reports from hosts
func (ds *DiscoveryServer) reportStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		ds.logger.Error("Failed to read request body", "error", err)
		http.Error(w, "Failed to read request", http.StatusBadRequest)
		return
	}

	var req StatusRequest
	if err := json.Unmarshal(body, &req); err != nil {
		ds.logger.Error("Failed to decode status request", "error", err)
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Validate required fields
	if req.ServiceName == "" || req.InstanceName == "" || req.Status == "" {
		ds.logger.Error("Missing required fields in status request")
		http.Error(w, "Missing required fields: service_name, instance_name, status", http.StatusBadRequest)
		return
	}

	clientIP := getClientIP(r)
	clientCN := getClientCN(r)

	status := HostStatus{
		ServiceName:   req.ServiceName,
		InstanceName:  req.InstanceName,
		IPAddress:     clientIP,
		Status:        req.Status,
		Timestamp:     time.Now(),
		ClientCN:      clientCN,
		HealthMetrics: req.HealthMetrics,
	}

	ds.addHostStatus(status)

	// Enhanced logging with health metrics
	logFields := []any{
		"service_name", req.ServiceName,
		"instance_name", req.InstanceName,
		"ip_address", clientIP,
		"status", req.Status,
		"client_cn", clientCN,
	}

	// Add health metrics to logs if available
	if req.HealthMetrics != nil {
		logFields = append(logFields,
			"cpu_usage", req.HealthMetrics.CPUUsage,
			"memory_usage", req.HealthMetrics.MemoryUsage,
			"disk_usage", req.HealthMetrics.DiskUsage,
			"network_ok", req.HealthMetrics.NetworkOk,
			"health_score", req.HealthMetrics.OverallScore,
			"health_checks_count", len(req.HealthMetrics.Checks),
		)
	}

	ds.logger.Info("Host status reported", logFields...)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// addHostStatus adds a new status report to the host history
func (ds *DiscoveryServer) addHostStatus(status HostStatus) {
	key := fmt.Sprintf("%s:%s", status.ServiceName, status.InstanceName)

	ds.mutex.Lock()
	defer ds.mutex.Unlock()

	hostHistory, exists := ds.hosts[key]
	if !exists {
		hostHistory = &HostHistory{
			ServiceName:  status.ServiceName,
			InstanceName: status.InstanceName,
			Statuses:     make([]HostStatus, 0, ds.maxHistory),
		}
		ds.hosts[key] = hostHistory
	}

	hostHistory.mutex.Lock()
	defer hostHistory.mutex.Unlock()

	// Add new status
	hostHistory.Statuses = append(hostHistory.Statuses, status)
	hostHistory.LastSeen = status.Timestamp

	// Trim history if needed
	if len(hostHistory.Statuses) > ds.maxHistory {
		copy(hostHistory.Statuses, hostHistory.Statuses[1:])
		hostHistory.Statuses = hostHistory.Statuses[:ds.maxHistory]
	}
}

// getHosts returns all known hosts
func (ds *DiscoveryServer) getHosts(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ds.mutex.RLock()
	defer ds.mutex.RUnlock()

	hosts := make([]HostResponse, 0, len(ds.hosts))
	now := time.Now()
	staleThreshold := time.Duration(ds.config.StaleTimeout) * time.Second

	for _, hostHistory := range ds.hosts {
		hostHistory.mutex.RLock()

		// Get the latest status (most recent)
		var latestStatus HostStatus
		currentStatus := "unknown"
		if len(hostHistory.Statuses) > 0 {
			latestStatus = hostHistory.Statuses[len(hostHistory.Statuses)-1]
			currentStatus = latestStatus.Status
		}

		// Check if host is stale (hasn't reported in staleTimeout seconds)
		if now.Sub(hostHistory.LastSeen) > staleThreshold {
			currentStatus = "lost"
		}

		// Create simplified response with just current status
		hostResponse := HostResponse{
			ServiceName:   hostHistory.ServiceName,
			InstanceName:  hostHistory.InstanceName,
			Status:        currentStatus,
			IPAddress:     latestStatus.IPAddress,
			LastSeen:      hostHistory.LastSeen,
			HealthMetrics: latestStatus.HealthMetrics,
			ClientCN:      latestStatus.ClientCN,
		}

		hostHistory.mutex.RUnlock()
		hosts = append(hosts, hostResponse)
	}

	response := DiscoveryResponse{
		Hosts: hosts,
		Total: len(hosts),
	}

	clientCN := getClientCN(r)
	ds.logger.Info("Hosts discovery request",
		"total_hosts", len(hosts),
		"client_cn", clientCN,
	)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// getHostByName returns a specific host by service_name and instance_name
func (ds *DiscoveryServer) getHostByName(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse path parameters manually
	params := parsePathParams(r.URL.Path, "/api/v1/hosts/{service_name}/{instance_name}")
	serviceName := params["service_name"]
	instanceName := params["instance_name"]

	if serviceName == "" || instanceName == "" {
		http.Error(w, "Missing service_name or instance_name", http.StatusBadRequest)
		return
	}

	key := fmt.Sprintf("%s:%s", serviceName, instanceName)

	ds.mutex.RLock()
	hostHistory, exists := ds.hosts[key]
	ds.mutex.RUnlock()

	if !exists {
		http.Error(w, "Host not found", http.StatusNotFound)
		return
	}

	hostHistory.mutex.RLock()
	historyCopy := HostHistoryResponse{
		ServiceName:  hostHistory.ServiceName,
		InstanceName: hostHistory.InstanceName,
		LastSeen:     hostHistory.LastSeen,
		Statuses:     make([]HostStatus, len(hostHistory.Statuses)),
	}
	copy(historyCopy.Statuses, hostHistory.Statuses)
	hostHistory.mutex.RUnlock()

	clientCN := getClientCN(r)
	ds.logger.Info("Host detail request",
		"service_name", serviceName,
		"instance_name", instanceName,
		"client_cn", clientCN,
	)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(historyCopy)
}

// health provides a health check endpoint
func (ds *DiscoveryServer) health(w http.ResponseWriter, r *http.Request) {
	ds.mutex.RLock()
	totalHosts := len(ds.hosts)
	ds.mutex.RUnlock()

	health := map[string]interface{}{
		"status":      "ok",
		"timestamp":   time.Now(),
		"total_hosts": totalHosts,
		"version":     "1.0.0",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(health)
}

// router handles HTTP routing manually
func (ds *DiscoveryServer) router(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path

	switch {
	case path == "/health":
		ds.health(w, r)
	case path == "/api/v1/report":
		ds.reportStatus(w, r)
	case path == "/api/v1/hosts":
		ds.getHosts(w, r)
	case matchesPattern(path, "/api/v1/hosts/{service_name}/{instance_name}"):
		ds.getHostByName(w, r)
	default:
		http.Error(w, "Not found", http.StatusNotFound)
	}
}

// healthRouter handles health check requests without requiring client certificates
func (ds *DiscoveryServer) healthRouter(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/health" {
		ds.health(w, r)
	} else {
		http.NotFound(w, r)
	}
}

// Start starts the discovery server
func (ds *DiscoveryServer) Start() error {
	// Main mTLS server
	server := &http.Server{
		Addr:         ":" + ds.config.ServerPort,
		Handler:      http.HandlerFunc(ds.router),
		TLSConfig:    ds.tlsConfig,
		ReadTimeout:  time.Duration(ds.config.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(ds.config.WriteTimeout) * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// Health check server (no TLS, no client certs required)
	healthServer := &http.Server{
		Addr:         ":" + ds.config.HealthPort,
		Handler:      http.HandlerFunc(ds.healthRouter),
		ReadTimeout:  time.Duration(ds.config.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(ds.config.WriteTimeout) * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	ds.logger.Info("Starting discovery server with mTLS", "port", ds.config.ServerPort)
	ds.logger.Info("Starting health check server", "port", ds.config.HealthPort)

	// Start main server in goroutine
	go func() {
		if err := server.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
			ds.logger.Error("Failed to start main server", "error", err)
			os.Exit(1)
		}
	}()

	// Start health server in goroutine
	go func() {
		if err := healthServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			ds.logger.Error("Failed to start health server", "error", err)
			os.Exit(1)
		}
	}()

	// Wait for interrupt signal
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	<-c

	ds.logger.Info("Shutting down servers...")

	// Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Shutdown both servers
	var err1, err2 error
	go func() { err1 = server.Shutdown(ctx) }()
	go func() { err2 = healthServer.Shutdown(ctx) }()

	// Wait for both shutdowns to complete
	time.Sleep(1 * time.Second)

	if err1 != nil {
		ds.logger.Error("Main server shutdown error", "error", err1)
		return err1
	}
	if err2 != nil {
		ds.logger.Error("Health server shutdown error", "error", err2)
		return err2
	}

	ds.logger.Info("Servers stopped")
	return nil
}

// getEnv gets an environment variable with a default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvInt gets an environment variable as integer with a default value
func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

// loadConfig loads configuration from environment variables
func loadConfig() (*Config, error) {
	config := &Config{
		ServerPort:     getEnv("SERVER_PORT", "8443"),
		HealthPort:     getEnv("HEALTH_PORT", "8080"),
		MaxHistory:     getEnvInt("MAX_HISTORY", 100),
		StaleTimeout:   getEnvInt("STALE_TIMEOUT", 300), // 5 minutes default
		CertFile:       getEnv("CERT_FILE", "/etc/ssl/certs/server.crt"),
		KeyFile:        getEnv("KEY_FILE", "/etc/ssl/certs/server.key"),
		CACertFile:     getEnv("CA_CERT_FILE", "/etc/ssl/certs/root_ca.crt"),
		LogLevel:       getEnv("LOG_LEVEL", "info"),
		ReadTimeout:    getEnvInt("READ_TIMEOUT", 30),
		WriteTimeout:   getEnvInt("WRITE_TIMEOUT", 30),
		RequestTimeout: getEnvInt("REQUEST_TIMEOUT", 30),
	}

	// Try to read config file if it exists
	configPaths := []string{
		"/etc/discovery/config.json",
		"./config/config.json",
		"./config.json",
	}

	for _, configPath := range configPaths {
		if data, err := os.ReadFile(configPath); err == nil {
			var fileConfig Config
			if err := json.Unmarshal(data, &fileConfig); err == nil {
				// Override defaults with file config, but let env vars take precedence
				if config.ServerPort == "8443" && fileConfig.ServerPort != "" {
					config.ServerPort = fileConfig.ServerPort
				}
				if config.MaxHistory == 100 && fileConfig.MaxHistory != 0 {
					config.MaxHistory = fileConfig.MaxHistory
				}
				// ... continue for other fields as needed
			}
			break
		}
	}

	// Validate required files exist
	for _, file := range []string{config.CertFile, config.KeyFile, config.CACertFile} {
		if _, err := os.Stat(file); os.IsNotExist(err) {
			return nil, fmt.Errorf("required file not found: %s", file)
		}
	}

	return config, nil
}

// setupLogger configures the structured logger
func setupLogger(level string) *slog.Logger {
	var logLevel slog.Level
	switch strings.ToLower(level) {
	case "debug":
		logLevel = slog.LevelDebug
	case "info":
		logLevel = slog.LevelInfo
	case "warn", "warning":
		logLevel = slog.LevelWarn
	case "error":
		logLevel = slog.LevelError
	default:
		logLevel = slog.LevelInfo
	}

	opts := &slog.HandlerOptions{
		Level: logLevel,
	}

	// Use JSON handler for structured logging
	handler := slog.NewJSONHandler(os.Stdout, opts)
	return slog.New(handler)
}

func main() {
	config, err := loadConfig()
	if err != nil {
		fmt.Printf("Failed to load config: %v\n", err)
		os.Exit(1)
	}

	logger := setupLogger(config.LogLevel)

	server, err := NewDiscoveryServer(config, logger)
	if err != nil {
		logger.Error("Failed to create discovery server", "error", err)
		os.Exit(1)
	}

	logger.Info("Discovery server configuration loaded",
		"port", config.ServerPort,
		"max_history", config.MaxHistory,
		"cert_file", filepath.Base(config.CertFile),
		"ca_cert", filepath.Base(config.CACertFile),
	)

	if err := server.Start(); err != nil {
		logger.Error("Server failed to start", "error", err)
		os.Exit(1)
	}
}
