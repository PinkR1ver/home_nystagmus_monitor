# Motion Lab cloud ingestion

- Created: 2026-09-21
- Status: Completed — backend deployed and verified; Android v0.5.0 client implemented separately
- User authorized deploying a backend database and collection upload API to the supplied ECS server.
- Keep existing services intact. Independent `/opt/motion-lab`, PostgreSQL, private file storage, account-scoped bearer credentials, HTTPS.
- Scope: eye / standing / gait / STS / IMU records, versioned local reports and raw artifacts; no claim of server-side inference.
- Preserve stable record IDs, retry idempotency, incremental sync, archive semantics and provenance of client vs server analysis.
- Acceptance: deployed health, authenticated upload/download, duplicate/conflict handling, account isolation, restart persistence, backups, TLS verification.

## Deployment / acceptance
- HTTPS `https://39.107.192.82`, PostgreSQL 18 database `motion_lab`, account-scoped collection API at `/v1`; app systemd service `motion-lab`, private API port 8789.
- Tables: accounts, api_tokens (hashes only), records, artifacts, reports (client/server provenance), schema_migrations. Raw files `/var/lib/motion-lab/objects`; code `/opt/motion-lab`.
- Existing Nginx 80/8443 sites untouched and verified HTTP 200 after deployment. New TLS 443 uses existing valid IP certificate and existing auto-renew timer.
- Synthetic integration tests passed: unauthorized/cross-account rejection, immutable/idempotent records, checksum mismatch, repeat/conflicting artifacts, report provenance, unavailable results, completion manifest, incremental sync/tombstones, archive/video cleanup, raw IMU and schema validation.
- Public verified HTTPS uploader ran twice with the same synthetic IMU directory: same revision 12; authenticated downloaded bytes matched exactly after service restart.
- Daily local backups configured, first backup completed; SQL restored into an isolated temporary database and record count verified. Restore-test database removed afterwards.
- Development credential generated outside repository (locations in operations README); root password never persisted.
- Only synthetic test data uploaded; no patient recordings used. One explicitly synthetic IMU record retained as deployment evidence.
- Current storage: 40 GB root disk, approximately 31 GB free before deployment. Seven daily same-disk backups are not off-site disaster recovery. Add off-host backup/storage before substantial collection.
- Subsequent Android v0.5.0 implementation now provides optional direct authenticated HTTPS sync, encrypted tokens, persistent per-account upload snapshots, retry/progress and incremental cloud history. See Android checkout `docs/CLOUD_SYNC.md` and `.agents/spec/android-cloud-sync.md`.
- No cloud inference was deployed; `complete` is upload state. Existing local eye/body reports remain client-origin.
- Added authenticated `/v1/me` for Android identity verification; deployed and exercised from real Android emulator.
- Authoritative schema, protocol and operations: `server/ingest/README.md`, `schema.sql`.
