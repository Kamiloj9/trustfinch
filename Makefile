.DEFAULT_GOAL := help

.PHONY: help test test-static test-runtime-bootstrap test-iac test-integration format

help:
	@printf '%s\n' 'Targets:' '  make test              Run every local Docker-based check' '  make test-static       Check repository security invariants' '  make test-runtime-bootstrap Verify the Amazon Linux runtime prerequisites' '  make test-iac          Format and validate Terraform in Docker' '  make test-integration  Run disposable local step-ca issuance tests' '  make format            Format Terraform in Docker'

test: test-static test-runtime-bootstrap test-iac test-integration

test-static:
	@./tests/test-static.sh

test-runtime-bootstrap:
	@./tests/test-runtime-bootstrap.sh

test-iac:
	@./tests/test-iac.sh

test-integration:
	@./tests/test-local-ca.sh
	@./tests/test-local-ha.sh

format:
	@docker run --rm -v "$(CURDIR):/workspace" -w /workspace hashicorp/terraform@sha256:6bbb82d575aa7bd4f0a2c6e3a0838ab9590426c08a71d7a2783643f01004d356 fmt -recursive
