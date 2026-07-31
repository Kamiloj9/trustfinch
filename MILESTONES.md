# Trustfinch milestones

Trustfinch grows from a carefully controlled Lean PKI into an evidence-backed production service. These milestones describe the public product path; they are not promises to skip ceremony, policy, or recovery review.

## How we call a milestone complete

Every milestone needs its scoped acceptance evidence, a reviewed change, and a clean local `make test` plus `make public-audit`. Production milestones also require the relevant human ceremony and runbook evidence—passing infrastructure code alone is not a production sign-off.

| Milestone | Goal | Completion evidence | Status |
| --- | --- | --- | --- |
| **v0.1 · Nest built** | Publish a safe, reproducible Trustfinch foundation. | Lean/HA/multi-region Terraform profiles, guided Lean setup, Docker-only checks, public audit, Apache-2.0 project materials, CI, and a source/SBOM/evidence prerelease. | **Released** — [v0.1](https://github.com/Kamiloj9/trustfinch/releases/tag/v0.1) |
| **v0.2 · First verified flight** | Prove one real Lean deployment is operated safely. | A completed identity matrix, reviewed root/intermediate ceremony, one approved enrollment path with negative tests, sealed root evidence, and a recorded Lean recovery exercise. | **Planned** |
| **v0.3 · Two-wing availability** | Make a single region resilient to node loss. | Production HA deployment, ALB/ASG/RDS evidence, restricted issuance during node replacement, and tested backup/restore against the production recovery objective. | **Planned** |
| **v0.4 · Regional resilience** | Sustain a regional outage with independent intermediates. | EU Central and EU West deployment evidence, Route 53 failover test, regional enrollment rules, and a client bootstrap/renewal test through the secondary region. | **Planned** |
| **v1.0 · Operational trust** | Establish a maintainable, production-ready PKI operating model. | Approved PKI policy/CPS appropriate to the organisation, recurring recovery and intermediate-rotation exercises, alert ownership, vulnerability-response practice, and documented RTO/RPO achievement. | **Planned** |

## v0.1 · Nest built

Released scope:

- [x] AWS KMS-backed root and intermediate key architecture with explicit root disablement.
- [x] Lean, single-region HA, and independent multi-region Terraform profiles.
- [x] Safe guided Lean setup with resumable ceremony stages and no backend bootstrapping.
- [x] Local Docker acceptance, recovery, failover, broker, artifact-signature, container-supply-chain, setup-guard, and workflow checks.
- [x] Public-project safeguards: Apache-2.0, contribution and conduct guidance, security reporting policy, public audit, Dependabot, CI, and release evidence.
- [x] `v0.1` prerelease with source archive, SPDX SBOM, checksums, test summary, audit record, and evidence manifest.

## v0.2 · First verified flight

Focus: make the Lean path demonstrably safe for one real, narrowly scoped trust domain.

- [ ] Complete and approve the [identity → certificate policy matrix](pki/policies/identity-matrix.md) for the first issuer and workload set.
- [ ] Perform a reviewed root/intermediate ceremony and record the public certificate/fingerprint review.
- [ ] Configure exactly one approved provisioner, including its rejection/negative-path evidence.
- [ ] Record the root-disable verification and CloudTrail alarm evidence after the ceremony.
- [ ] Run and retain a Lean state recovery exercise using [the recovery runbook](runbooks/recovery.md).

## v0.3 · Two-wing availability

Focus: move from one host to a tested, single-region HA service.

- [ ] Complete [the production HA deployment runbook](runbooks/ha-deployment.md) with reviewed networking, TLS, RTO/RPO, and alarm targets.
- [ ] Prove issuance remains available through an ALB/ASG node-loss event.
- [ ] Exercise PostgreSQL backup/restore and verify operational alert routing and ownership.
- [ ] Promote only provisioners with approved policy rows and negative tests.

## v0.4 · Regional resilience

Focus: use independent regional intermediates beneath one root, rather than sharing mutable CA state across regions.

- [ ] Deploy and review both regional stacks with separate state, databases, intermediate keys, and artifact buckets.
- [ ] Complete the Route 53 failover and secondary-region enrollment exercise in [the multi-region runbook](runbooks/multi-region.md).
- [ ] Document regional token/replay boundaries and client trust/renewal behavior.
- [ ] Record the agreed regional RTO/RPO result.

## v1.0 · Operational trust

Focus: turn the proven platform into a durable service, not merely a deployed stack.

- [ ] Approve organisation-appropriate certificate policy and CPS documentation.
- [ ] Schedule recurring recovery, failover, key-ceremony, and intermediate-rotation exercises.
- [ ] Establish alert ownership, incident response, release review, and vulnerability-response practices.
- [ ] Demonstrate the agreed service objectives repeatedly, with retained evidence.

## What stays deliberately out of scope

Trustfinch will not call a feature complete just because it can be enabled. Long-lived device certificates with immediate revocation needs, OCSP requirements, broad IAM-role enrollment, and multi-region shared state each require their own reviewed design and acceptance tests.
