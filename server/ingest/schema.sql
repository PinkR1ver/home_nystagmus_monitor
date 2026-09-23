CREATE TABLE IF NOT EXISTS accounts (
 id uuid PRIMARY KEY, label text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS api_tokens (
 token_hash text PRIMARY KEY, account_id uuid NOT NULL REFERENCES accounts(id),
 label text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz
);
CREATE SEQUENCE IF NOT EXISTS change_revision;
CREATE TABLE IF NOT EXISTS records (
 account_id uuid NOT NULL REFERENCES accounts(id), record_id text NOT NULL,
 task_type text NOT NULL CHECK(task_type IN ('eye','standing','gait','sts','imu')),
 metadata jsonb NOT NULL, metadata_hash text NOT NULL,
 status text NOT NULL DEFAULT 'uploading' CHECK(status IN ('uploading','complete','archived')),
 revision bigint NOT NULL DEFAULT nextval('change_revision'),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(account_id,record_id)
);
CREATE INDEX IF NOT EXISTS records_sync ON records(account_id,revision);
CREATE TABLE IF NOT EXISTS artifacts (
 account_id uuid NOT NULL, record_id text NOT NULL, name text NOT NULL,
 sha256 text NOT NULL, byte_size bigint NOT NULL CHECK(byte_size>0), content_type text NOT NULL,
 storage_key text NOT NULL UNIQUE, created_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz,
 PRIMARY KEY(account_id,record_id,name),
 FOREIGN KEY(account_id,record_id) REFERENCES records(account_id,record_id)
);
CREATE TABLE IF NOT EXISTS reports (
 account_id uuid NOT NULL, record_id text NOT NULL,
 origin text NOT NULL CHECK(origin IN ('client','server')), version text NOT NULL,
 outcome text NOT NULL CHECK(outcome IN ('analyzed','unable_to_analyze')),
 payload jsonb NOT NULL, payload_hash text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(account_id,record_id,origin,version),
 FOREIGN KEY(account_id,record_id) REFERENCES records(account_id,record_id)
);
CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY, applied_at timestamptz DEFAULT now());
INSERT INTO schema_migrations(version) VALUES(1) ON CONFLICT DO NOTHING;

-- Additive v2: BEFAST stores client feature/self-report snapshots, no required raw media.
BEGIN;
ALTER TABLE records DROP CONSTRAINT IF EXISTS records_task_type_check;
ALTER TABLE records ADD CONSTRAINT records_task_type_check
 CHECK(task_type IN ('eye','standing','gait','sts','imu','befast'));
INSERT INTO schema_migrations(version) VALUES(2) ON CONFLICT DO NOTHING;
COMMIT;
