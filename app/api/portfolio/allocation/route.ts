import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { holdings, priceCache } from "@/lib/db/schema";
import { computePositions } from "@/lib/portfolio";
import { fetchQuotes } from "@/lib/yahoo";
import { getBaseCurrency, getRate } from "@/lib/fx";
import { inArray } from "drizzle-orm";

const CACHE_TTL_SECONDS = 15 * 60;

export interface AllocationSlice {
  label: string;
  value: number;
  percentage: number;
}

type GroupBy = "holding" | "sector" | "asset_class";

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const rawBy = searchParams.get("by") ?? "holding";
  const by: GroupBy = ["holding", "sector", "asset_class"].includes(rawBy)
    ? (rawBy as GroupBy)
    : "holding";

  const baseCurrency = getBaseCurrency();
  const positions = computePositions().filter((p) => p.sharesHeld > 0);

  if (positions.length === 0) {
    return NextResponse.json({ baseCurrency, slices: [] });
  }

  const tickers = positions.map((p) => p.ticker);

  // Refresh stale prices
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

  // Load holding metadata (sector, asset_class)
  const holdingRows = db.select().from(holdings).where(inArray(holdings.ticker, tickers)).all();
  const holdingMeta = new Map(holdingRows.map((h) => [h.ticker, h]));

  // FX rates for all native currencies
  const nativeCurrencies = new Set(positions.map((p) => priceMap.get(p.ticker)?.currency ?? "USD"));
  const fxRateMap = new Map<string, number>();
  await Promise.all(
    [...nativeCurrencies].map(async (cur) => {
      fxRateMap.set(cur, await getRate(cur, baseCurrency));
    })
  );

  // Compute market value per position in base currency
  const grouped = new Map<string, number>();
  for (const p of positions) {
    const entry = priceMap.get(p.ticker);
    const nativeCurrency = entry?.currency ?? "USD";
    const fxRate = fxRateMap.get(nativeCurrency) ?? 1;
    const currentPrice = entry?.price ?? null;
    if (currentPrice == null) continue;

    const marketValue = p.sharesHeld * currentPrice * fxRate;

    let label: string;
    const meta = holdingMeta.get(p.ticker);
    if (by === "holding") {
      label = p.ticker;
    } else if (by === "sector") {
      label = meta?.sector ?? "Unknown";
    } else {
      label = formatAssetClass(meta?.assetClass ?? "stock");
    }

    grouped.set(label, (grouped.get(label) ?? 0) + marketValue);
  }

  const total = [...grouped.values()].reduce((a, b) => a + b, 0);
  const slices: AllocationSlice[] = [...grouped.entries()]
    .map(([label, value]) => ({
      label,
      value,
      percentage: total > 0 ? (value / total) * 100 : 0,
    }))
    .sort((a, b) => b.value - a.value);

  return NextResponse.json({ baseCurrency, slices });
}

function formatAssetClass(raw: string): string {
  switch (raw) {
    case "etf": return "ETF";
    case "bond": return "Bond";
    case "cash": return "Cash";
    default: return "Stock";
  }
}
