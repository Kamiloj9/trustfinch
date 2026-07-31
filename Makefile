.DEFAULT_GOAL := help

.PHONY: help test test-static test-runtime-bootstrap test-artifact-signature test-container-image-supply-chain test-log-redaction test-iac test-integration test-recovery test-trustfinch-setup test-github-actions public-audit format

help:
	@printf '%s\n' 'Targets:' '  make test              Run every local Docker-based check' '  make test-static       Check repository security invariants' '  make test-runtime-bootstrap Verify the Amazon Linux runtime prerequisites' '  make test-artifact-signature Verify signed runtime artifacts reject tampering' '  make test-container-image-supply-chain Build, scan, sign, attest, and verify a disposable image' '  make test-log-redaction Verify CA logs redact one-time tokens' '  make test-iac          Format and validate Terraform in Docker' '  make test-integration  Run disposable local step-ca issuance tests' '  make test-recovery     Exercise Lean CA state backup and recovery in Docker' '  make test-trustfinch-setup Verify the guided setup script without AWS access' '  make test-github-actions Lint GitHub workflows and public-project controls' '  make public-audit      Scan tracked source and reachable Git history for leaks' '  make format            Format Terraform in Docker'

test: test-static test-runtime-bootstrap test-artifact-signature test-container-image-supply-chain test-log-redaction test-iac test-integration test-recovery test-trustfinch-setup test-github-actions

test-static:
	@./tests/test-static.sh

test-runtime-bootstrap:
	@./tests/test-runtime-bootstrap.sh

test-artifact-signature:
	@bash ./tests/test-artifact-signature.sh

test-container-image-supply-chain:
	@bash ./tests/test-container-image-supply-chain.sh

test-log-redaction:
	@./tests/test-log-redaction.sh

test-iac:
	@./tests/test-iac.sh

test-integration:
	@./tests/test-local-ca.sh
	@./tests/test-local-ha.sh
	@./tests/test-gitlab-broker.sh
	@./tests/test-iam-broker.sh

test-recovery:
	@./tests/test-local-recovery.sh

test-trustfinch-setup:
	@./tests/test-trustfinch-setup.sh

test-github-actions:
	@./tests/test-github-actions.sh

public-audit:
	@./tests/test-public-audit.sh

format:
	@docker run --rm -v "$(CURDIR):/workspace" -w /workspace hashicorp/terraform@sha256:6bbb82d575aa7bd4f0a2c6e3a0838ab9590426c08a71d7a2783643f01004d356 fmt -recursive
