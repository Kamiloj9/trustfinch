#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTIONLINT_IMAGE="rhysd/actionlint@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667"

fail() {
  printf 'GitHub Actions test failed: %s\n' "$*" >&2
  exit 1
}

command -v docker >/dev/null || fail "docker is required"
command -v rg >/dev/null || fail "rg is required"

for required_file in \
  .github/workflows/ci.yml \
  .github/workflows/release.yml \
  .github/dependabot.yml \
  LICENSE \
  SECURITY.md \
  CONTRIBUTING.md \
  CODE_OF_CONDUCT.md; do
  [[ -f "${ROOT_DIR}/${required_file}" ]] || fail "missing ${required_file}"
done

docker run --rm \
  -v "${ROOT_DIR}:/repo:ro" \
  -w /repo \
  --entrypoint actionlint \
  "${ACTIONLINT_IMAGE}"

while IFS= read -r action_reference; do
  [[ "${action_reference}" =~ @[0-9a-f]{40}([[:space:]]|#|$) ]] \
    || fail "GitHub Action is not pinned to a full commit SHA: ${action_reference}"
done < <(rg --no-filename '^[[:space:]]*uses:' "${ROOT_DIR}/.github/workflows")

rg --quiet '^permissions:$' "${ROOT_DIR}/.github/workflows/ci.yml" \
  || fail "CI must declare default token permissions"
rg --quiet 'contents: read' "${ROOT_DIR}/.github/workflows/ci.yml" \
  || fail "CI must retain read-only contents access"
rg --fixed-strings --quiet 'make test' "${ROOT_DIR}/.github/workflows/ci.yml" \
  || fail "CI must run the complete local Docker test suite"
rg --fixed-strings --quiet 'apt-get install --yes ripgrep' "${ROOT_DIR}/.github/workflows/ci.yml" \
  || fail "CI must install the ripgrep prerequisite"
rg --fixed-strings --quiet 'docker-compose-linux-x86_64' "${ROOT_DIR}/.github/workflows/ci.yml" \
  || fail "CI must install the Docker Compose plugin"
rg --fixed-strings --quiet 'f9ebc6ebdb19d769b793c245a736caaeb198c62587f13b25c660c13b4987f959' "${ROOT_DIR}/.github/workflows/ci.yml" \
  || fail "CI must verify the Docker Compose plugin checksum"
rg --fixed-strings --quiet 'make public-audit' "${ROOT_DIR}/.github/workflows/ci.yml" \
  || fail "CI must scan source and reachable history"
rg --fixed-strings --quiet 'fetch-depth: 0' "${ROOT_DIR}/.github/workflows/ci.yml" \
  || fail "CI must fetch reachable history for the public audit"
rg --fixed-strings --quiet 'tags:' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must be tag-triggered"
rg --fixed-strings --quiet '"v*"' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must accept version tags"
rg --fixed-strings --quiet 'Release tag must be a safe v-prefixed semantic version' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must reject unsafe tag names"
rg --fixed-strings --quiet 'contents: write' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must explicitly scope release creation permission"
rg --fixed-strings --quiet 'gh release create' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must create a GitHub Release"
rg --fixed-strings --quiet 'apt-get install --yes ripgrep' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must install the ripgrep prerequisite"
rg --fixed-strings --quiet 'docker-compose-linux-x86_64' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must install the Docker Compose plugin"
rg --fixed-strings --quiet 'f9ebc6ebdb19d769b793c245a736caaeb198c62587f13b25c660c13b4987f959' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must verify the Docker Compose plugin checksum"
rg --fixed-strings --quiet 'git archive --format=tar.gz' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must create a tagged source archive"
rg --fixed-strings --quiet 'spdx-json' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must generate an SPDX SBOM"
rg --fixed-strings --quiet 'sha256sum' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must generate checksums"
rg --fixed-strings --quiet 'evidence.json' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must attach a release-evidence manifest"
rg --fixed-strings --quiet -- '--prerelease' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "release workflow must mark v0 releases as prereleases"
rg --fixed-strings --quiet '[[ "$PACKAGE_TAG" == v0.* ]]' "${ROOT_DIR}/.github/workflows/release.yml" \
  || fail "v0 releases must remain prereleases"
if rg --quiet 'AWS_|id-token:|terraform (apply|plan)' "${ROOT_DIR}/.github/workflows"; then
  fail "GitHub workflows must not receive AWS or Terraform deployment authority"
fi
rg --fixed-strings --quiet 'Apache License' "${ROOT_DIR}/LICENSE" \
  || fail "Apache-2.0 license is missing"
rg --fixed-strings --quiet 'Private vulnerability reporting' "${ROOT_DIR}/SECURITY.md" \
  || fail "security policy must direct reporters to private reporting"

printf 'GitHub Actions and public-project checks passed\n'
