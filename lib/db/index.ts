import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import * as schema from "./schema";
import path from "path";
import fs from "fs";

const dataDir = path.join(process.cwd(), "data");
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

const sqlite = new Database(path.join(dataDir, "yana.db"));
sqlite.pragma("journal_mode = WAL");

sqlite.exec(`
  CREATE TABLE IF NOT EXISTS holdings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ticker TEXT NOT NULL UNIQUE,
    name TEXT,
    created_at INTEGER NOT NULL DEFAULT (unixepoch())
  );
  CREATE TABLE IF NOT EXISTS price_cache (
    ticker TEXT PRIMARY KEY,
    price REAL,
    currency TEXT,
    updated_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    holding_id INTEGER NOT NULL REFERENCES holdings(id),
    type TEXT NOT NULL,
    date TEXT NOT NULL,
    shares REAL,
    price REAL,
    fee REAL NOT NULL DEFAULT 0,
    tax REAL NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'USD',
    notes TEXT,
    created_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS fx_rates (
    from_currency TEXT NOT NULL,
    to_currency TEXT NOT NULL,
    rate REAL NOT NULL,
    fetched_at INTEGER NOT NULL,
    PRIMARY KEY (from_currency, to_currency)
  );
  CREATE TABLE IF NOT EXISTS portfolio_snapshots (
    date TEXT PRIMARY KEY,
    total_value REAL NOT NULL,
    cost_basis REAL NOT NULL,
    base_currency TEXT NOT NULL,
    recorded_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS dividend_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    holding_id INTEGER NOT NULL UNIQUE REFERENCES holdings(id),
    ex_div_date TEXT,
    pay_date TEXT,
    amount_per_share REAL,
    annual_dividend_rate REAL,
    frequency TEXT,
    fetched_at INTEGER NOT NULL
  );
`);

function cols(table: string): string[] {
  return (sqlite.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[]).map((c) => c.name);
}

// Non-destructive column additions for existing databases
const holdingsCols = cols("holdings");
if (!holdingsCols.includes("sector")) sqlite.exec("ALTER TABLE holdings ADD COLUMN sector TEXT");
if (!holdingsCols.includes("asset_class")) sqlite.exec("ALTER TABLE holdings ADD COLUMN asset_class TEXT DEFAULT 'stock'");
if (!holdingsCols.includes("currency")) sqlite.exec("ALTER TABLE holdings ADD COLUMN currency TEXT DEFAULT 'USD'");

// --- Multi-portfolio migration ---
sqlite.exec(`
  CREATE TABLE IF NOT EXISTS portfolios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    base_currency TEXT NOT NULL DEFAULT 'EUR',
    created_at INTEGER NOT NULL DEFAULT (unixepoch())
  );
  CREATE TABLE IF NOT EXISTS goals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    portfolio_id INTEGER NOT NULL,
    scope TEXT NOT NULL,
    target_key TEXT NOT NULL,
    target_pct REAL NOT NULL,
    created_at INTEGER NOT NULL,
    UNIQUE(portfolio_id, scope, target_key)
  );
`);

// Seed a default portfolio so existing data always has a home.
const portfolioCount = (sqlite.prepare("SELECT COUNT(*) AS n FROM portfolios").get() as { n: number }).n;
if (portfolioCount === 0) {
  sqlite
    .prepare("INSERT INTO portfolios (id, name, base_currency, created_at) VALUES (1, 'Main Portfolio', 'EUR', unixepoch())")
    .run();
}

// transactions: add portfolio_id (simple column add, default 1).
if (!cols("transactions").includes("portfolio_id")) {
  sqlite.exec("ALTER TABLE transactions ADD COLUMN portfolio_id INTEGER NOT NULL DEFAULT 1");
}

// --- Authentication / multi-user migration ---
sqlite.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL DEFAULT (unixepoch())
  );
  CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    expires_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL
  );
`);

// portfolios: add user_id (nullable). Existing portfolios stay unowned until the
// seeded user adopts them (see scripts/seed-user.mjs).
if (!cols("portfolios").includes("user_id")) {
  sqlite.exec("ALTER TABLE portfolios ADD COLUMN user_id INTEGER");
}

// Table rebuilds below change a UNIQUE/PRIMARY KEY, so they must DROP referenced
// tables. better-sqlite3 enables foreign_keys by default — disable during rebuild.
const needHoldingsRebuild = !cols("holdings").includes("portfolio_id");
const needSnapshotRebuild = !cols("portfolio_snapshots").includes("portfolio_id");

if (needHoldingsRebuild || needSnapshotRebuild) {
  sqlite.pragma("foreign_keys = OFF");

  // holdings: switch UNIQUE(ticker) -> UNIQUE(portfolio_id, ticker), add portfolio_id.
  if (needHoldingsRebuild) {
    sqlite.exec(`
      CREATE TABLE holdings_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        portfolio_id INTEGER NOT NULL DEFAULT 1,
        ticker TEXT NOT NULL,
        name TEXT,
        sector TEXT,
        asset_class TEXT DEFAULT 'stock',
        currency TEXT DEFAULT 'USD',
        created_at INTEGER NOT NULL DEFAULT (unixepoch()),
        UNIQUE(portfolio_id, ticker)
      );
      INSERT INTO holdings_new (id, portfolio_id, ticker, name, sector, asset_class, currency, created_at)
        SELECT id, 1, ticker, name, sector, asset_class, currency, created_at FROM holdings;
      DROP TABLE holdings;
      ALTER TABLE holdings_new RENAME TO holdings;
    `);
  }

  // portfolio_snapshots: switch PK(date) -> PK(portfolio_id, date), add portfolio_id.
  if (needSnapshotRebuild) {
    sqlite.exec(`
      CREATE TABLE portfolio_snapshots_new (
        portfolio_id INTEGER NOT NULL DEFAULT 1,
        date TEXT NOT NULL,
        total_value REAL NOT NULL,
        cost_basis REAL NOT NULL,
        base_currency TEXT NOT NULL,
        recorded_at INTEGER NOT NULL,
        PRIMARY KEY (portfolio_id, date)
      );
      INSERT INTO portfolio_snapshots_new (portfolio_id, date, total_value, cost_basis, base_currency, recorded_at)
        SELECT 1, date, total_value, cost_basis, base_currency, recorded_at FROM portfolio_snapshots;
      DROP TABLE portfolio_snapshots;
      ALTER TABLE portfolio_snapshots_new RENAME TO portfolio_snapshots;
    `);
  }

  sqlite.pragma("foreign_keys = ON");
}

export const db = drizzle(sqlite, { schema });
