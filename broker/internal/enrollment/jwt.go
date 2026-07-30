package enrollment

import (
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/go-jose/go-jose/v4"
)

type brokerKey struct {
	PrivateKey *ecdsa.PrivateKey
	KeyID      string
}

func LoadECPrivateJWK(path string) (brokerKey, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return brokerKey{}, err
	}
	var jwk jose.JSONWebKey
	if err := json.Unmarshal(contents, &jwk); err != nil {
		return brokerKey{}, err
	}
	privateKey, ok := jwk.Key.(*ecdsa.PrivateKey)
	if !ok || privateKey.Curve.Params().Name != "P-256" || jwk.KeyID == "" || !jwk.Valid() {
		return brokerKey{}, fmt.Errorf("broker JWK must be a P-256 EC key with kid")
	}
	return brokerKey{PrivateKey: privateKey, KeyID: jwk.KeyID}, nil
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

func signBrokerJWT(key brokerKey, issuer, subject, audience, csrFingerprint string, sans []string, now time.Time) (string, error) {
	payload, err := json.Marshal(map[string]any{
		"iss":  issuer,
		"sub":  subject,
		"aud":  audience,
		"iat":  now.Unix(),
		"nbf":  now.Add(-30 * time.Second).Unix(),
		"exp":  now.Add(2 * time.Minute).Unix(),
		"jti":  randomTokenID(),
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

func csrFingerprint(rawCSR []byte) string {
	digest := sha256.Sum256(rawCSR)
	return base64.RawURLEncoding.EncodeToString(digest[:])
}

func decodeJSONSegment(segment string, target any) error {
	decoded, err := base64.RawURLEncoding.DecodeString(segment)
	if err != nil {
		return err
	}
	return json.Unmarshal(decoded, target)
}

func randomTokenID() string {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		panic("secure random source failed: " + err.Error())
	}
	return base64.RawURLEncoding.EncodeToString(bytes)
}
