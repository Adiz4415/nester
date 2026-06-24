# Migration Runbook

This directory contains [golang-migrate](https://github.com/golang-migrate/migrate) SQL migration files for the Nester API database.

## Running Migrations

### Via Docker Compose (recommended for local dev)

Migrations run automatically on `make dev` when `RUN_MIGRATIONS=true` is set in `.env`.

### Manually with golang-migrate

```bash
# Apply all pending migrations
migrate -path apps/api/migrations -database "$DATABASE_DSN" up

# Apply migrations up to a specific version
migrate -path apps/api/migrations -database "$DATABASE_DSN" goto 12
```

### Check current version

```bash
migrate -path apps/api/migrations -database "$DATABASE_DSN" version
```

## Rolling Back

```bash
# Roll back one migration
migrate -path apps/api/migrations -database "$DATABASE_DSN" down 1

# Roll back N migrations
migrate -path apps/api/migrations -database "$DATABASE_DSN" down N
```

> **Warning:** Rolling back in production should be rare and done with a DB backup in hand. Always test the down migration locally first.

## Adding a New Migration

1. Find the next available sequential number:
   ```bash
   ls apps/api/migrations/ | sed 's/_.*//' | sort -n | uniq | tail -1
   ```
2. Check for conflicts (should print nothing):
   ```bash
   ls apps/api/migrations/ | sed 's/_.*//' | sort | uniq -d
   ```
3. Create the pair:
   ```
   NNN_descriptive_name.up.sql   — forward change
   NNN_descriptive_name.down.sql — exact reverse (no-op is acceptable if irreversible)
   ```

## ⚠️ Re-auth Required After Migration 009_add_user_roles

After deploying migration `009_add_user_roles`, **all existing admin JWT tokens are stale**. Tokens issued before this migration lack the `Roles` claim and will receive `403 Forbidden` on every role-gated admin endpoint.

**Resolution:** admins must log out and re-authenticate to receive a new token that includes their roles.

## Known Issues

- Numbering collisions exist at prefixes 007, 009, and 010. See [#523](https://github.com/Suncrest-Labs/nester/issues/523) for the fix tracking these conflicts.
- There are gaps in the sequence at 004 and 013 — these are expected (migrations were removed) and do not affect operation.

## _FIXME_ — migration 023 cannot run before 033 on a fresh database (fixed by 037)

Migration 023 (`vault_transactions_hash_unique.up.sql`) creates a `UNIQUE INDEX` on column `transaction_hash`. That column is only created by migration 033 (`update_vault_transactions.up.sql`) via `RENAME COLUMN tx_hash TO transaction_hash`. On a fresh database the numeric order is `023 → 033`, so the very first `migrate up` would crash at 023 with `column "transaction_hash" does not exist` before 033 ever renames it. Migration 035 is byte-identical to 033.

### Fix shipped in this branch

1. **`023` is now idempotent.** Its `CREATE UNIQUE INDEX` is wrapped in a `DO $$ ... IF EXISTS (information_schema.columns ...) ... END $$` guard, so on a fresh DB the migration is a safe no-op until 033/035 have renamed the column.
2. **`033` and `035` (duplicate) are now idempotent.** Their `RENAME COLUMN tx_hash TO transaction_hash` is wrapped in the same `IF EXISTS` guard so it is a no-op on a DB that has already been renamed (e.g. by a previous run or by 035 itself).
3. **New `037_consolidate_vault_transactions_index` actually creates the unique index** at the end of the chain, gated only by `CREATE UNIQUE INDEX IF NOT EXISTS`. After 033/035 have run, the column exists, and 037 is the canonical creator of the index on fresh DBs.

### Operator note: existing DBs hit a dirty-database state on next `migrate up`

Editing files 023, 033, and 035 changes the file content that migrators
already consider immutable. That breaks the audit trail in two different
ways depending on why the edited migration is being rejected:

1. **Dirty-state failure** (default `golang-migrate` v4 CLI): the engine
   records the in-progress version as `dirty=true` whenever a migration
   crashes midway. Editing an applied file does not by itself dirty the
   state, but if the operator's environment was already dirty (e.g.
   from an earlier incident), they need a recipe to recover. The error
   message looks like:

   ```
   error: Dirty database version 23. Reason: migration 023 has been modified
   since it was applied.
   ```

2. **Checksum-mismatch failure** (only when running with a driver /
   wrapper that records `schema_migrations.checksum`): the file content
   no longer matches the hash recorded when the migration was first
   applied. The error message in this case is the same in many builds,
   so diagnosing which case applies requires inspecting
   `schema_migrations` directly.

The recipes below cover both cases. They are conservative: each step
idempotently nudges the recoverable state toward "clean, current, and
hash-consistent."

#### Step 0: capture the current state

```bash
migrate -path apps/api/migrations -database "$DATABASE_DSN" version
# and for drivers that record a checksum:
psql "$DATABASE_DSN" -c \
  "SELECT version, dirty, length(checksum) AS checksum_len
     FROM schema_migrations;"
```

If `dirty=false` and (where applicable) the checksum column matches the
current file content, no operator action is needed and you can skip to
`migrate up` directly.

#### Step 1: force the database clean (`golang-migrate` v4)

`migrate force` is one of the eight v4 subcommands (`create`, `up`,
`down`, `drop`, `force`, `version`, `goto` is the canonical list — note
that **`migrate checksum` does not exist** in the v4 CLI). `force` does
two things atomically:

- Sets `schema_migrations.version` to the integer you pass.
- Sets `schema_migrations.dirty` to `false`.
- It does **not** read or update the `checksum` column.

For this PR, the safe values depend on which migrations your env already
applied:

```bash
# If the DB was already past 035 before this branch deployed — i.e. you
# are recovering from a checksum mismatch on the edited files:
migrate -path apps/api/migrations -database "$DATABASE_DSN" force 35

# Re-applying 023/033/035 is then a no-op thanks to the guards, and 037
# is the only genuinely new migration.
migrate -path apps/api/migrations -database "$DATABASE_DSN" up
```

> Do **not** force a version above your current applied set without
> auditing the database manually for the gap. Forcing ahead then
> running `up` will skip the gap's migrations — e.g. `force 37` on a DB
> that never recorded 036 will treat 036 as already-applied and skip it
> on the next `up`, leaving the schema behind the migration version.

#### Step 2 (only if checksums are verified): rewrite `schema_migrations.checksum`

For drivers/wrappers that record `schema_migrations.checksum`:

```bash
# Compute the new sha256 of each edited file exactly the way the driver
# does (most use sha256 of the raw file bytes; verify with your driver
# docs if you are unsure):
sha256sum apps/api/migrations/023_vault_transactions_hash_unique.up.sql \
          apps/api/migrations/033_update_vault_transactions.up.sql \
          apps/api/migrations/035_update_vault_transactions.up.sql
```

Then UPDATE the table — no `migrate` CLI subcommand does this for you
in v4. Example with `psql`:

```sql
UPDATE schema_migrations
   SET checksum = '<hash-from-sha256sum-on-023_vault_transactions_hash_unique.up.sql>'
 WHERE version = 23;
-- repeat the pattern for versions 33 and 35.
```

#### Step 3 (alternative): pass `--skip-verify-checksum` at runtime

If your `golang-migrate` build supports the flag (check with
`migrate --help` — older v4.4–v4.5 binaries do not), you can sidestep
the checksum check outright:

```bash
migrate -path apps/api/migrations -database "$DATABASE_DSN" \
    up --skip-verify-checksum
```

#### Non-CLI environments (psql only)

Steps 0–3 above assume the `migrate` CLI is available in the deployment
environment. In containers / CI runners that ship only `psql`, the same
recovery is achievable with raw SQL:

```sql
-- Capture the current state.
SELECT version, dirty, checksum IS NOT NULL AS has_checksum
  FROM schema_migrations;

-- Clear the dirty flag for the edited versions.
UPDATE schema_migrations SET dirty = false WHERE version IN (23, 33, 35);

-- If your driver records a checksum and the file no longer matches,
-- rewrite it via Step 2's sha256 + UPDATE pattern.
```

**Cross-tool note**: the above assumes the standard `golang-migrate`
`schema_migrations` table layout (`version BIGINT`, `dirty BOOLEAN`,
optional `checksum TEXT`). If your environment uses a different
migration tool, the table name and column shape will differ — consult
your tool's "reset dirty / checksum" docs. For multi-tool environments
(e.g. `golang-migrate` in CI, a third-party tool in prod), pick **one**
authority per environment and stick to it.

### Concurrency note

The `DO $$ ... IF EXISTS ... ALTER TABLE ...` blocks in `023`, `033`,
`035` run in a single transaction per migration, so concurrent
`migrate up` invocations cannot observe a torn state (a missing or
half-renamed column).

### Regression coverage

The integration test `apps/api/internal/service/vault_service_yield_cycle_integration_test.go`
already exercises the migration chain in numeric order against a fresh
Postgres via its `applyYieldCycleMigrations` helper — that is the
regression test for this PR. If that test ever fails on a future
re-order of files 023/033/035/037, the ordering bug has returned.

### When to remove these guards

Once a critical mass of production DBs have been migrated past version 037 and the checksum reset has been applied broadly, the guards in 023/033/035 can be removed and the original blunt statements restored. Until then, the guards are a one-time operational tax vs. the recurring tax of `migrate up` failing on every CI run and new developer setup. Tracked as part of the v2.4 milestone cleanup.
