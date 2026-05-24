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
`);

// Non-destructive column additions for existing databases
const holdingsCols = (sqlite.prepare("PRAGMA table_info(holdings)").all() as { name: string }[]).map((c) => c.name);
if (!holdingsCols.includes("sector")) sqlite.exec("ALTER TABLE holdings ADD COLUMN sector TEXT");
if (!holdingsCols.includes("asset_class")) sqlite.exec("ALTER TABLE holdings ADD COLUMN asset_class TEXT DEFAULT 'stock'");
if (!holdingsCols.includes("currency")) sqlite.exec("ALTER TABLE holdings ADD COLUMN currency TEXT DEFAULT 'USD'");

export const db = drizzle(sqlite, { schema });
