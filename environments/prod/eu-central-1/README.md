# Production single-region profile

This directory is deliberately not an alias of the Lean/PoC environment. Production requires the Stage 2 and Stage 3 decisions from the plan: two Availability Zones, PostgreSQL/RDS Multi-AZ, ALB, backup/restore evidence, provisioner-specific negative tests, and an approved certificate policy/CPS.

Do not copy `environments/dev/eu-central-1` into production. Implement this profile only after the PoC acceptance tests and recovery exercise pass.
