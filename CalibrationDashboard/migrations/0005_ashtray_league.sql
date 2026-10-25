CREATE TABLE league_members (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  alias TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  revoked_at INTEGER
);
CREATE INDEX league_members_expiration ON league_members(expires_at);

CREATE TABLE league_scores (
  member_id TEXT NOT NULL REFERENCES league_members(id) ON DELETE CASCADE,
  season_start TEXT NOT NULL,
  count INTEGER NOT NULL CHECK(count >= 0 AND count <= 100000),
  revision INTEGER NOT NULL CHECK(revision > 0),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(member_id, season_start)
);
CREATE INDEX league_scores_season ON league_scores(season_start, count DESC, member_id);
