-- Migration 035 (down): reverse the rename + drop the fee columns.
-- Inherits the same idempotency and safety guards as 033.
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
