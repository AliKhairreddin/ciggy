-- Private, derived chart data follows the source row's deletion and expiry.
ALTER TABLE recordings ADD COLUMN overview_json TEXT;
