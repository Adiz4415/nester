-- Migration 033 (down): undo the rename + drop the fee columns.
--
-- Safety: drop the index first. A naive `down` that renames the column
-- before down-migrating migration 037 will fail because Postgres
-- refuses to rename a column referenced by an active index. The
-- `IF EXISTS` makes this safe to call regardless of whether 023 or 037
-- have created the index in this environment.
--
-- Note: production code (RecordHarvest) references `transaction_hash`,
-- so down-migrating past 033 in production will break writes.
DROP INDEX IF EXISTS idx_vault_transactions_transaction_hash_unique;

ALTER TABLE vault_transactions DROP COLUMN IF EXISTS fee_charged;
ALTER TABLE vault_transactions DROP COLUMN IF EXISTS share_price_at_time;
ALTER TABLE vault_transactions DROP COLUMN IF EXISTS shares_minted_or_burned;
ALTER TABLE vault_transactions DROP COLUMN IF EXISTS user_id;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND table_name = 'vault_transactions'
      AND column_name = 'transaction_hash'
  ) THEN
    ALTER TABLE vault_transactions RENAME COLUMN transaction_hash TO tx_hash;
  END IF;
END
$$ LANGUAGE plpgsql;
