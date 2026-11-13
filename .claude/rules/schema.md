# SQLite Schema

From `schema_sql` in `libwimg/src/db.zig` (migrations below it add the same
columns to older DBs and drop the old `embeddings` table). Amounts are integer
cents, `category` is the integer ID from `categories.zig`, `updated_at` is unix
ms for LWW sync, `deleted` is a soft-delete tombstone.

```sql
CREATE TABLE transactions (
  id TEXT PRIMARY KEY,
  date_year INTEGER NOT NULL,
  date_month INTEGER NOT NULL,
  date_day INTEGER NOT NULL,
  description TEXT NOT NULL,
  amount_cents INTEGER NOT NULL,
  currency TEXT NOT NULL DEFAULT 'EUR',
  category INTEGER NOT NULL DEFAULT 0,
  account TEXT NOT NULL DEFAULT '',
  excluded INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_transactions_date ON transactions(date_year, date_month, date_day);

-- "Vorgemerkt" from the last FinTS fetch. Replaced per account on every
-- fetch, never synced, never in totals.
CREATE TABLE pending_transactions (
  id TEXT PRIMARY KEY,
  date_year INTEGER NOT NULL,
  date_month INTEGER NOT NULL,
  date_day INTEGER NOT NULL,
  description TEXT NOT NULL,
  amount_cents INTEGER NOT NULL,
  currency TEXT NOT NULL DEFAULT 'EUR',
  category INTEGER NOT NULL DEFAULT 0,
  account TEXT NOT NULL DEFAULT ''
);

CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE rules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pattern TEXT NOT NULL,
  category INTEGER NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,       -- learned rules use 1
  updated_at INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  bank TEXT NOT NULL DEFAULT '',
  color TEXT NOT NULL DEFAULT '#4361ee',
  deleted INTEGER NOT NULL DEFAULT 0,
  balance_cents INTEGER NOT NULL DEFAULT 0,
  balance_date TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE undo_history (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  op INTEGER NOT NULL,
  tbl TEXT NOT NULL,
  row_id TEXT NOT NULL,
  col TEXT,
  old_val TEXT,
  new_val TEXT,
  undone INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE recurring_patterns (
  id TEXT PRIMARY KEY,
  merchant TEXT NOT NULL,
  amount INTEGER NOT NULL,
  interval TEXT NOT NULL,
  category INTEGER NOT NULL DEFAULT 0,
  last_seen TEXT NOT NULL,
  next_due TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  prev_amount INTEGER,
  updated_at INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE snapshots (
  id TEXT PRIMARY KEY,                       -- "2026-03"
  date TEXT NOT NULL,
  net_worth INTEGER NOT NULL DEFAULT 0,
  income INTEGER NOT NULL DEFAULT 0,
  expenses INTEGER NOT NULL DEFAULT 0,
  tx_count INTEGER NOT NULL DEFAULT 0,
  breakdown TEXT NOT NULL DEFAULT '[]',      -- by_category JSON
  updated_at INTEGER NOT NULL DEFAULT 0
);

-- Kept for cheap resurrection; no UI since 2026-05-14.
CREATE TABLE debts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  total INTEGER NOT NULL,
  paid INTEGER NOT NULL DEFAULT 0,
  monthly INTEGER NOT NULL DEFAULT 0,
  deleted INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE savings_goals (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon TEXT NOT NULL DEFAULT '🎯',
  target INTEGER NOT NULL,
  current INTEGER NOT NULL DEFAULT 0,
  deadline TEXT,
  deleted INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0
);
```
