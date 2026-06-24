-- Migration 035: byte-identical content to migration 033 (committed
-- twice by mistake). Kept in the filesystem because golang-migrate's
-- schema_migrations table holds these version numbers, and removing
-- the file would corrupt production DBs that applied it. Inherits the
-- same idempotent rename guard as 033.
ALTER TABLE vault_transactions ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE vault_transactions ADD COLUMN IF NOT EXISTS shares_minted_or_burned NUMERIC(28, 8);
ALTER TABLE vault_transactions ADD COLUMN IF NOT EXISTS share_price_at_time NUMERIC(28, 8);
ALTER TABLE vault_transactions ADD COLUMN IF NOT EXISTS fee_charged NUMERIC(28, 8);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND table_name = 'vault_transactions'
      AND column_name = 'tx_hash'
  ) THEN
    ALTER TABLE vault_transactions RENAME COLUMN tx_hash TO transaction_hash;
  END IF;
END
$$ LANGUAGE plpgsql;
