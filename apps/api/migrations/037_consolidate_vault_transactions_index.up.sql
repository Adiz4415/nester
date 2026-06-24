-- Migration 037: ensure vault_transactions has the unique
-- transaction_hash index regardless of whether DB-deploys ran the
-- original 023 (which would have created it) or the now-guard-wrapped
-- 023 (which is a no-op on fresh DBs that hadn't yet reached the 033
-- rename). With 033/035 idempotent, the column now exists by the time
-- this migration runs, so the index can be created unconditionally.
--
-- Idempotency: CREATE UNIQUE INDEX IF NOT EXISTS makes this safe to
-- apply on any DB that already received the index via the original 023.
--
-- NULL behaviour preserved: NULLs are distinct in this index, so
-- existing legacy rows without a hash are unaffected.
CREATE UNIQUE INDEX IF NOT EXISTS idx_vault_transactions_transaction_hash_unique
    ON vault_transactions (transaction_hash);
