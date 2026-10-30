CREATE TABLE review_feedback (
  id TEXT PRIMARY KEY,
  participant_id TEXT NOT NULL REFERENCES participants(id) ON DELETE CASCADE,
  started_at INTEGER NOT NULL,
  ended_at INTEGER NOT NULL,
  body_json TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  expires_at INTEGER NOT NULL
);
CREATE INDEX review_feedback_period ON review_feedback(participant_id, started_at, ended_at);
CREATE INDEX review_feedback_expiration ON review_feedback(expires_at);
