# CA ceremony

Terraform creates two `ECC_NIST_P256`, `SIGN_VERIFY` KMS keys. It does **not** create CA private keys in state. The controlled ceremony signs public certificates with those KMS keys.

## Prerequisites

- The root key was enabled with a reviewed, time-bound apply.
- The operator is using short-lived AWS credentials (prefer AWS IAM Identity Center); the profile/config directory is supplied explicitly through `AWS_SHARED_CONFIG_DIR`.
- `ROOT_KEY_ID`, `INTERMEDIATE_KEY_ID`, and `ARTIFACT_BUCKET` came from the reviewed Terraform outputs.
- The ceremony operator role is one of `root_ceremony_role_arns` in Terraform, and no runtime role is in that list.

## Run

```sh
AWS_REGION=eu-central-1 \
AWS_SHARED_CONFIG_DIR=/absolute/path/to/aws-config \
ROOT_KEY_ID=... INTERMEDIATE_KEY_ID=... \
PKI_NAME='Example Company' \
./ceremony/create-hierarchy.sh

AWS_REGION=eu-central-1 \
AWS_SHARED_CONFIG_DIR=/absolute/path/to/aws-config \
ARTIFACT_BUCKET=... \
./ceremony/publish-public-certificates.sh
```

Review the certificate subjects, key usages, validity periods, and chain before publishing. Then apply the same Terraform environment with `root_key_enabled = false`; confirm the CloudTrail alarm path for root-key activity.

The output directory is gitignored to prevent accidental publication. Only reviewed public certificates may later be copied into a versioned release artifact.

## Independent regional intermediate

For a second region, keep the existing reviewed root certificate and sign only the new regional intermediate:

```sh
ROOT_AWS_REGION=eu-central-1 \
INTERMEDIATE_AWS_REGION=eu-west-1 \
AWS_SHARED_CONFIG_DIR=/absolute/path/to/aws-config \
ROOT_KEY_ID=<shared-root-key-id> INTERMEDIATE_KEY_ID=<eu-west-key-id> \
ROOT_CERT_PATH=/absolute/path/to/root_ca.crt \
OUTPUT_DIR=/absolute/path/to/eu-west-ceremony-output \
./ceremony/create-hierarchy.sh
```

Publish the existing root certificate and the new EU West intermediate to the EU West artifact bucket. The regional runtime never receives the root key.
