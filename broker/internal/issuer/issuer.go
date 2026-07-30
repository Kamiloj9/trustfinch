// Package issuer contains the small, shared boundary between enrollment
// brokers and step-ca. It deliberately does not implement a CA: it validates
// a CSR's pre-approved identity and creates a short-lived, CSR-bound JWK OTT
// for an existing step-ca JWK provisioner.
package issuer

import (
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/go-jose/go-jose/v4"
)

type SigningKey struct {
	PrivateKey *ecdsa.PrivateKey
	KeyID      string
}

func LoadSigningKey(path string) (SigningKey, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return SigningKey{}, err
	}
	return ParseSigningKey(contents)
}

func ParseSigningKey(contents []byte) (SigningKey, error) {
	var jwk jose.JSONWebKey
	if err := json.Unmarshal(contents, &jwk); err != nil {
		return SigningKey{}, err
	}
	privateKey, ok := jwk.Key.(*ecdsa.PrivateKey)
	if !ok || privateKey.Curve.Params().Name != "P-256" || jwk.KeyID == "" || !jwk.Valid() {
		return SigningKey{}, fmt.Errorf("broker JWK must be a P-256 EC key with kid")
	}
	return SigningKey{PrivateKey: privateKey, KeyID: jwk.KeyID}, nil
}

func SignOneTimeToken(key SigningKey, issuer, subject, audience, csrFingerprint string, sans []string, now time.Time) (string, error) {
	payload, err := json.Marshal(map[string]any{
		"iss":  issuer,
		"sub":  subject,
		"aud":  audience,
		"iat":  now.Unix(),
		"nbf":  now.Add(-30 * time.Second).Unix(),
		"exp":  now.Add(2 * time.Minute).Unix(),
		"jti":  NewTokenID(),
		"sans": sans,
		"cnf":  map[string]string{"x5rt#S256": csrFingerprint},
	})
	if err != nil {
		return "", err
	}
	signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.ES256, Key: key.PrivateKey}, (&jose.SignerOptions{}).WithType("JWT").WithHeader(jose.HeaderKey("kid"), key.KeyID))
	if err != nil {
		return "", err
	}
	signed, err := signer.Sign(payload)
	if err != nil {
		return "", err
	}
	return signed.CompactSerialize()
}

func ParseApprovedCSR(rawPEM, subject, uriSAN string) (*x509.CertificateRequest, error) {
	parsedURI, err := url.Parse(uriSAN)
	if err != nil || parsedURI.Scheme != "spiffe" || parsedURI.Host == "" {
		return nil, fmt.Errorf("approved identity has an invalid SPIFFE URI")
	}
	block, rest := pem.Decode([]byte(rawPEM))
	if block == nil || block.Type != "CERTIFICATE REQUEST" || len(strings.TrimSpace(string(rest))) != 0 {
		return nil, fmt.Errorf("invalid CSR PEM")
	}
	csr, err := x509.ParseCertificateRequest(block.Bytes)
	if err != nil || csr.CheckSignature() != nil {
		return nil, fmt.Errorf("invalid CSR signature")
	}
	if csr.Subject.CommonName != subject || len(csr.DNSNames) != 0 || len(csr.EmailAddresses) != 0 || len(csr.IPAddresses) != 0 || len(csr.URIs) != 1 || csr.URIs[0].String() != parsedURI.String() {
		return nil, fmt.Errorf("CSR identity does not match authorization")
	}
	return csr, nil
}

func CSRFingerprint(rawCSR []byte) string {
	digest := sha256.Sum256(rawCSR)
	return base64.RawURLEncoding.EncodeToString(digest[:])
}

func NewTokenID() string {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		panic("secure random source failed: " + err.Error())
	}
	return base64.RawURLEncoding.EncodeToString(bytes)
}
