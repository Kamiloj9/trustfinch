# Independent EU West profile

This HA stack has its own PostgreSQL state and intermediate KMS key. It does not create a root key: sign the regional intermediate with the shared root from the designated security region during a reviewed ceremony.

Do not copy PostgreSQL state, one-time tokens, or an intermediate key from eu-central-1.
