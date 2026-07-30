package enrollment

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"strings"
	"time"
)

// Config deliberately contains only public configuration. The matching private
// JWK is loaded separately from a runtime secret file and never from Terraform
// state, the S3 runtime artifact, or this JSON file.
type Config struct {
	Issuer                 string     `json:"issuer"`
	DiscoveryURL           string     `json:"discovery_url"`
	ReplayTableName        string     `json:"replay_table_name"`
	CAURL                  string     `json:"ca_url"`
	CAServerName           string     `json:"ca_server_name"`
	CASignAudience         string     `json:"ca_sign_audience"`
	BrokerProvisionerName  string     `json:"broker_provisioner_name"`
	MaxGitLabTokenLifetime Duration   `json:"max_gitlab_token_lifetime"`
	Identities             []Identity `json:"identities"`
}

type Identity struct {
	ProjectID   string `json:"project_id"`
	ProjectPath string `json:"project_path"`
	Audience    string `json:"audience"`
	RefType     string `json:"ref_type"`
	Ref         string `json:"ref"`
	Subject     string `json:"subject"`
	URISAN      string `json:"uri_san"`
}

type Duration struct{ time.Duration }

func (d *Duration) UnmarshalJSON(value []byte) error {
	var text string
	if err := json.Unmarshal(value, &text); err != nil {
		return fmt.Errorf("duration must be a string: %w", err)
	}
	parsed, err := time.ParseDuration(text)
	if err != nil {
		return err
	}
	d.Duration = parsed
	return nil
}

func LoadConfig(path string) (Config, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}
	var config Config
	if err := json.Unmarshal(contents, &config); err != nil {
		return Config{}, err
	}
	return config, config.Validate()
}

func (c Config) Validate() error {
	for name, value := range map[string]string{
		"issuer": c.Issuer, "discovery_url": c.DiscoveryURL, "ca_url": c.CAURL,
		"ca_server_name": c.CAServerName, "ca_sign_audience": c.CASignAudience,
		"broker_provisioner_name": c.BrokerProvisionerName,
	} {
		if strings.TrimSpace(value) == "" {
			return fmt.Errorf("%s is required", name)
		}
	}
	if len(c.Identities) == 0 {
		return fmt.Errorf("at least one GitLab identity is required")
	}
	if c.MaxGitLabTokenLifetime.Duration <= 0 || c.MaxGitLabTokenLifetime.Duration > 24*time.Hour {
		return fmt.Errorf("max_gitlab_token_lifetime must be between zero and 24h")
	}
	for _, value := range []string{c.Issuer, c.DiscoveryURL, c.CAURL, c.CASignAudience} {
		u, err := url.Parse(value)
		if err != nil || u.Scheme == "" || u.Host == "" {
			return fmt.Errorf("invalid URL %q", value)
		}
	}
	seen := map[string]struct{}{}
	for _, identity := range c.Identities {
		for name, value := range map[string]string{
			"project_id": identity.ProjectID, "project_path": identity.ProjectPath,
			"audience": identity.Audience, "ref_type": identity.RefType, "ref": identity.Ref,
			"subject": identity.Subject, "uri_san": identity.URISAN,
		} {
			if strings.TrimSpace(value) == "" {
				return fmt.Errorf("identity %q: %s is required", identity.ProjectPath, name)
			}
		}
		if identity.RefType != "branch" && identity.RefType != "tag" {
			return fmt.Errorf("identity %q: ref_type must be branch or tag", identity.ProjectPath)
		}
		uri, err := url.Parse(identity.URISAN)
		if err != nil || uri.Scheme != "spiffe" || uri.Host == "" {
			return fmt.Errorf("identity %q: uri_san must be an absolute SPIFFE URI", identity.ProjectPath)
		}
		key := strings.Join([]string{identity.ProjectID, identity.Audience, identity.RefType, identity.Ref}, "\x00")
		if _, found := seen[key]; found {
			return fmt.Errorf("duplicate GitLab identity mapping for project %q and ref %q", identity.ProjectID, identity.Ref)
		}
		seen[key] = struct{}{}
	}
	return nil
}
