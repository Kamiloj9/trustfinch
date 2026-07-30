{{- if not .Token.email_verified }}{{ fail "Google identity token does not have a verified email" }}{{ end -}}
{
  "subject": {
    "commonName": {{ toJson .Token.email }}
  },
  "emailAddresses": [{{ toJson .Token.email }}],
  {{- if typeIs "*rsa.PublicKey" .Insecure.CR.PublicKey }}
  "keyUsage": ["keyEncipherment", "digitalSignature"],
  {{- else }}
  "keyUsage": ["digitalSignature"],
  {{- end }}
  "extKeyUsage": ["clientAuth"]
}
