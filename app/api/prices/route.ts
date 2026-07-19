import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { priceCache } from "@/lib/db/schema";
import { fetchQuotes } from "@/lib/yahoo";
import { inArray } from "drizzle-orm";
import { requireUser } from "@/lib/auth";

const CACHE_TTL_SECONDS = 15 * 60;

export async function GET(req: Request) {
  await requireUser();
  const { searchParams } = new URL(req.url);
  const raw = searchParams.get("tickers") ?? "";
  const tickers = raw
    .split(",")
    .map((t) => t.trim().toUpperCase())
    .filter(Boolean);

  if (tickers.length === 0) return NextResponse.json([]);

  const now = Math.floor(Date.now() / 1000);
  const cached = db
    .select()
    .from(priceCache)
    .where(inArray(priceCache.ticker, tickers))
    .all();

  const fresh = cached.filter((c) => now - c.updatedAt < CACHE_TTL_SECONDS);
  const freshSet = new Set(fresh.map((c) => c.ticker));
  const stale = tickers.filter((t) => !freshSet.has(t));

  if (stale.length > 0) {
    const quotes = await fetchQuotes(stale);
    for (const q of quotes) {
      db.insert(priceCache)
        .values({ ticker: q.ticker, price: q.price, currency: q.currency, updatedAt: now })
        .onConflictDoUpdate({
          target: priceCache.ticker,
          set: { price: q.price, currency: q.currency, updatedAt: now },
        })
        .run();
    }
    const updated = db
      .select()
      .from(priceCache)
      .where(inArray(priceCache.ticker, stale))
      .all();
    return NextResponse.json([...fresh, ...updated]);
  }

  return NextResponse.json(fresh);
}
