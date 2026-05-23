import { NextResponse } from "next/server";
import { computePositions } from "@/lib/portfolio";
import { fetchQuotes } from "@/lib/yahoo";
import { db } from "@/lib/db";
import { priceCache } from "@/lib/db/schema";
import { inArray } from "drizzle-orm";

const CACHE_TTL_SECONDS = 15 * 60;

export async function GET() {
  const positions = computePositions();

  if (positions.length === 0) {
    return NextResponse.json([]);
  }

  const tickers = positions.map((p) => p.ticker);
  const now = Math.floor(Date.now() / 1000);

  const cached = db
    .select()
    .from(priceCache)
    .where(inArray(priceCache.ticker, tickers))
    .all();

  const stale = tickers.filter((t) => {
    const hit = cached.find((c) => c.ticker === t);
    return !hit || now - hit.updatedAt > CACHE_TTL_SECONDS;
  });

  if (stale.length > 0) {
    const fresh = await fetchQuotes(stale);
    for (const q of fresh) {
      db.insert(priceCache)
        .values({ ticker: q.ticker, price: q.price, currency: q.currency, updatedAt: now })
        .onConflictDoUpdate({
          target: priceCache.ticker,
          set: { price: q.price, currency: q.currency, updatedAt: now },
        })
        .run();
    }
  }

  const allCached = db
    .select()
    .from(priceCache)
    .where(inArray(priceCache.ticker, tickers))
    .all();
  const priceMap = new Map(allCached.map((c) => [c.ticker, c]));

  const result = positions.map((p) => {
    const entry = priceMap.get(p.ticker);
    const currentPrice = entry?.price ?? null;
    const currency = entry?.currency ?? "USD";
    const marketValue = currentPrice != null ? p.sharesHeld * currentPrice : null;
    const unrealizedPnl =
      marketValue != null ? marketValue - p.totalCostBasis : null;
    const pnlPct =
      unrealizedPnl != null && p.totalCostBasis > 0
        ? (unrealizedPnl / p.totalCostBasis) * 100
        : null;

    return {
      holdingId: p.holdingId,
      ticker: p.ticker,
      name: p.name,
      sharesHeld: p.sharesHeld,
      avgCost: p.avgCost,
      totalCostBasis: p.totalCostBasis,
      currentPrice,
      currency,
      marketValue,
      unrealizedPnl,
      pnlPct,
    };
  });

  return NextResponse.json(result);
}
