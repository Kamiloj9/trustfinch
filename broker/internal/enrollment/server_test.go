package enrollment

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v4"
)

func TestGitLabEnrollmentClaimAndSANGuards(t *testing.T) {
	issuerKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	var issuer *httptest.Server
	issuer = httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/.well-known/openid-configuration":
			_ = json.NewEncoder(writer).Encode(discoveryDocument{Issuer: issuer.URL, JWKSURL: issuer.URL + "/jwks"})
		case "/jwks":
			_ = json.NewEncoder(writer).Encode(jose.JSONWebKeySet{Keys: []jose.JSONWebKey{rsaPublicJWK(t, issuerKey, "gitlab-key")}})
		default:
			http.NotFound(writer, request)
		}
	}))
	defer issuer.Close()

	identity := Identity{
		ProjectID: "42", ProjectPath: "platform/pki", Audience: "https://ca.pki.test/gitlab/platform-pki",
		RefType: "branch", Ref: "main", Subject: "gitlab:platform/pki", URISAN: "spiffe://pki.test/gitlab/platform/pki",
	}
	brokerPrivate, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	caRequests := 0
	failNextCARequest := false
	ca := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/1.0/sign" || request.Method != http.MethodPost {
			http.NotFound(writer, request)
			return
		}
		caRequests++
		var payload map[string]string
		if err := json.NewDecoder(request.Body).Decode(&payload); err != nil {
			t.Fatal(err)
		}
		if err := assertBrokerOTT(payload["ott"], brokerPrivate.PublicKey, identity, payload["csr"]); err != nil {
			t.Error(err)
			http.Error(writer, "bad authorization", http.StatusForbidden)
			return
		}
		if failNextCARequest {
			failNextCARequest = false
			http.Error(writer, "temporary CA failure", http.StatusServiceUnavailable)
			return
		}
		writer.Header().Set("Content-Type", "application/json")
		writer.WriteHeader(http.StatusCreated)
		_, _ = writer.Write([]byte(`{"crt":"test certificate","ca":"test ca","certChain":[]}`))
	}))
	defer ca.Close()

	server, err := NewServer(Config{
		Issuer: issuer.URL, DiscoveryURL: issuer.URL + "/.well-known/openid-configuration", ReplayTableName: "local",
		CAURL: ca.URL, CAServerName: "ca.pki.test", CASignAudience: "https://ca.pki.test/1.0/sign#GitLab%20Enrollment%20Broker:broker-key",
		BrokerProvisionerName: "GitLab Enrollment Broker", MaxGitLabTokenLifetime: Duration{10 * time.Minute}, Identities: []Identity{identity},
	}, brokerKey{PrivateKey: brokerPrivate, KeyID: "broker-key"}, NewMemoryReplayStore(), &http.Client{Timeout: 5 * time.Second}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	api := httptest.NewServer(server.Handler())
	defer api.Close()

	now := time.Now().UTC()
	validCSR := makeCSR(t, identity.Subject, identity.URISAN)
	retryableToken := makeGitLabToken(t, issuerKey, issuer.URL, validClaims(identity, now, "retry-after-ca-failure", identity.Audience))
	failNextCARequest = true
	assertStatus(t, postEnrollment(t, api.URL, retryableToken, validCSR), http.StatusBadGateway)
	assertStatus(t, postEnrollment(t, api.URL, retryableToken, validCSR), http.StatusCreated)

	validToken := makeGitLabToken(t, issuerKey, issuer.URL, gitLabClaims{
		Issuer: issuer.URL, Audience: []string{identity.Audience}, ExpiresAt: now.Add(5 * time.Minute).Unix(), NotBefore: now.Add(-time.Minute).Unix(), IssuedAt: now.Unix(), ID: "valid-jti",
		ProjectID: stringOrNumber(identity.ProjectID), ProjectPath: identity.ProjectPath, Ref: identity.Ref, RefType: identity.RefType, RefProtected: true,
	})
	assertStatus(t, postEnrollment(t, api.URL, validToken, validCSR), http.StatusCreated)
	assertStatus(t, postEnrollment(t, api.URL, validToken, validCSR), http.StatusConflict)

	wrongAudience := validClaims(identity, now, "wrong-audience", identity.Audience+"/wrong")
	assertStatus(t, postEnrollment(t, api.URL, makeGitLabToken(t, issuerKey, issuer.URL, wrongAudience), validCSR), http.StatusUnauthorized)

	wrongProject := validClaims(identity, now, "wrong-project", identity.Audience)
	wrongProject.ProjectPath = "platform/other"
	assertStatus(t, postEnrollment(t, api.URL, makeGitLabToken(t, issuerKey, issuer.URL, wrongProject), validCSR), http.StatusUnauthorized)

	unprotected := validClaims(identity, now, "unprotected", identity.Audience)
	unprotected.RefProtected = false
	assertStatus(t, postEnrollment(t, api.URL, makeGitLabToken(t, issuerKey, issuer.URL, unprotected), validCSR), http.StatusUnauthorized)

	expired := validClaims(identity, now, "expired", identity.Audience)
	expired.ExpiresAt = now.Add(-2 * time.Minute).Unix()
	expired.IssuedAt = now.Add(-7 * time.Minute).Unix()
	assertStatus(t, postEnrollment(t, api.URL, makeGitLabToken(t, issuerKey, issuer.URL, expired), validCSR), http.StatusUnauthorized)

	customSANToken := makeGitLabToken(t, issuerKey, issuer.URL, validClaims(identity, now, "custom-san", identity.Audience))
	assertStatus(t, postEnrollment(t, api.URL, customSANToken, makeCSR(t, identity.Subject, "spiffe://pki.test/other")), http.StatusForbidden)

	if caRequests != 3 {
		t.Fatalf("step-ca request count = %d, want 3", caRequests)
	}
}

func validClaims(identity Identity, now time.Time, jti, audience string) gitLabClaims {
	return gitLabClaims{
		Issuer: "ignored-before-signing", Audience: []string{audience}, ExpiresAt: now.Add(5 * time.Minute).Unix(), NotBefore: now.Add(-time.Minute).Unix(), IssuedAt: now.Unix(), ID: jti,
		ProjectID: stringOrNumber(identity.ProjectID), ProjectPath: identity.ProjectPath, Ref: identity.Ref, RefType: identity.RefType, RefProtected: true,
	}
}

func postEnrollment(t *testing.T, endpoint, token, csr string) *http.Response {
	t.Helper()
	body, err := json.Marshal(enrollmentRequest{CSR: csr})
	if err != nil {
		t.Fatal(err)
	}
	request, err := http.NewRequest(http.MethodPost, endpoint+enrollmentPath, strings.NewReader(string(body)))
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", "application/json")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	return response
}

func assertStatus(t *testing.T, response *http.Response, expected int) {
	t.Helper()
	defer response.Body.Close()
	contents, _ := io.ReadAll(response.Body)
	if response.StatusCode != expected {
		t.Fatalf("status = %d, want %d: %s", response.StatusCode, expected, contents)
	}
}

func rsaPublicJWK(t *testing.T, key *rsa.PrivateKey, kid string) jose.JSONWebKey {
	t.Helper()
	return jose.JSONWebKey{Key: &key.PublicKey, KeyID: kid, Algorithm: string(jose.RS256), Use: "sig"}
}

func makeGitLabToken(t *testing.T, key *rsa.PrivateKey, issuer string, claims gitLabClaims) string {
	t.Helper()
	claims.Issuer = issuer
	header, err := json.Marshal(map[string]string{"alg": "RS256", "kid": "gitlab-key", "typ": "JWT"})
	if err != nil {
		t.Fatal(err)
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		t.Fatal(err)
	}
	encodedHeader := base64.RawURLEncoding.EncodeToString(header)
	encodedPayload := base64.RawURLEncoding.EncodeToString(payload)
	digest := sha256.Sum256([]byte(encodedHeader + "." + encodedPayload))
	signature, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	return encodedHeader + "." + encodedPayload + "." + base64.RawURLEncoding.EncodeToString(signature)
}

func makeCSR(t *testing.T, subject, uri string) string {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	parsedURI, err := url.Parse(uri)
	if err != nil {
		t.Fatal(err)
	}
	csr, err := x509.CreateCertificateRequest(rand.Reader, &x509.CertificateRequest{Subject: pkixName(subject), URIs: []*url.URL{parsedURI}}, key)
	if err != nil {
		t.Fatal(err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE REQUEST", Bytes: csr}))
}

func pkixName(commonName string) pkix.Name { return pkix.Name{CommonName: commonName} }

func assertBrokerOTT(token string, publicKey ecdsa.PublicKey, identity Identity, rawCSR string) error {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return fmt.Errorf("broker OTT has invalid shape")
	}
	var header struct {
		Algorithm string `json:"alg"`
		KeyID     string `json:"kid"`
	}
	if err := decodeJSONSegment(parts[0], &header); err != nil || header.Algorithm != "ES256" || header.KeyID != "broker-key" {
		return fmt.Errorf("broker OTT header is invalid")
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(signature) != 64 || !ecdsa.Verify(&publicKey, digest[:], new(big.Int).SetBytes(signature[:32]), new(big.Int).SetBytes(signature[32:])) {
		return fmt.Errorf("broker OTT signature is invalid")
	}
	var claims struct {
		Issuer   string            `json:"iss"`
		Subject  string            `json:"sub"`
		Audience string            `json:"aud"`
		SANs     []string          `json:"sans"`
		CNF      map[string]string `json:"cnf"`
	}
	if err := decodeJSONSegment(parts[1], &claims); err != nil {
		return err
	}
	block, _ := pem.Decode([]byte(rawCSR))
	if claims.Issuer != "GitLab Enrollment Broker" || claims.Subject != identity.Subject || claims.Audience != "https://ca.pki.test/1.0/sign#GitLab%20Enrollment%20Broker:broker-key" || len(claims.SANs) != 1 || claims.SANs[0] != identity.URISAN || claims.CNF["x5rt#S256"] != csrFingerprint(block.Bytes) {
		return fmt.Errorf("broker OTT did not bind the approved identity and CSR")
	}
	return nil
}
