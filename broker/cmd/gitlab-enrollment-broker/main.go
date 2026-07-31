package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/trustfinch/trustfinch/broker/internal/enrollment"
)

func main() {
	var configPath string
	var listenAddress string
	var jwkPath string
	var caRootPath string
	var replayStoreType string

	flag.StringVar(&configPath, "config", envOr("BROKER_CONFIG", "/etc/gitlab-enrollment-broker/config.json"), "broker configuration path")
	flag.StringVar(&listenAddress, "listen", envOr("BROKER_LISTEN_ADDRESS", ":8080"), "HTTP listen address")
	flag.StringVar(&jwkPath, "jwk", envOr("BROKER_JWK_PATH", "/run/secrets/broker-jwk.json"), "private JWK path")
	flag.StringVar(&caRootPath, "ca-root", envOr("BROKER_CA_ROOT_PATH", "/etc/step-ca/certs/root_ca.crt"), "step-ca root certificate path")
	flag.StringVar(&replayStoreType, "replay-store", envOr("BROKER_REPLAY_STORE", "dynamodb"), "replay store: dynamodb or memory")
	flag.Parse()

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	config, err := enrollment.LoadConfig(configPath)
	if err != nil {
		logger.Error("invalid broker configuration", "error", err)
		os.Exit(1)
	}
	privateKey, err := enrollment.LoadECPrivateJWK(jwkPath)
	if err != nil {
		logger.Error("invalid broker private JWK", "error", err)
		os.Exit(1)
	}

	transport := http.DefaultTransport.(*http.Transport).Clone()
	if caRootPath != "" {
		pem, err := os.ReadFile(caRootPath)
		if err != nil {
			logger.Error("read step-ca root certificate", "error", err)
			os.Exit(1)
		}
		pool, err := x509.SystemCertPool()
		if err != nil || pool == nil {
			pool = x509.NewCertPool()
		}
		if !pool.AppendCertsFromPEM(pem) {
			logger.Error("parse step-ca root certificate")
			os.Exit(1)
		}
		transport.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: pool, ServerName: config.CAServerName}
	}
	httpClient := &http.Client{Transport: transport, Timeout: 10 * time.Second}

	var replayStore enrollment.ReplayStore
	switch replayStoreType {
	case "memory":
		replayStore = enrollment.NewMemoryReplayStore()
	case "dynamodb":
		replayStore, err = enrollment.NewDynamoDBReplayStore(context.Background(), config.ReplayTableName)
		if err != nil {
			logger.Error("create DynamoDB replay store", "error", err)
			os.Exit(1)
		}
	default:
		logger.Error("unsupported replay store", "replay_store", replayStoreType)
		os.Exit(1)
	}

	server, err := enrollment.NewServer(config, privateKey, replayStore, httpClient, logger)
	if err != nil {
		logger.Error("create enrollment broker", "error", err)
		os.Exit(1)
	}

	httpServer := &http.Server{
		Addr:              listenAddress,
		Handler:           server.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	go func() {
		logger.Info("GitLab enrollment broker listening", "address", listenAddress)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("broker server failed", "error", err)
			os.Exit(1)
		}
	}()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)
	<-signals
	shutdownContext, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(shutdownContext); err != nil {
		fmt.Fprintf(os.Stderr, "broker shutdown: %v\n", err)
		os.Exit(1)
	}
}

func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
