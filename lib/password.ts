import { randomBytes, scryptSync, timingSafeEqual } from "crypto";

// Password hashes are stored as "scrypt$<saltHex>$<hashHex>".
// Pure Node crypto — no external dependency. The seed script mirrors this format.
const KEYLEN = 64;

export function hashPassword(password: string): string {
  const salt = randomBytes(16);
  const hash = scryptSync(password, salt, KEYLEN);
  return `scrypt$${salt.toString("hex")}$${hash.toString("hex")}`;
}

export function verifyPassword(password: string, stored: string): boolean {
  const parts = stored.split("$");
  if (parts.length !== 3 || parts[0] !== "scrypt") return false;
  const salt = Buffer.from(parts[1], "hex");
  const expected = Buffer.from(parts[2], "hex");
  const actual = scryptSync(password, salt, expected.length);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
