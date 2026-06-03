import { db } from "@/lib/db";
import { holdings, transactions, priceCache, portfolioSnapshots } from "@/lib/db/schema";
import { and, asc, eq, inArray } from "drizzle-orm";
import { fetchQuotes } from "@/lib/yahoo";
import { getRate } from "@/lib/fx";

export interface PositionData {
  holdingId: number;
  ticker: string;
  name: string | null;
  sharesHeld: number;
  avgCost: number | null;
  totalCostBasis: number;
  currency: string;
}

export function computePositions(portfolioId: number): PositionData[] {
  const allHoldings = db.select().from(holdings).where(eq(holdings.portfolioId, portfolioId)).all();
  const allTxns = db
    .select()
    .from(transactions)
    .where(eq(transactions.portfolioId, portfolioId))
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

export interface EnrichedPosition {
  holdingId: number;
  ticker: string;
  name: string | null;
  assetClass: string;
  sector: string | null;
  sharesHeld: number;
  nativeCurrency: string;
  currentPriceNative: number | null;
  currentPriceBase: number | null;
  marketValueBase: number | null;
}

const CACHE_TTL_SECONDS = 15 * 60;

/** Open positions enriched with refreshed prices and metadata, valued in base currency. */
export async function computeEnrichedPositions(
  portfolioId: number,
  baseCurrency: string
): Promise<EnrichedPosition[]> {
  const positions = computePositions(portfolioId).filter((p) => p.sharesHeld > 0);
  if (positions.length === 0) return [];

  const tickers = positions.map((p) => p.ticker);
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

  const holdingRows = db.select().from(holdings).where(eq(holdings.portfolioId, portfolioId)).all();
  const metaMap = new Map(holdingRows.map((h) => [h.id, h]));

  const nativeCurrencies = new Set(positions.map((p) => priceMap.get(p.ticker)?.currency ?? p.currency));
  const fxRateMap = new Map<string, number>();
  await Promise.all(
    [...nativeCurrencies].map(async (cur) => {
      fxRateMap.set(cur, await getRate(cur, baseCurrency));
    })
  );

  return positions.map((p) => {
    const entry = priceMap.get(p.ticker);
    const nativeCurrency = entry?.currency ?? p.currency;
    const fxRate = fxRateMap.get(nativeCurrency) ?? 1;
    const currentPriceNative = entry?.price ?? null;
    const meta = metaMap.get(p.holdingId);
    return {
      holdingId: p.holdingId,
      ticker: p.ticker,
      name: p.name,
      assetClass: meta?.assetClass ?? "stock",
      sector: meta?.sector ?? null,
      sharesHeld: p.sharesHeld,
      nativeCurrency,
      currentPriceNative,
      currentPriceBase: currentPriceNative != null ? currentPriceNative * fxRate : null,
      marketValueBase: currentPriceNative != null ? p.sharesHeld * currentPriceNative * fxRate : null,
    };
  });
}

export async function computePortfolioValue(
  portfolioId: number,
  baseCurrency: string
): Promise<{
  totalValue: number | null;
  costBasis: number;
  baseCurrency: string;
}> {
  const positions = computePositions(portfolioId).filter((p) => p.sharesHeld > 0);
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

export async function writeSnapshotIfNeeded(portfolioId: number, baseCurrency: string): Promise<void> {
  const today = new Date().toISOString().slice(0, 10);
  const existing = db
    .select()
    .from(portfolioSnapshots)
    .where(and(eq(portfolioSnapshots.portfolioId, portfolioId), eq(portfolioSnapshots.date, today)))
    .get();
  if (existing) return;

  const { totalValue, costBasis } = await computePortfolioValue(portfolioId, baseCurrency);
  if (totalValue == null) return;

  db.insert(portfolioSnapshots)
    .values({
      portfolioId,
      date: today,
      totalValue,
      costBasis,
      baseCurrency,
      recordedAt: Math.floor(Date.now() / 1000),
    })
    .onConflictDoUpdate({
      target: [portfolioSnapshots.portfolioId, portfolioSnapshots.date],
      set: { totalValue, costBasis, baseCurrency, recordedAt: Math.floor(Date.now() / 1000) },
    })
    .run();
}
