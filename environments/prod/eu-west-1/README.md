# Second-region profile

This directory is reserved for the independent regional intermediate CA profile. It must not share Badger state, one-time tokens, or an intermediate key with `eu-central-1` unless the team explicitly accepts the stronger database replication and replay controls required by that alternative.

Build it after the single-region HA profile and its regional failover test are complete.
