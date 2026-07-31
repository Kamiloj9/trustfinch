package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/kamilojdana/trustfinch/broker/internal/iam"
	"github.com/kamilojdana/trustfinch/broker/internal/issuer"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	context, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	handler, err := loadHandler(context)
	if err != nil {
		logger.Error("initialize IAM enrollment broker", "error", err)
		os.Exit(1)
	}
	lambda.Start(handler.Handle)
}

func loadHandler(ctx context.Context) (*iam.Handler, error) {
	bucket := os.Getenv("IAM_BROKER_CONFIG_BUCKET")
	key := os.Getenv("IAM_BROKER_CONFIG_KEY")
	secretARN := os.Getenv("IAM_BROKER_JWK_SECRET_ARN")
	if bucket == "" || key == "" || secretARN == "" {
		return nil, fmt.Errorf("IAM_BROKER_CONFIG_BUCKET, IAM_BROKER_CONFIG_KEY, and IAM_BROKER_JWK_SECRET_ARN are required")
	}
	awsConfig, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}
	configObject, err := s3.NewFromConfig(awsConfig).GetObject(ctx, &s3.GetObjectInput{Bucket: aws.String(bucket), Key: aws.String(key)})
	if err != nil {
		return nil, fmt.Errorf("read IAM broker configuration: %w", err)
	}
	defer configObject.Body.Close()
	configJSON, err := io.ReadAll(io.LimitReader(configObject.Body, 1024*1024))
	if err != nil {
		return nil, err
	}
	config, err := iam.ParseConfig(configJSON)
	if err != nil {
		return nil, err
	}
	secret, err := secretsmanager.NewFromConfig(awsConfig).GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{SecretId: aws.String(secretARN)})
	if err != nil {
		return nil, fmt.Errorf("read IAM broker signing JWK: %w", err)
	}
	if secret.SecretString == nil {
		return nil, fmt.Errorf("IAM broker JWK secret must use SecretString")
	}
	signingKey, err := issuer.ParseSigningKey([]byte(*secret.SecretString))
	if err != nil {
		return nil, err
	}
	httpClient, err := newHTTPClient(config)
	if err != nil {
		return nil, err
	}
	return iam.NewHandler(config, signingKey, httpClient)
}

func newHTTPClient(config iam.Config) (*http.Client, error) {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	pool, err := x509.SystemCertPool()
	if err != nil || pool == nil {
		pool = x509.NewCertPool()
	}
	if strings.TrimSpace(config.CARootCertificatePEM) != "" && !pool.AppendCertsFromPEM([]byte(config.CARootCertificatePEM)) {
		return nil, fmt.Errorf("IAM broker CA root certificate is invalid")
	}
	transport.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: pool, ServerName: config.CAServerName}
	return &http.Client{Transport: transport, Timeout: 10 * time.Second}, nil
}
