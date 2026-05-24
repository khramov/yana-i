import { NextResponse } from "next/server";
import { computePositions } from "@/lib/portfolio";
import { fetchQuotes } from "@/lib/yahoo";
import { getBaseCurrency, getRate } from "@/lib/fx";
import { db } from "@/lib/db";
import { priceCache } from "@/lib/db/schema";
import { inArray } from "drizzle-orm";

const CACHE_TTL_SECONDS = 15 * 60;

export async function GET() {
  const baseCurrency = getBaseCurrency();
  const positions = computePositions();

  if (positions.length === 0) {
    return NextResponse.json({ baseCurrency, positions: [] });
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

  // Pre-fetch FX rates for all unique native currencies
  const nativeCurrencies = new Set(
    positions.map((p) => priceMap.get(p.ticker)?.currency ?? p.currency)
  );
  const fxRateMap = new Map<string, number>();
  await Promise.all(
    [...nativeCurrencies].map(async (cur) => {
      fxRateMap.set(cur, await getRate(cur, baseCurrency));
    })
  );

  const result = positions.map((p) => {
    const entry = priceMap.get(p.ticker);
    const nativeCurrency = entry?.currency ?? p.currency;
    const fxRate = fxRateMap.get(nativeCurrency) ?? 1;
    const currentPrice = entry?.price ?? null;
    // Per-share values stay in native currency; portfolio totals in base
    const marketValue = currentPrice != null ? p.sharesHeld * currentPrice * fxRate : null;
    const costBasisBase = p.totalCostBasis * fxRate;
    const unrealizedPnl = marketValue != null ? marketValue - costBasisBase : null;
    const pnlPct =
      unrealizedPnl != null && costBasisBase > 0
        ? (unrealizedPnl / costBasisBase) * 100
        : null;

    return {
      holdingId: p.holdingId,
      ticker: p.ticker,
      name: p.name,
      sharesHeld: p.sharesHeld,
      avgCost: p.avgCost,         // native currency, per-share
      nativeCurrency,             // for formatting avgCost and currentPrice
      currentPrice,               // native currency, per-share
      marketValue,                // base currency
      unrealizedPnl,              // base currency
      pnlPct,
    };
  });

  return NextResponse.json({ baseCurrency, positions: result });
}
