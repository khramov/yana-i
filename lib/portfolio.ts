import { db } from "@/lib/db";
import { holdings, transactions, priceCache, portfolioSnapshots } from "@/lib/db/schema";
import { asc, eq, inArray } from "drizzle-orm";
import { fetchQuotes } from "@/lib/yahoo";
import { getBaseCurrency, getRate } from "@/lib/fx";

export interface PositionData {
  holdingId: number;
  ticker: string;
  name: string | null;
  sharesHeld: number;
  avgCost: number | null;
  totalCostBasis: number;
  currency: string;
}

export function computePositions(): PositionData[] {
  const allHoldings = db.select().from(holdings).all();
  const allTxns = db
    .select()
    .from(transactions)
    .orderBy(asc(transactions.date), asc(transactions.id))
    .all();

  const txnsByHolding = new Map<number, typeof allTxns>();
  for (const t of allTxns) {
    const list = txnsByHolding.get(t.holdingId) ?? [];
    list.push(t);
    txnsByHolding.set(t.holdingId, list);
  }

  return allHoldings.map((h) => {
    const txns = txnsByHolding.get(h.id) ?? [];
    let shares = 0;
    let avgCostPerShare = 0;
    let currency = "USD";

    for (const t of txns) {
      if (t.type === "buy" && t.shares != null && t.price != null) {
        currency = t.currency ?? "USD";
        const newShares = t.shares;
        const lotCost = newShares * t.price + t.fee;
        avgCostPerShare =
          shares + newShares > 0
            ? (shares * avgCostPerShare + lotCost) / (shares + newShares)
            : 0;
        shares += newShares;
      } else if (t.type === "sell" && t.shares != null) {
        shares = Math.max(0, shares - t.shares);
      }
    }

    const sharesHeld = Math.round(shares * 1e8) / 1e8; // float cleanup
    const totalCostBasis = sharesHeld * avgCostPerShare;

    return {
      holdingId: h.id,
      ticker: h.ticker,
      name: h.name,
      sharesHeld,
      avgCost: sharesHeld > 0 ? avgCostPerShare : null,
      totalCostBasis,
      currency,
    };
  });
}

const CACHE_TTL_SECONDS = 15 * 60;

export async function computePortfolioValue(): Promise<{
  totalValue: number | null;
  costBasis: number;
  baseCurrency: string;
}> {
  const baseCurrency = getBaseCurrency();
  const positions = computePositions().filter((p) => p.sharesHeld > 0);
  const tickers = positions.map((p) => p.ticker);

  if (tickers.length === 0) return { totalValue: null, costBasis: 0, baseCurrency };

  const now = Math.floor(Date.now() / 1000);
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

  const allCached = db.select().from(priceCache).where(inArray(priceCache.ticker, tickers)).all();
  const priceMap = new Map(allCached.map((c) => [c.ticker, c]));

  const nativeCurrencies = new Set(positions.map((p) => priceMap.get(p.ticker)?.currency ?? p.currency));
  const fxRateMap = new Map<string, number>();
  await Promise.all(
    [...nativeCurrencies].map(async (cur) => {
      fxRateMap.set(cur, await getRate(cur, baseCurrency));
    })
  );

  let totalValue: number | null = null;
  let costBasis = 0;
  for (const p of positions) {
    const entry = priceMap.get(p.ticker);
    const nativeCurrency = entry?.currency ?? p.currency;
    const fxRate = fxRateMap.get(nativeCurrency) ?? 1;
    const currentPrice = entry?.price ?? null;
    if (currentPrice != null) totalValue = (totalValue ?? 0) + p.sharesHeld * currentPrice * fxRate;
    costBasis += p.totalCostBasis * fxRate;
  }

  return { totalValue, costBasis, baseCurrency };
}

export async function writeSnapshotIfNeeded(): Promise<void> {
  const today = new Date().toISOString().slice(0, 10);
  const existing = db.select().from(portfolioSnapshots).where(eq(portfolioSnapshots.date, today)).get();
  if (existing) return;

  const { totalValue, costBasis, baseCurrency } = await computePortfolioValue();
  if (totalValue == null) return;

  db.insert(portfolioSnapshots)
    .values({
      date: today,
      totalValue,
      costBasis,
      baseCurrency,
      recordedAt: Math.floor(Date.now() / 1000),
    })
    .onConflictDoUpdate({
      target: portfolioSnapshots.date,
      set: { totalValue, costBasis, baseCurrency, recordedAt: Math.floor(Date.now() / 1000) },
    })
    .run();
}
