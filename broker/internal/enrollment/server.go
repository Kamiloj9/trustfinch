package enrollment

import (
	"bytes"
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/go-jose/go-jose/v4"
)

const enrollmentPath = "/1.0/enroll/gitlab"

type Server struct {
	config      Config
	brokerKey   brokerKey
	replayStore ReplayStore
	httpClient  *http.Client
	logger      *slog.Logger
	now         func() time.Time

	keysMu        sync.RWMutex
	keys          map[string]*rsa.PublicKey
	keysFetchedAt time.Time
}

type enrollmentRequest struct {
	CSR string `json:"csr"`
}

func NewServer(config Config, privateKey brokerKey, replayStore ReplayStore, httpClient *http.Client, logger *slog.Logger) (*Server, error) {
	if err := config.Validate(); err != nil {
		return nil, err
	}
	if privateKey.PrivateKey == nil || privateKey.KeyID == "" {
		return nil, fmt.Errorf("broker private key is required")
	}
	if replayStore == nil || httpClient == nil || logger == nil {
		return nil, fmt.Errorf("broker dependencies are required")
	}
	return &Server{
		config: config, brokerKey: privateKey, replayStore: replayStore, httpClient: httpClient,
		logger: logger, now: time.Now, keys: map[string]*rsa.PublicKey{},
	}, nil
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(writer http.ResponseWriter, _ *http.Request) { writer.WriteHeader(http.StatusOK) })
	mux.HandleFunc("POST "+enrollmentPath, s.enroll)
	return securityHeaders(mux)
}

func (s *Server) enroll(writer http.ResponseWriter, request *http.Request) {
	request.Body = http.MaxBytesReader(writer, request.Body, 1024*1024)
	defer request.Body.Close()
	token, err := bearerToken(request.Header.Get("Authorization"))
	if err != nil {
		s.unauthorized(writer)
		return
	}
	var body enrollmentRequest
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&body); err != nil || body.CSR == "" {
		http.Error(writer, "invalid certificate request", http.StatusBadRequest)
		return
	}
	if err := ensureEOF(decoder); err != nil {
		http.Error(writer, "invalid certificate request", http.StatusBadRequest)
		return
	}

	claims, err := s.validateGitLabToken(request.Context(), token)
	if err != nil {
		s.logger.Warn("rejected GitLab token", "reason", err.Error())
		s.unauthorized(writer)
		return
	}
	identity, err := selectGitLabIdentity(claims, s.config.Identities)
	if err != nil {
		s.logger.Warn("rejected GitLab identity", "project_id", claims.ProjectID, "project_path", claims.ProjectPath, "ref", claims.Ref)
		s.unauthorized(writer)
		return
	}
	csr, err := parseApprovedCSR(body.CSR, identity)
	if err != nil {
		http.Error(writer, "certificate request does not match the approved identity", http.StatusForbidden)
		return
	}

	release, err := s.replayStore.Claim(request.Context(), claims.ID, time.Unix(claims.ExpiresAt, 0))
	if err != nil {
		if errors.Is(err, ErrReplay) {
			http.Error(writer, "GitLab token has already been used", http.StatusConflict)
			return
		}
		s.logger.Error("record GitLab token replay guard", "error", err)
		http.Error(writer, "enrollment temporarily unavailable", http.StatusServiceUnavailable)
		return
	}
	successful := false
	defer func() { release(request.Context(), successful) }()

	ott, err := signBrokerJWT(s.brokerKey, s.config.BrokerProvisionerName, identity.Subject, s.config.CASignAudience, csrFingerprint(csr.Raw), []string{identity.URISAN}, s.now())
	if err != nil {
		s.logger.Error("create CA authorization token", "error", err)
		http.Error(writer, "enrollment temporarily unavailable", http.StatusServiceUnavailable)
		return
	}
	response, status, err := s.requestCertificate(request.Context(), body.CSR, ott)
	if err != nil {
		s.logger.Error("step-ca signing request failed", "error", err)
		http.Error(writer, "certificate authority unavailable", http.StatusBadGateway)
		return
	}
	if status != http.StatusCreated {
		s.logger.Error("step-ca rejected broker authorization", "status", status)
		http.Error(writer, "certificate authority rejected enrollment", http.StatusBadGateway)
		return
	}
	successful = true
	writer.Header().Set("Cache-Control", "no-store")
	writer.Header().Set("Content-Type", "application/json")
	writer.WriteHeader(http.StatusCreated)
	_, _ = writer.Write(response)
}

func (s *Server) validateGitLabToken(ctx context.Context, token string) (gitLabClaims, error) {
	kid, err := parseJWTHeader(token)
	if err != nil {
		return gitLabClaims{}, err
	}
	key, err := s.getGitLabKey(ctx, kid)
	if err != nil {
		return gitLabClaims{}, err
	}
	return verifyGitLabJWT(token, key, s.config.Issuer, s.now(), s.config.MaxGitLabTokenLifetime.Duration)
}

func (s *Server) getGitLabKey(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	s.keysMu.RLock()
	key := s.keys[kid]
	fetchedAt := s.keysFetchedAt
	s.keysMu.RUnlock()
	if key != nil && s.now().Sub(fetchedAt) < 5*time.Minute {
		return key, nil
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, s.config.DiscoveryURL, nil)
	if err != nil {
		return nil, err
	}
	response, err := s.httpClient.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("OIDC discovery returned %d", response.StatusCode)
	}
	var discovery discoveryDocument
	if err := json.NewDecoder(io.LimitReader(response.Body, 1024*1024)).Decode(&discovery); err != nil {
		return nil, err
	}
	if discovery.Issuer != s.config.Issuer || discovery.JWKSURL == "" {
		return nil, fmt.Errorf("OIDC discovery does not match configured issuer")
	}
	keysRequest, err := http.NewRequestWithContext(ctx, http.MethodGet, discovery.JWKSURL, nil)
	if err != nil {
		return nil, err
	}
	keysResponse, err := s.httpClient.Do(keysRequest)
	if err != nil {
		return nil, err
	}
	defer keysResponse.Body.Close()
	if keysResponse.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("OIDC JWKS returned %d", keysResponse.StatusCode)
	}
	var set jose.JSONWebKeySet
	if err := json.NewDecoder(io.LimitReader(keysResponse.Body, 1024*1024)).Decode(&set); err != nil {
		return nil, err
	}
	loaded := map[string]*rsa.PublicKey{}
	for _, candidate := range set.Keys {
		publicKey, ok := candidate.Key.(*rsa.PublicKey)
		if ok && candidate.KeyID != "" && candidate.Valid() {
			loaded[candidate.KeyID] = publicKey
		}
	}
	if len(loaded) == 0 {
		return nil, fmt.Errorf("OIDC JWKS has no supported RSA keys")
	}
	s.keysMu.Lock()
	s.keys = loaded
	s.keysFetchedAt = s.now()
	key = s.keys[kid]
	s.keysMu.Unlock()
	if key == nil {
		return nil, fmt.Errorf("OIDC JWKS did not contain token key")
	}
	return key, nil
}

func (s *Server) requestCertificate(ctx context.Context, csr, ott string) ([]byte, int, error) {
	payload, err := json.Marshal(map[string]string{"csr": csr, "ott": ott})
	if err != nil {
		return nil, 0, err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, s.config.CAURL+"/1.0/sign", bytes.NewReader(payload))
	if err != nil {
		return nil, 0, err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := s.httpClient.Do(request)
	if err != nil {
		return nil, 0, err
	}
	defer response.Body.Close()
	contents, err := io.ReadAll(io.LimitReader(response.Body, 2*1024*1024))
	if err != nil {
		return nil, 0, err
	}
	return contents, response.StatusCode, nil
}

func parseApprovedCSR(rawPEM string, identity Identity) (*x509.CertificateRequest, error) {
	block, rest := pem.Decode([]byte(rawPEM))
	if block == nil || block.Type != "CERTIFICATE REQUEST" || len(strings.TrimSpace(string(rest))) != 0 {
		return nil, fmt.Errorf("invalid CSR PEM")
	}
	csr, err := x509.ParseCertificateRequest(block.Bytes)
	if err != nil || csr.CheckSignature() != nil {
		return nil, fmt.Errorf("invalid CSR signature")
	}
	if csr.Subject.CommonName != identity.Subject || len(csr.DNSNames) != 0 || len(csr.EmailAddresses) != 0 || len(csr.IPAddresses) != 0 || len(csr.URIs) != 1 || csr.URIs[0].String() != identity.URISAN {
		return nil, fmt.Errorf("CSR identity does not match authorization")
	}
	return csr, nil
}

func bearerToken(header string) (string, error) {
	parts := strings.Fields(header)
	if len(parts) != 2 || parts[0] != "Bearer" || len(parts[1]) > 16384 {
		return "", fmt.Errorf("missing bearer token")
	}
	return parts[1], nil
}

func ensureEOF(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return fmt.Errorf("unexpected request body data")
	}
	return nil
}

func (s *Server) unauthorized(writer http.ResponseWriter) {
	writer.Header().Set("WWW-Authenticate", "Bearer")
	http.Error(writer, "unauthorized", http.StatusUnauthorized)
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("X-Content-Type-Options", "nosniff")
		writer.Header().Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(writer, request)
	})
}
