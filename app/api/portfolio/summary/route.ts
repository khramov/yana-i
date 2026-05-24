import { NextResponse } from "next/server";
import { computePositions } from "@/lib/portfolio";
import { fetchQuotes } from "@/lib/yahoo";
import { db } from "@/lib/db";
import { priceCache, transactions } from "@/lib/db/schema";
import { inArray, eq } from "drizzle-orm";

const CACHE_TTL_SECONDS = 15 * 60;

export async function GET() {
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

  const enriched = open.map((p) => {
    const entry = priceMap.get(p.ticker);
    const currentPrice = entry?.price ?? null;
    const marketValue = currentPrice != null ? p.sharesHeld * currentPrice : null;
    const unrealizedPnl = marketValue != null ? marketValue - p.totalCostBasis : null;
    const pnlPct =
      unrealizedPnl != null && p.totalCostBasis > 0
        ? (unrealizedPnl / p.totalCostBasis) * 100
        : null;
    return { ...p, currentPrice, marketValue, unrealizedPnl, pnlPct };
  });

  let totalValue: number | null = null;
  let costBasis = 0;
  for (const p of enriched) {
    costBasis += p.totalCostBasis;
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
  const dividendsReceived = divTxns.reduce((sum, t) => sum + (t.price ?? 0), 0);

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
    totalValue,
    costBasis,
    unrealizedPnl,
    totalReturnPct,
    dividendsReceived,
    holdingsCount: enriched.length,
    top5,
  });
}
