# Runtime artifact-signing runbook

The CA nodes download their runtime configuration from a private S3 bucket. When runtime verification is enabled, the node verifies a detached ECDSA P-256 signature over a manifest of every downloaded runtime artifact before it renders secrets or starts Docker. The KMS signing key is deliberately separate from the root and intermediate CA keys; the runtime receives only its public PEM key.

## Bootstrap the signing key

1. Add `runtime_artifact_signing` from the relevant `terraform.tfvars.example`. Keep `verification_enabled = false` for the first apply. The key administrator and artifact signer roles must be distinct; the signer role needs only `kms:Sign` with `ECDSA_SHA_256` on this new key.
2. Apply the reviewed change with short-lived credentials. Record the `artifact_bucket` and `runtime_artifact_signing_key_id` Terraform outputs.
3. Assume the approved artifact signer role and run:

   ```sh
   ceremony/sign-runtime-artifacts.sh --bucket <artifact_bucket> --key-id <runtime_artifact_signing_key_id>
   ```

   The script downloads `runtime/`, produces `runtime.manifest`, signs that manifest in KMS, and uploads only `runtime.manifest` and `runtime.manifest.sig`. It refuses an empty manifest or a manifest larger than the KMS raw-message limit.
4. Set `verification_enabled = true` and apply a separately reviewed change. In HA, increment `runtime_release_id` in that second apply so the ASG rolls only after the signed manifest exists. Lean replaces its instance user data and will fail closed if the manifest is absent or invalid.

## Every runtime artifact release

With verification enabled, artifact writes and runtime activation are a two-phase release:

1. Apply the reviewed configuration/artifact update without changing the HA `runtime_release_id`; existing nodes keep their already-running configuration.
2. From the artifact signer role, run `sign-runtime-artifacts.sh` for the bucket and KMS key. Confirm both manifest objects are versioned in the bucket.
3. In a second reviewed apply, increment `runtime_release_id` to roll HA nodes. For Lean, restart only after the signing command succeeds.

Never grant the EC2 runtime role `kms:Sign`, and never use the root or intermediate CA key for artifact signatures. A signature authenticates the S3 runtime payload; it does not replace the separate image-digest, image-signature, and SBOM controls required for container images.
