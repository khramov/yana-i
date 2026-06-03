import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { holdings, transactions, dividendMetadata } from "@/lib/db/schema";
import { and, eq, inArray } from "drizzle-orm";
import { computePositions } from "@/lib/portfolio";
import { toBase } from "@/lib/fx";
import { getCurrentPortfolio } from "@/lib/portfolio-context";

export async function GET() {
  const { id: portfolioId, baseCurrency } = await getCurrentPortfolio();

  const divTxns = db
    .select({
      id: transactions.id,
      holdingId: transactions.holdingId,
      date: transactions.date,
      price: transactions.price,
      currency: transactions.currency,
      ticker: holdings.ticker,
      name: holdings.name,
    })
    .from(transactions)
    .innerJoin(holdings, eq(transactions.holdingId, holdings.id))
    .where(and(eq(transactions.portfolioId, portfolioId), eq(transactions.type, "dividend")))
    .all();

  // Monthly breakdown
  const monthlyMap = new Map<string, number>();
  // By holding: trailing 12m
  const byHoldingTrailing = new Map<string, { ticker: string; name: string | null; trailing12m: number }>();

  const trailing12mCutoff = new Date();
  trailing12mCutoff.setFullYear(trailing12mCutoff.getFullYear() - 1);
  const cutoffDate = trailing12mCutoff.toISOString().slice(0, 10);

  for (const t of divTxns) {
    const amount = await toBase(t.price ?? 0, t.currency ?? "USD", baseCurrency);
    const month = t.date.slice(0, 7); // YYYY-MM
    monthlyMap.set(month, (monthlyMap.get(month) ?? 0) + amount);

    if (t.date >= cutoffDate) {
      if (!byHoldingTrailing.has(t.ticker)) {
        byHoldingTrailing.set(t.ticker, { ticker: t.ticker, name: t.name, trailing12m: 0 });
      }
      byHoldingTrailing.get(t.ticker)!.trailing12m += amount;
    }
  }

  const monthly = Array.from(monthlyMap.entries())
    .map(([month, amount]) => ({ month, amount }))
    .sort((a, b) => a.month.localeCompare(b.month));

  // Forward annual income from dividend_metadata
  const positions = computePositions(portfolioId).filter((p) => p.sharesHeld > 0);
  const holdingIds = positions.map((p) => p.holdingId);
  const metadata =
    holdingIds.length > 0
      ? db.select().from(dividendMetadata).where(inArray(dividendMetadata.holdingId, holdingIds)).all()
      : [];

  const metadataMap = new Map(metadata.map((m) => [m.holdingId, m]));

  let forwardAnnual = 0;
  const byHoldingForward = new Map<string, number>();

  for (const pos of positions) {
    const meta = metadataMap.get(pos.holdingId);
    if (!meta?.annualDividendRate) continue;

    const holding = db.select().from(holdings).where(eq(holdings.id, pos.holdingId)).get();
    if (!holding) continue;

    const annualNative = pos.sharesHeld * meta.annualDividendRate;
    const annualBase = await toBase(annualNative, holding.currency ?? "USD", baseCurrency);
    forwardAnnual += annualBase;
    byHoldingForward.set(pos.ticker, annualBase);
  }

  const allTickers = new Set([
    ...byHoldingTrailing.keys(),
    ...byHoldingForward.keys(),
  ]);

  const byHolding = Array.from(allTickers)
    .map((ticker) => {
      const trailing = byHoldingTrailing.get(ticker);
      const forward = byHoldingForward.get(ticker) ?? 0;
      return {
        ticker,
        name: trailing?.name ?? null,
        trailing12m: trailing?.trailing12m ?? 0,
        forward,
      };
    })
    .filter((h) => h.trailing12m > 0 || h.forward > 0)
    .sort((a, b) => b.trailing12m - a.trailing12m);

  const lastRefreshed =
    metadata.length > 0 ? Math.max(...metadata.map((m) => m.fetchedAt)) : null;

  return NextResponse.json({
    baseCurrency,
    monthly,
    forwardAnnual,
    byHolding,
    lastRefreshed,
  });
}
