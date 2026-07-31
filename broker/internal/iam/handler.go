package iam

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/trustfinch/trustfinch/broker/internal/issuer"
)

const enrollmentPath = "/1.0/enroll/iam"

type Handler struct {
	config     Config
	signingKey issuer.SigningKey
	httpClient *http.Client
	now        func() time.Time
}

type enrollmentRequest struct {
	CSR string `json:"csr"`
}

func NewHandler(config Config, signingKey issuer.SigningKey, httpClient *http.Client) (*Handler, error) {
	if err := config.Validate(); err != nil {
		return nil, err
	}
	if signingKey.PrivateKey == nil || signingKey.KeyID == "" || httpClient == nil {
		return nil, fmt.Errorf("IAM broker dependencies are required")
	}
	return &Handler{config: config, signingKey: signingKey, httpClient: httpClient, now: time.Now}, nil
}

func (h *Handler) Handle(ctx context.Context, event events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	if event.RouteKey != "POST "+enrollmentPath || event.RawPath != enrollmentPath || event.RequestContext.HTTP.Method != http.MethodPost {
		return response(http.StatusNotFound, "not found"), nil
	}
	if event.IsBase64Encoded || len(event.Body) > 1024*1024 {
		return response(http.StatusBadRequest, "invalid certificate request"), nil
	}
	if event.RequestContext.Authorizer == nil || event.RequestContext.Authorizer.IAM == nil {
		return response(http.StatusForbidden, "IAM authorization context is required"), nil
	}
	caller := event.RequestContext.Authorizer.IAM
	roleARN, err := NormalizeAssumedRoleARN(caller.UserARN, caller.AccountID)
	if err != nil {
		return response(http.StatusForbidden, "IAM role is not authorized"), nil
	}
	identity, err := SelectIdentity(roleARN, h.config.Identities)
	if err != nil {
		return response(http.StatusForbidden, "IAM role is not authorized"), nil
	}

	var body enrollmentRequest
	decoder := json.NewDecoder(strings.NewReader(event.Body))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&body); err != nil || body.CSR == "" || ensureEOF(decoder) != nil {
		return response(http.StatusBadRequest, "invalid certificate request"), nil
	}
	csr, err := issuer.ParseApprovedCSR(body.CSR, identity.Subject, identity.URISAN)
	if err != nil {
		return response(http.StatusForbidden, "certificate request does not match the approved identity"), nil
	}
	ott, err := issuer.SignOneTimeToken(h.signingKey, h.config.BrokerProvisionerName, identity.Subject, h.config.CASignAudience, issuer.CSRFingerprint(csr.Raw), []string{identity.URISAN}, h.now())
	if err != nil {
		return response(http.StatusServiceUnavailable, "enrollment temporarily unavailable"), nil
	}
	certificate, status, err := h.requestCertificate(ctx, body.CSR, ott)
	if err != nil || status != http.StatusCreated {
		return response(http.StatusBadGateway, "certificate authority unavailable"), nil
	}
	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusCreated,
		Headers: map[string]string{
			"Cache-Control":          "no-store",
			"Content-Type":           "application/json",
			"X-Content-Type-Options": "nosniff",
			"Referrer-Policy":        "no-referrer",
		},
		Body: certificate,
	}, nil
}

func (h *Handler) requestCertificate(ctx context.Context, csr, ott string) (string, int, error) {
	payload, err := json.Marshal(map[string]string{"csr": csr, "ott": ott})
	if err != nil {
		return "", 0, err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, h.config.CAURL+"/1.0/sign", bytes.NewReader(payload))
	if err != nil {
		return "", 0, err
	}
	request.Header.Set("Content-Type", "application/json")
	result, err := h.httpClient.Do(request)
	if err != nil {
		return "", 0, err
	}
	defer result.Body.Close()
	contents, err := io.ReadAll(io.LimitReader(result.Body, 2*1024*1024))
	if err != nil {
		return "", 0, err
	}
	return string(contents), result.StatusCode, nil
}

func ensureEOF(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return fmt.Errorf("unexpected request body data")
	}
	return nil
}

func response(status int, message string) events.APIGatewayV2HTTPResponse {
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers: map[string]string{
			"Cache-Control":          "no-store",
			"Content-Type":           "text/plain; charset=utf-8",
			"X-Content-Type-Options": "nosniff",
			"Referrer-Policy":        "no-referrer",
		},
		Body: message,
	}
}
