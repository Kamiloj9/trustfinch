# Certificate revocation

This PKI uses `step-ca` passive revocation for normal workload certificates. A successful revocation blocks all future renewals of the certificate, but does not invalidate the already-issued certificate at relying parties. The residual exposure is therefore bounded by the certificate's maximum 24-hour lifetime. Do not represent this profile as providing real-time OCSP or CRL enforcement.

## Workload key compromise

1. Remove the workload's enrollment authorization where applicable: disable its IAM role mapping, GitLab identity mapping, EC2 account rule, ACME DNS/challenge ownership, or OIDC identity. This prevents fresh enrollment with a new key.
2. From a host that holds the compromised certificate and key, revoke it over the CA's mutually authenticated endpoint. The certificate owner does not need a provisioner password:

   ```sh
   step ca revoke \
     --cert /etc/workload/tls.crt \
     --key /etc/workload/tls.key \
     --reason "key compromise" \
     --reasonCode KeyCompromise \
     --ca-url https://ca.example.internal \
     --root /etc/pki/root_ca.crt
   ```

3. Verify that the old certificate cannot renew, then enroll a replacement identity using the approved flow. Record the certificate serial, reason code, affected identity, time, operator, and replacement evidence in the incident ticket. Never paste private keys, provisioner passwords, bearer tokens, or certificate-request headers into that ticket.
4. Rotate every access path that could have exposed the key, and allow or actively disconnect existing sessions according to the workload's incident procedure. Relying parties that do not check revocation can trust the prior certificate until it expires.

## Administrative revocation

When the certificate key is unavailable, a PKI administrator may revoke by serial number using a reviewed JWK provisioner credential. The JWK password must be entered from a controlled ceremony or break-glass environment; it must never be stored in Terraform variables, CI logs, or a long-lived host environment. Confirm the provisioner and serial before authorizing the request.

## Acceptance evidence

`make test` issues a local certificate, revokes it with its own certificate/key pair, and proves that `step ca renew` is denied. Exercise the production procedure during a quarterly recovery/security test and record the observed time to block renewal.
