package enrollment

import (
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/kamilojdana/trustfinch/broker/internal/issuer"
	"github.com/go-jose/go-jose/v4"
)

type brokerKey = issuer.SigningKey

func LoadECPrivateJWK(path string) (brokerKey, error) {
	return issuer.LoadSigningKey(path)
}

type discoveryDocument struct {
	Issuer  string `json:"issuer"`
	JWKSURL string `json:"jwks_uri"`
}

type gitLabClaims struct {
	Issuer       string          `json:"iss"`
	Audience     stringOrStrings `json:"aud"`
	ExpiresAt    int64           `json:"exp"`
	NotBefore    int64           `json:"nbf"`
	IssuedAt     int64           `json:"iat"`
	ID           string          `json:"jti"`
	ProjectID    stringOrNumber  `json:"project_id"`
	ProjectPath  string          `json:"project_path"`
	Ref          string          `json:"ref"`
	RefType      string          `json:"ref_type"`
	RefProtected boolOrString    `json:"ref_protected"`
}

type stringOrStrings []string

func (s *stringOrStrings) UnmarshalJSON(value []byte) error {
	var one string
	if err := json.Unmarshal(value, &one); err == nil {
		*s = []string{one}
		return nil
	}
	var many []string
	if err := json.Unmarshal(value, &many); err != nil {
		return fmt.Errorf("aud must be a string or string array")
	}
	*s = many
	return nil
}

func (s stringOrStrings) Includes(expected string) bool {
	for _, actual := range s {
		if actual == expected {
			return true
		}
	}
	return false
}

type stringOrNumber string

func (s *stringOrNumber) UnmarshalJSON(value []byte) error {
	var text string
	if err := json.Unmarshal(value, &text); err == nil {
		*s = stringOrNumber(text)
		return nil
	}
	var number json.Number
	decoder := json.NewDecoder(strings.NewReader(string(value)))
	decoder.UseNumber()
	if err := decoder.Decode(&number); err != nil {
		return fmt.Errorf("value must be a string or number")
	}
	*s = stringOrNumber(number.String())
	return nil
}

type boolOrString bool

func (b *boolOrString) UnmarshalJSON(value []byte) error {
	var actual bool
	if err := json.Unmarshal(value, &actual); err == nil {
		*b = boolOrString(actual)
		return nil
	}
	var text string
	if err := json.Unmarshal(value, &text); err != nil {
		return fmt.Errorf("value must be a boolean or string")
	}
	switch text {
	case "true":
		*b = true
	case "false":
		*b = false
	default:
		return fmt.Errorf("value must be true or false")
	}
	return nil
}

func verifyGitLabJWT(token string, key *rsa.PublicKey, expectedIssuer string, now time.Time, maxLifetime time.Duration) (gitLabClaims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return gitLabClaims{}, fmt.Errorf("JWT must have three parts")
	}
	signed, err := jose.ParseSigned(token, []jose.SignatureAlgorithm{jose.RS256})
	if err != nil {
		return gitLabClaims{}, fmt.Errorf("parse GitLab JWT: %w", err)
	}
	if len(signed.Signatures) != 1 {
		return gitLabClaims{}, fmt.Errorf("GitLab JWT must have exactly one signature")
	}
	payload, err := signed.Verify(key)
	if err != nil {
		return gitLabClaims{}, fmt.Errorf("verify GitLab JWT signature: %w", err)
	}
	var claims gitLabClaims
	if err := json.Unmarshal(payload, &claims); err != nil {
		return gitLabClaims{}, fmt.Errorf("decode JWT claims: %w", err)
	}
	if claims.Issuer != expectedIssuer {
		return gitLabClaims{}, fmt.Errorf("unexpected issuer")
	}
	if claims.ID == "" || len(claims.ID) > 255 || claims.ExpiresAt == 0 || claims.NotBefore == 0 || claims.IssuedAt == 0 || claims.ProjectPath == "" {
		return gitLabClaims{}, fmt.Errorf("GitLab token is missing required time or jti claims")
	}
	const clockSkew = time.Minute
	if now.After(time.Unix(claims.ExpiresAt, 0).Add(clockSkew)) || now.Before(time.Unix(claims.NotBefore, 0).Add(-clockSkew)) || now.Before(time.Unix(claims.IssuedAt, 0).Add(-clockSkew)) {
		return gitLabClaims{}, fmt.Errorf("GitLab token is not currently valid")
	}
	if time.Unix(claims.ExpiresAt, 0).Sub(time.Unix(claims.IssuedAt, 0)) > maxLifetime+clockSkew {
		return gitLabClaims{}, fmt.Errorf("GitLab token lifetime exceeds policy")
	}
	return claims, nil
}

func selectGitLabIdentity(claims gitLabClaims, identities []Identity) (Identity, error) {
	for _, identity := range identities {
		if claims.Audience.Includes(identity.Audience) &&
			string(claims.ProjectID) == identity.ProjectID &&
			claims.ProjectPath == identity.ProjectPath &&
			claims.RefType == identity.RefType &&
			claims.Ref == identity.Ref &&
			bool(claims.RefProtected) {
			return identity, nil
		}
	}
	return Identity{}, fmt.Errorf("GitLab token does not match an approved protected-ref identity")
}

func parseJWTHeader(token string) (string, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return "", fmt.Errorf("JWT must have three parts")
	}
	signed, err := jose.ParseSigned(token, []jose.SignatureAlgorithm{jose.RS256})
	if err != nil || len(signed.Signatures) != 1 {
		return "", fmt.Errorf("GitLab JWT must be a single RS256 JWS")
	}
	header := signed.Signatures[0].Protected
	if header.Algorithm != string(jose.RS256) || header.KeyID == "" {
		return "", fmt.Errorf("GitLab JWT must have an RS256 algorithm and kid")
	}
	return header.KeyID, nil
}

func signBrokerJWT(key brokerKey, provisioner, subject, audience, csrFingerprint string, sans []string, now time.Time) (string, error) {
	return issuer.SignOneTimeToken(key, provisioner, subject, audience, csrFingerprint, sans, now)
}

func csrFingerprint(rawCSR []byte) string {
	return issuer.CSRFingerprint(rawCSR)
}

func parseApprovedCSR(rawPEM string, identity Identity) (*x509.CertificateRequest, error) {
	return issuer.ParseApprovedCSR(rawPEM, identity.Subject, identity.URISAN)
}

func decodeJSONSegment(segment string, target any) error {
	decoded, err := base64.RawURLEncoding.DecodeString(segment)
	if err != nil {
		return err
	}
	return json.Unmarshal(decoded, target)
}
