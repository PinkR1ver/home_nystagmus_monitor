# Motion Lab collection backend

Deployed 2026-09-21 at `https://39.107.192.82` (HTTPS 443).
This independent collection service leaves the older `server/main.py` analysis backend unchanged.

## Storage design

PostgreSQL database `motion_lab`, role/OS user `motionlab`; local Unix socket with peer authentication. No public database access.

| Table | Responsibility |
| --- | --- |
| accounts | Ownership / tenant boundary |
| api_tokens | Account-scoped bearer token hashes and revocation |
| records | Stable Android session ID, task type, versioned metadata, upload/complete/archive status, monotonic sync revision |
| artifacts | Original video / raw landmarks / IMU / context / ZIP references, size, SHA-256, deletion state |
| reports | JSONB reports, algorithm version, client/server provenance, analyzed/unable-to-analyze outcome |
| schema_migrations | Applied schema version |

`(account_id, record_id)` is the business key. Capture timestamps use ISO 8601 with timezone. Existing Android millisecond+UUID session directory names are accepted. Device details, subject pseudonym and test context remain separate from analysis. No subject name is required.

Files are outside web roots at `/var/lib/motion-lab/objects`. Binary videos do not live in database rows. JSONB preserves changing eye/body report structures, quality warnings, null metrics and model versions without inventing clinical fields. Reports from this endpoint are always marked `client`; future server analysis must use its own trusted writer. `complete` means upload committed, not server analysis completed.

## API protocol

All `/v1` endpoints require `Authorization: Bearer <token>`. Account identity is derived from the token, never a client-supplied account ID.

1. `PUT /v1/records/{recordId}`: `{schemaVersion:1, taskType:"eye|standing|gait|sts|imu", startedAt:"2026-09-21T08:00:00Z", durationSec:10, device:{}, context:{}, subjectId:null}`.
2. `PUT /v1/records/{recordId}/artifacts/{name}`: raw bytes plus `X-Content-SHA256`. Allowed names: `video.mp4`, `landmarks.json`, `test_context.json`, `eye_signals.csv`, `imu.csv`, `report.zip`, `imu.zip`. Max 300 MiB per file. Artifacts are opaque capture data; upload does not validate that video bytes decode.
3. Optional `PUT /v1/records/{recordId}/client-report`: `{version:"eye-post-v1", outcome:"analyzed|unable_to_analyze", payload:{...original report...}}`.
4. `POST /v1/records/{recordId}/complete`: `{artifacts:{"video.mp4":"<sha256>"}, reportVersion:"eye-post-v1"}`. Manifest must exactly match uploaded files. IMU requires CSV or ZIP; other tasks require original video. A raw-only record may omit reportVersion.
5. `GET /v1/records?after=0&limit=100`: incremental records, archivedRecordIds, nextCursor, hasMore. Persist cursor only after local merge; fetch pages until hasMore=false. Preserve local video path. Tombstones hide server entries but must not trigger unrequested local-file deletion.
6. `GET /v1/records/{recordId}`: metadata, artifact manifest, report versions. `GET .../artifacts/{name}` downloads the authorized file.
7. `POST /v1/records/{recordId}/archive`: preserve metadata/reports, hide from default listing, clean original video. Idempotent cleanup. Backups may retain video until their retention expires.

Exact retries are safe; different content under an existing immutable key returns 409. Complete records are immutable. Changed reports after completion require a new record ID in v1. JSON body limit 8 MiB. Full-file retry supported; byte-range resume not implemented. No background inference, account self-registration or mobile sync UI is included in this service.

`GET /health` is public; authenticated `GET /v1/schema` returns OpenAPI.

## Upload an Android session folder

`upload_session.py` matches the current Android `SessionStore` directory (`video.mp4`, `test_context.json`, `landmarks.json`, `eye_report.json` or `report.json`). Exported report ZIP alone excludes video and is insufficient for a video record. IMU folders can supply `imu.csv` or `imu.zip`.

```bash
python3 server/ingest/upload_session.py /path/to/1790000000000-session-id \
  --task eye --duration 10 \
  --credential-file /secure/path/development-credential.json
```

The uploader uses certificate verification; it never accepts plaintext HTTP. Retries require the same metadata arguments. For eye reports `unavailableReason` maps to unable_to_analyze.

Current Android application still has no INTERNET permission or sync UI. Integrating the API into the app (network permission, per-device credentials, upload queue, progress/retry and incremental merge) is a separate follow-up, not claimed complete by backend deployment. Never embed the development token in a distributed APK.

## Deployment and operations

- Code: `/opt/motion-lab`, systemd `motion-lab.service`, API `127.0.0.1:8789`, two workers.
- Database: PostgreSQL 18, database `motion_lab`. Data and indexes remain managed by the system PostgreSQL cluster.
- Nginx: `/etc/nginx/sites-available/motion-lab`, new 443 listener. Existing 80/8443 applications untouched.
- TLS: reuse existing Let's Encrypt IP certificate `/etc/letsencrypt/live/shi-survey`; existing `shi-certbot.timer` renews and reloads nginx. This short-lived certificate needs continued successful renewal.
- Packages: Ubuntu `postgresql`, `python3-psycopg`, `python3-fastapi`, `python3-uvicorn`, `python3-httpx`. No GPU or model runtime required.
- `deploy/bootstrap.sh` assumes packages, service user and directories already provisioned; applies idempotent schema and service configs. Do not run nginx config on another server without replacing certificate path/server_name.
- Token provisioning: `sudo -u motionlab python3 /opt/motion-lab/admin.py DEVICE_LABEL --output /var/lib/motion-lab/credential.json`; move credential to a restricted operator location immediately. `--account-id` issues a new token for an existing account. Set `api_tokens.revoked_at=now()` to revoke. No root password is stored in these sources.
- Initial development credential: server `/root/motion-lab/development-credential.json`; local `/Users/judew/.config/motion-lab/development-credential.json`, both mode 0600. Credentials are outside Git.
- Logs: `journalctl -u motion-lab`; access logging disabled to avoid retaining record identifiers. Process restart: `systemctl restart motion-lab`.
- Backups: `motion-lab-backup.timer` daily around 03:15 server time; `/var/backups/motion-lab/<UTC timestamp>/{database.dump,objects.tar.gz,COMPLETE}`; retain seven completed snapshots. SQL+committed objects snapshot takes the mutation advisory lock; long backups briefly delay upload commits. Backups contain credential hashes, not bearer tokens.
- Backup storage is on the same 40 GB system disk. This protects against logical errors but not disk/instance loss. Before significant real collection, add separate durable storage/off-host backup; videos and backup copies grow quickly. Uploads reject when less than file budget + 2 GiB reserve remains. No automatic expansion or quota billing is configured.
- Restore into an empty database owned by motionlab using `pg_restore --no-owner --no-acl -d DATABASE database.dump`, then extract objects.tar.gz under the data directory, retaining service ownership and private permissions. Stop writes while restoring production. Regenerate/revoke tokens as appropriate.
- Interrupted processes may leave unreferenced opaque upload files; no automatic orphan deletion is enabled in v1.

## Validation

`test_integration.py` runs against localhost using temporary synthetic accounts and removes its own data afterwards. Verifies unauthorized rejection, account isolation, immutable IDs, mismatched SHA-256, duplicate retry, download integrity, report provenance/conflict, completion manifest, incremental cursor, archive tombstones/video cleanup, raw-only IMU and validation. Never uses patient data.

Deployment acceptance results are recorded in `.agents/spec/motion-cloud-ingestion.md`.
