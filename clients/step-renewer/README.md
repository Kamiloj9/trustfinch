# Workload certificate renewal

This package is for a workload that already has a certificate, private key, independently distributed root certificate, and the pinned `step` CLI installed. It does not enroll a workload or create a private key. Use the enrollment mechanism approved in the identity matrix first.

`renew-step-certificate.sh` asks `step-ca` to renew into a temporary file in the certificate's own directory, verifies the returned chain against the supplied root, copies the current certificate mode, and finishes with `mv`. The live certificate is consequently never replaced with a partial, unverified, or failed renewal. On transient failure it retries with bounded exponential backoff; after the last attempt it exits non-zero so systemd logs the failure.

Install the executable as `/usr/local/libexec/pki-renew-certificate`, copy `renewal.env.example` to `/etc/pki/renewal.env` with placeholders replaced, then install and enable the supplied service and timer:

```sh
install -m 0755 renew-step-certificate.sh /usr/local/libexec/pki-renew-certificate
install -m 0600 renewal.env.example /etc/pki/renewal.env
install -m 0644 systemd/pki-certificate-renew.service /etc/systemd/system/
install -m 0644 systemd/pki-certificate-renew.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now pki-certificate-renew.timer
```

The timer checks hourly, adds up to ten minutes of scheduling jitter, and uses the CLI's `--expires-in` threshold (which also introduces jitter) so normal 24-hour certificates renew well before expiry. Leave `PKI_RENEW_FORCE_NOW=false` in service use; it exists solely for a controlled immediate-renewal test. Set `PKI_RELOAD_COMMAND` only to a reviewed local command; it runs after the atomic replacement and is useful for reloading a TLS-serving process.

The helper deliberately does not delete an old certificate after a failed CA request. Keep the prior certificate and retry with jitter/backoff during a short CA, network, KMS, or regional outage.
