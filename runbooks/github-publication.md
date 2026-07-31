# Publishing Trustfinch on GitHub

Complete this checklist before pushing the repository to a public GitHub account. Public code cannot be made private retroactively once it has been cloned or forked.

## Before the first push

1. Run `make test` and `make public-audit` locally.
2. Inspect all reachable Git history for AWS credentials, private keys, Terraform state, real certificate material, internal DNS names, and customer identifiers. Rotate anything that was ever committed; removing a file from the current tree is insufficient.
3. Confirm `git status --short` is understood and that `.local/`, `.terraform/`, and `*.tfvars` are untracked.
4. Create an empty public repository named `trustfinch` under the intended owner. Do not add a remote README, license, or `.gitignore`; the local history contains the canonical versions.

## Repository settings

1. Enable private vulnerability reporting and confirm that the Security tab offers a private-report form.
2. Protect `main`: require pull requests, at least one approval, and passing GitHub Actions CI; disallow force pushes and branch deletion.
3. Protect release tags matching `v*`; only maintainers may create them.
4. Enable Dependabot alerts and security updates. Enable secret scanning and code scanning where available for the repository plan.
5. Set GitHub Actions default workflow permissions to read-only. The checked-in release workflow requests only `contents: write` for its release job.

## First release

1. Merge reviewed changes into `main` after local Docker validation.
2. Create the protected tag `v0.1` from the reviewed commit.
3. Confirm the release workflow attaches the source archive, SPDX SBOM, checksums, and release-evidence manifest. `v0.1` is intentionally marked as a prerelease.
4. Do not treat a source release as authorization to deploy infrastructure. Terraform deployment and KMS image signing remain separately controlled workflows.
