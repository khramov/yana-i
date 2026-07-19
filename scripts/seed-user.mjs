// One-off seed: create a user and give it any pre-existing (unowned) portfolios.
// Usage: node scripts/seed-user.mjs <email> <password>
//   or:  SEED_EMAIL=... SEED_PASSWORD=... node scripts/seed-user.mjs
//
// The password hash format ("scrypt$<saltHex>$<hashHex>") matches lib/password.ts.

import Database from "better-sqlite3";
import { randomBytes, scryptSync } from "crypto";
import path from "path";

const email = (process.argv[2] ?? process.env.SEED_EMAIL ?? "").trim().toLowerCase();
const password = process.argv[3] ?? process.env.SEED_PASSWORD ?? "";

if (!email || !password) {
  console.error("Usage: node scripts/seed-user.mjs <email> <password>");
  process.exit(1);
}

function hashPassword(pw) {
  const salt = randomBytes(16);
  const hash = scryptSync(pw, salt, 64);
  return `scrypt$${salt.toString("hex")}$${hash.toString("hex")}`;
}

const db = new Database(path.join(process.cwd(), "data", "yana.db"));
db.pragma("journal_mode = WAL");

// Idempotent DDL so the script works even before the app has booted.
db.exec(`
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
  CREATE TABLE IF NOT EXISTS portfolios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    base_currency TEXT NOT NULL DEFAULT 'EUR',
    created_at INTEGER NOT NULL DEFAULT (unixepoch())
  );
`);

const portfolioCols = db.prepare("PRAGMA table_info(portfolios)").all().map((c) => c.name);
if (!portfolioCols.includes("user_id")) {
  db.exec("ALTER TABLE portfolios ADD COLUMN user_id INTEGER");
}

const now = Math.floor(Date.now() / 1000);
const hash = hashPassword(password);

const existing = db.prepare("SELECT id FROM users WHERE email = ?").get(email);
let userId;
if (existing) {
  db.prepare("UPDATE users SET password_hash = ? WHERE id = ?").run(hash, existing.id);
  userId = existing.id;
  console.log(`Updated password for existing user ${email} (id ${userId}).`);
} else {
  const info = db
    .prepare("INSERT INTO users (email, password_hash, created_at) VALUES (?, ?, ?)")
    .run(email, hash, now);
  userId = info.lastInsertRowid;
  console.log(`Created user ${email} (id ${userId}).`);
}

const adopted = db
  .prepare("UPDATE portfolios SET user_id = ? WHERE user_id IS NULL")
  .run(userId);
console.log(`Adopted ${adopted.changes} previously unowned portfolio(s).`);

db.close();
