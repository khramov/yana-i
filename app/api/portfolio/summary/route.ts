import { NextResponse } from "next/server";
import { computePositions } from "@/lib/portfolio";
import { fetchQuotes } from "@/lib/yahoo";
import { getBaseCurrency, getRate, toBase } from "@/lib/fx";
import { db } from "@/lib/db";
import { priceCache, transactions } from "@/lib/db/schema";
import { inArray, eq } from "drizzle-orm";

const CACHE_TTL_SECONDS = 15 * 60;

export async function GET() {
  const baseCurrency = getBaseCurrency();
  const positions = computePositions();
  const open = positions.filter((p) => p.sharesHeld > 0);
  const tickers = open.map((p) => p.ticker);
  const now = Math.floor(Date.now() / 1000);

  if (tickers.length > 0) {
    const cached = db.select().from(priceCache).where(inArray(priceCache.ticker, tickers)).all();
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
  }

  const allCached =
    tickers.length > 0
      ? db.select().from(priceCache).where(inArray(priceCache.ticker, tickers)).all()
      : [];
  const priceMap = new Map(allCached.map((c) => [c.ticker, c]));

  // Pre-fetch FX rates for all unique currencies
  const nativeCurrencies = new Set(open.map((p) => priceMap.get(p.ticker)?.currency ?? p.currency));
  const fxRateMap = new Map<string, number>();
  await Promise.all(
    [...nativeCurrencies].map(async (cur) => {
      fxRateMap.set(cur, await getRate(cur, baseCurrency));
    })
  );

  const enriched = open.map((p) => {
    const entry = priceMap.get(p.ticker);
    const nativeCurrency = entry?.currency ?? p.currency;
    const fxRate = fxRateMap.get(nativeCurrency) ?? 1;
    const currentPrice = entry?.price ?? null;
    const marketValue = currentPrice != null ? p.sharesHeld * currentPrice * fxRate : null;
    const costBasisBase = p.totalCostBasis * fxRate;
    const unrealizedPnl = marketValue != null ? marketValue - costBasisBase : null;
    const pnlPct =
      unrealizedPnl != null && costBasisBase > 0
        ? (unrealizedPnl / costBasisBase) * 100
        : null;
    return { ...p, currentPrice, marketValue, costBasisBase, unrealizedPnl, pnlPct };
  });

  let totalValue: number | null = null;
  let costBasis = 0;
  for (const p of enriched) {
    costBasis += p.costBasisBase;
    if (p.marketValue != null) totalValue = (totalValue ?? 0) + p.marketValue;
  }
  const unrealizedPnl = totalValue != null ? totalValue - costBasis : null;
  const totalReturnPct =
    unrealizedPnl != null && costBasis > 0 ? (unrealizedPnl / costBasis) * 100 : null;

  const divTxns = db
    .select()
    .from(transactions)
    .where(eq(transactions.type, "dividend"))
    .all();
  let dividendsReceived = 0;
  for (const t of divTxns) {
    dividendsReceived += await toBase(t.price ?? 0, t.currency ?? "USD");
  }

  const withValue = enriched
    .filter((p) => p.marketValue != null)
    .sort((a, b) => (b.marketValue ?? 0) - (a.marketValue ?? 0));

  const top5 = withValue.slice(0, 5).map((p) => ({
    ticker: p.ticker,
    name: p.name,
    marketValue: p.marketValue!,
    weight: totalValue ? (p.marketValue! / totalValue) * 100 : null,
    pnlPct: p.pnlPct,
  }));

  return NextResponse.json({
    baseCurrency,
    totalValue,
    costBasis,
    unrealizedPnl,
    totalReturnPct,
    dividendsReceived,
    holdingsCount: enriched.length,
    top5,
  });
}
