# Container image supply-chain runbook

Every image started by the CA runtime is immutable by digest. When container-image verification is enabled, the host checks a Cosign signature and an SPDX SBOM attestation for every image in the rendered Compose file before it renders secrets or starts a container. The trusted public key is embedded in the instance bootstrap; the private signing operation stays in the isolated KMS release-signing key.

## Build, scan, sign, and attest

Use a registry that the CA nodes can read. Mirror upstream `step-ca` and `caddy` images into a registry controlled by the release process, and build the GitLab broker image there. Resolve each pushed image to its digest—never sign or deploy a mutable tag.

From the reviewed release signer role, authenticate Docker to that registry and run:

```sh
ceremony/sign-container-image.sh \
  --image <registry>/<repository>@sha256:<digest> \
  --key awskms:///<runtime_artifact_signing_key_id> \
  --platform linux/arm64 \
  --sbom-output evidence/<image>.spdx.json \
  --scan-output evidence/<image>.trivy.json
```

For a private registry whose Docker credentials are stored in a file rather than a credential helper, add `--docker-config-dir <directory>`. Cosign receives the standard `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, and AWS region environment variables when they are set, including temporary credentials issued by an assumed release role. A developer using a local AWS profile or SSO cache can instead add `--aws-config-dir ~/.aws`; it is mounted read-only. On AWS CA nodes the bootstrap writes a short-lived ECR login to `/root/.docker`, which the verifier mounts read-only for Cosign.

The command fails on HIGH or CRITICAL Trivy vulnerability or secret findings, produces an SPDX JSON SBOM, uploads a Cosign signature, and uploads a signed `spdxjson` attestation. It submits both signatures to the transparency log by default. Retain the SBOM and Trivy JSON report with the release approval.

The local Docker acceptance test uses a fresh local key, registry, and `--tlog-upload false`; its verifier is explicitly passed `--allow-insecure-no-tlog`. That option is only for the disposable test and must never be added to a runtime systemd unit.

## Enable runtime verification

1. First apply `runtime_artifact_signing` with both `verification_enabled` and `image_verification_enabled` false. The resulting KMS key is a release-signing key only; do not use a CA key or grant `kms:Sign` to the EC2 role.
2. Mirror and sign every image that appears in the Compose file. This includes `step-ca`, and in Lean also `caddy`; it includes the GitLab broker whenever that service is enabled. Store the signature and SBOM attestation beside the image in its registry.
3. Set the signed mirror digests in `runtime_images`, for example:

   ```hcl
   runtime_images = {
     step_ca_image       = "123456789012.dkr.ecr.eu-central-1.amazonaws.com/pki-step-ca@sha256:<digest>"
     caddy_image         = "123456789012.dkr.ecr.eu-central-1.amazonaws.com/pki-caddy@sha256:<digest>"
     ecr_registry        = "123456789012.dkr.ecr.eu-central-1.amazonaws.com"
     ecr_repository_arns = [
       "arn:aws:ecr:eu-central-1:123456789012:repository/pki-step-ca",
       "arn:aws:ecr:eu-central-1:123456789012:repository/pki-caddy",
     ]
   }

   runtime_artifact_signing = {
     key_administrator_arns    = ["arn:aws:iam::123456789012:role/pki-release-key-admin"]
     artifact_signer_role_arns = ["arn:aws:iam::123456789012:role/pki-release-signer"]
     verification_enabled       = true
     image_verification_enabled = true
   }
   ```

   The Terraform guard rejects image verification without explicit digest-pinned mirrors. Image verification also requires artifact verification: the signed manifest authenticates the Compose file that selects the images. For a configured private ECR registry, the runtime role receives only `GetAuthorizationToken`, `BatchCheckLayerAvailability`, `BatchGetImage`, and `GetDownloadUrlForLayer` on the listed repositories. At startup it obtains a fresh ECR Docker login, which Cosign also receives read-only.
4. Apply this as a separately reviewed rollout. In HA, increment `runtime_release_id` in that apply. The host fails closed if a signature, a transparency-log entry, or an SPDX attestation is missing or invalid.

## Release and incident rules

- Sign and attest a new digest before changing its Terraform image reference. A signature for one digest never authorizes another digest.
- A Trivy scan result is evidence for the release, not a waiver. Triage findings before changing the scanner threshold; do not use `--ignore-unfixed` to bypass production findings.
- On an unexpected verification failure, keep the previously running HA instances available, inspect the registry signature/SBOM objects and the release evidence, then roll only after a reviewed correction.
- A digest pin is necessary but not sufficient: the Cosign public key, signed digest, transparency-log proof, and SBOM attestation are all checked at runtime.
