CREATE TABLE participants (
  id TEXT PRIMARY KEY,
  alias TEXT NOT NULL,
  owner_email TEXT NOT NULL,
  token_hash TEXT UNIQUE,
  kind TEXT NOT NULL CHECK(kind IN ('app', 'import')),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  revoked_at INTEGER
);
CREATE INDEX participants_owner ON participants(owner_email, revoked_at);
CREATE UNIQUE INDEX import_alias ON participants(owner_email, alias) WHERE kind = 'import' AND revoked_at IS NULL;

CREATE TABLE pairing_codes (
  code_hash TEXT PRIMARY KEY,
  owner_email TEXT NOT NULL,
  alias TEXT,
  expires_at INTEGER NOT NULL,
  consumed_by TEXT
);

CREATE TABLE recordings (
  id TEXT PRIMARY KEY,
  participant_id TEXT NOT NULL REFERENCES participants(id),
  recording_id TEXT NOT NULL,
  object_key TEXT NOT NULL UNIQUE,
  body_hash TEXT NOT NULL,
  started_at REAL NOT NULL,
  ended_at REAL NOT NULL,
  sample_count INTEGER NOT NULL,
  sources_json TEXT NOT NULL,
  annotations_json TEXT NOT NULL DEFAULT '[]',
  label_revision INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL CHECK(state IN ('pending', 'ready', 'deleted')),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  UNIQUE(participant_id, recording_id)
);
CREATE INDEX recordings_participant_created ON recordings(participant_id, created_at);
CREATE INDEX recordings_recent ON recordings(state, started_at DESC, id);
CREATE INDEX recordings_expiration ON recordings(expires_at, state);

CREATE TABLE request_limits (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
