package iam

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/kamilojdana/trustfinch/broker/internal/issuer"
	"github.com/go-jose/go-jose/v4"
)

func TestSigV4IAMEnrollmentGuards(t *testing.T) {
	identity := Identity{
		RoleARN: "arn:aws:iam::111122223333:role/platform/pki-runner",
		Subject: "iam:platform/pki-runner", URISAN: "spiffe://pki.test/iam/platform/pki-runner",
	}
	brokerKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	caShouldFail := false
	ca := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/1.0/sign" || request.Method != http.MethodPost {
			http.NotFound(writer, request)
			return
		}
		var payload map[string]string
		if err := json.NewDecoder(request.Body).Decode(&payload); err != nil {
			t.Fatal(err)
		}
		if err := assertBrokerOTT(payload["ott"], brokerKey.PublicKey, identity, payload["csr"]); err != nil {
			t.Error(err)
			http.Error(writer, "bad authorization", http.StatusForbidden)
			return
		}
		if caShouldFail {
			http.Error(writer, "temporary CA failure", http.StatusServiceUnavailable)
			return
		}
		writer.Header().Set("Content-Type", "application/json")
		writer.WriteHeader(http.StatusCreated)
		_, _ = writer.Write([]byte(`{"crt":"test certificate","ca":"test ca","certChain":[]}`))
	}))
	defer ca.Close()

	handler, err := NewHandler(Config{
		CAURL: ca.URL, CAServerName: "ca.pki.test",
		CASignAudience:        "https://ca.pki.test/1.0/sign#IAM%20Enrollment%20Broker:iam-broker-key",
		BrokerProvisionerName: "IAM Enrollment Broker", Identities: []Identity{identity},
	}, issuer.SigningKey{PrivateKey: brokerKey, KeyID: "iam-broker-key"}, ca.Client())
	if err != nil {
		t.Fatal(err)
	}

	validCSR := makeCSR(t, identity.Subject, identity.URISAN)
	validEvent := makeEvent(t, validCSR, "arn:aws:sts::111122223333:assumed-role/platform/pki-runner/build-123")
	assertStatus(t, handler, validEvent, http.StatusCreated)

	wrongRole := makeEvent(t, validCSR, "arn:aws:sts::111122223333:assumed-role/platform/other/build-123")
	assertStatus(t, handler, wrongRole, http.StatusForbidden)

	userPrincipal := makeEvent(t, validCSR, "arn:aws:iam::111122223333:user/deployer")
	assertStatus(t, handler, userPrincipal, http.StatusForbidden)

	customSAN := makeEvent(t, makeCSR(t, identity.Subject, "spiffe://pki.test/iam/other"), "arn:aws:sts::111122223333:assumed-role/platform/pki-runner/build-123")
	assertStatus(t, handler, customSAN, http.StatusForbidden)

	caShouldFail = true
	assertStatus(t, handler, makeEvent(t, validCSR, "arn:aws:sts::111122223333:assumed-role/platform/pki-runner/build-124"), http.StatusBadGateway)
}

func TestNormalizeAssumedRoleARN(t *testing.T) {
	actual, err := NormalizeAssumedRoleARN("arn:aws:sts::111122223333:assumed-role/team/ci/role-name/session-123", "111122223333")
	if err != nil {
		t.Fatal(err)
	}
	if expected := "arn:aws:iam::111122223333:role/team/ci/role-name"; actual != expected {
		t.Fatalf("normalized role = %q, want %q", actual, expected)
	}
	if _, err := NormalizeAssumedRoleARN("arn:aws:sts::999988887777:assumed-role/team/ci/role-name/session-123", "111122223333"); err == nil {
		t.Fatal("expected caller account mismatch to be rejected")
	}
}

func makeEvent(t *testing.T, csr, userARN string) events.APIGatewayV2HTTPRequest {
	t.Helper()
	body, err := json.Marshal(enrollmentRequest{CSR: csr})
	if err != nil {
		t.Fatal(err)
	}
	return events.APIGatewayV2HTTPRequest{
		Version: "2.0", RouteKey: "POST " + enrollmentPath, RawPath: enrollmentPath, Body: string(body),
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{Method: http.MethodPost},
			Authorizer: &events.APIGatewayV2HTTPRequestContextAuthorizerDescription{IAM: &events.APIGatewayV2HTTPRequestContextAuthorizerIAMDescription{
				AccountID: "111122223333", UserARN: userARN, CallerID: "AROAXXXX:build-123",
			}},
		},
	}
}

func assertStatus(t *testing.T, handler *Handler, event events.APIGatewayV2HTTPRequest, expected int) {
	t.Helper()
	result, err := handler.Handle(context.Background(), event)
	if err != nil {
		t.Fatal(err)
	}
	if result.StatusCode != expected {
		t.Fatalf("status = %d, want %d: %s", result.StatusCode, expected, result.Body)
	}
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
	csr, err := x509.CreateCertificateRequest(rand.Reader, &x509.CertificateRequest{Subject: pkix.Name{CommonName: subject}, URIs: []*url.URL{parsedURI}}, key)
	if err != nil {
		t.Fatal(err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE REQUEST", Bytes: csr}))
}

func assertBrokerOTT(token string, publicKey ecdsa.PublicKey, identity Identity, rawCSR string) error {
	signed, err := jose.ParseSigned(token, []jose.SignatureAlgorithm{jose.ES256})
	if err != nil || len(signed.Signatures) != 1 || signed.Signatures[0].Protected.KeyID != "iam-broker-key" {
		return io.ErrUnexpectedEOF
	}
	payload, err := signed.Verify(&publicKey)
	if err != nil {
		return err
	}
	var claims struct {
		Issuer   string            `json:"iss"`
		Subject  string            `json:"sub"`
		Audience string            `json:"aud"`
		SANs     []string          `json:"sans"`
		CNF      map[string]string `json:"cnf"`
		Expires  int64             `json:"exp"`
	}
	if err := json.Unmarshal(payload, &claims); err != nil {
		return err
	}
	block, _ := pem.Decode([]byte(rawCSR))
	if claims.Issuer != "IAM Enrollment Broker" || claims.Subject != identity.Subject || claims.Audience != "https://ca.pki.test/1.0/sign#IAM%20Enrollment%20Broker:iam-broker-key" || len(claims.SANs) != 1 || claims.SANs[0] != identity.URISAN || claims.CNF["x5rt#S256"] != issuer.CSRFingerprint(block.Bytes) || claims.Expires < time.Now().Add(time.Minute).Unix() || claims.Expires > time.Now().Add(3*time.Minute).Unix() {
		return io.ErrUnexpectedEOF
	}
	return nil
}
