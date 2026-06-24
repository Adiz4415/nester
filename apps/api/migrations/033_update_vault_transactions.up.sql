-- Migration 033: add fee-tracking columns and (originally) rename the
-- transaction hash column from `tx_hash` to `transaction_hash`. To
-- safely re-run on DBs that have already applied this change (e.g. via
-- the byte-identical migration 035), the rename is now gated on the
-- old column's presence.
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
