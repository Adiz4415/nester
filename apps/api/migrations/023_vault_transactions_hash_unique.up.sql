-- Migration 023: was originally observed to crash on a fresh database
-- because it referenced column `transaction_hash`, which is created by
-- migration 033. To unblock clean-DB deploys without modifying the
-- checksum of files that production DBs may have already applied under
-- the original content, wrap the index creation in a guard: skip the
-- CREATE UNIQUE INDEX if the column does not yet exist. Migration 037
-- will create the index for fresh-DB chains once the rename has run.
--
-- Pre-existing semantics preserved: NULL hashes remain allowed and
-- distinct (Postgres treats NULLs as distinct in a unique index), so
-- legacy rows without a hash are unaffected.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND table_name = 'vault_transactions'
      AND column_name = 'transaction_hash'
  ) THEN
    CREATE UNIQUE INDEX IF NOT EXISTS idx_vault_transactions_transaction_hash_unique
      ON vault_transactions (transaction_hash);
  END IF;
END
$$ LANGUAGE plpgsql;
