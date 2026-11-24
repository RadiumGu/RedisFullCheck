# TLS validation (Tokyo, ap-northeast-1)

`setup.sh` builds an isolated VPC + t4g.small runner + 4 ElastiCache clusters (TLS in-transit):
Redis OSS 7.0 and Valkey 9.0, each standalone and cluster-mode (Valkey ones also use AUTH token).
`runner_test.sh` runs on the runner (local plaintext source :6400, mTLS source :6401 with private CA).
`teardown.sh` removes everything. `ssm.sh`/`creds.sh` are helpers.

New flags (per side, `--source*` / `--target*`):
`tls`, `tlsinsecure`, `tlscacert`, `tlscert`, `tlskey`, `tlsservername`.
Cluster example: `-t master@clustercfg.xxx.cache.amazonaws.com:6379 --targetdbtype 1 --targettls -a <token>`

Results (2026-11-24): all 16 cases pass — plaintext/mTLS/TLS sources to all 4 targets, cluster<->cluster
and standalone<->standalone with TLS both sides, wrong-CA rejected, insecure accepted, injected drift detected.
Without `--targettls`, the tool hangs against a TLS endpoint (no clean error; use a timeout).
