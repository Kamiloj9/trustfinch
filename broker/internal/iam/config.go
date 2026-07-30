package iam

import (
	"encoding/json"
	"fmt"
	"net/url"
	"regexp"
	"strings"
)

var (
	roleARNPattern        = regexp.MustCompile(`^arn:(aws|aws-us-gov|aws-cn):iam::([0-9]{12}):role/([A-Za-z0-9+=,.@_/-]+)$`)
	assumedRoleARNPattern = regexp.MustCompile(`^arn:(aws|aws-us-gov|aws-cn):sts::([0-9]{12}):assumed-role/([A-Za-z0-9+=,.@_/-]+)/([A-Za-z0-9+=,.@_-]{2,64})$`)
)

// Config is deliberately public configuration stored in the reviewed runtime
// artifact. The corresponding private signing JWK comes only from Secrets
// Manager at Lambda startup.
type Config struct {
	CAURL                 string     `json:"ca_url"`
	CAServerName          string     `json:"ca_server_name"`
	CASignAudience        string     `json:"ca_sign_audience"`
	BrokerProvisionerName string     `json:"broker_provisioner_name"`
	CARootCertificatePEM  string     `json:"ca_root_certificate_pem,omitempty"`
	Identities            []Identity `json:"identities"`
}

type Identity struct {
	RoleARN string `json:"role_arn"`
	Subject string `json:"subject"`
	URISAN  string `json:"uri_san"`
}

func ParseConfig(contents []byte) (Config, error) {
	var config Config
	if err := json.Unmarshal(contents, &config); err != nil {
		return Config{}, err
	}
	return config, config.Validate()
}

func (c Config) Validate() error {
	for name, value := range map[string]string{
		"ca_url": c.CAURL, "ca_server_name": c.CAServerName,
		"ca_sign_audience": c.CASignAudience, "broker_provisioner_name": c.BrokerProvisionerName,
	} {
		if strings.TrimSpace(value) == "" {
			return fmt.Errorf("%s is required", name)
		}
	}
	for _, value := range []string{c.CAURL, c.CASignAudience} {
		parsed, err := url.Parse(value)
		if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
			return fmt.Errorf("invalid HTTPS URL %q", value)
		}
	}
	parsedCAURL, _ := url.Parse(c.CAURL)
	if parsedCAURL.Path != "" && parsedCAURL.Path != "/" || parsedCAURL.RawQuery != "" || parsedCAURL.Fragment != "" {
		return fmt.Errorf("ca_url must be an HTTPS origin without a path, query, or fragment")
	}
	if len(c.Identities) == 0 {
		return fmt.Errorf("at least one IAM role identity is required")
	}
	seen := map[string]struct{}{}
	for _, identity := range c.Identities {
		if !roleARNPattern.MatchString(identity.RoleARN) {
			return fmt.Errorf("identity role_arn must be an IAM role ARN")
		}
		if strings.TrimSpace(identity.Subject) == "" {
			return fmt.Errorf("identity %q: subject is required", identity.RoleARN)
		}
		uri, err := url.Parse(identity.URISAN)
		if err != nil || uri.Scheme != "spiffe" || uri.Host == "" {
			return fmt.Errorf("identity %q: uri_san must be an absolute SPIFFE URI", identity.RoleARN)
		}
		if _, found := seen[identity.RoleARN]; found {
			return fmt.Errorf("duplicate IAM role identity %q", identity.RoleARN)
		}
		seen[identity.RoleARN] = struct{}{}
	}
	return nil
}

// NormalizeAssumedRoleARN only accepts the trusted temporary-credential ARN
// that API Gateway supplies after successful SigV4 authorization. IAM users,
// federated users, and malformed STS ARNs never gain a certificate identity.
func NormalizeAssumedRoleARN(userARN, accountID string) (string, error) {
	matches := assumedRoleARNPattern.FindStringSubmatch(userARN)
	if matches == nil || matches[2] != accountID {
		return "", fmt.Errorf("request is not an assumed IAM role ARN")
	}
	return fmt.Sprintf("arn:%s:iam::%s:role/%s", matches[1], matches[2], matches[3]), nil
}

func SelectIdentity(roleARN string, identities []Identity) (Identity, error) {
	for _, identity := range identities {
		if identity.RoleARN == roleARN {
			return identity, nil
		}
	}
	return Identity{}, fmt.Errorf("IAM role does not match an approved certificate identity")
}
