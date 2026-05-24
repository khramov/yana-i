import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { holdings, transactions } from "@/lib/db/schema";
import { eq, asc } from "drizzle-orm";
import { computePositions } from "@/lib/portfolio";

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const yearParam = searchParams.get("year");
  const filterYear = yearParam ? parseInt(yearParam, 10) : null;

  const divTxns = db
    .select({
      id: transactions.id,
      holdingId: transactions.holdingId,
      date: transactions.date,
      shares: transactions.shares,
      price: transactions.price,
      tax: transactions.tax,
      currency: transactions.currency,
      notes: transactions.notes,
      ticker: holdings.ticker,
      name: holdings.name,
    })
    .from(transactions)
    .innerJoin(holdings, eq(transactions.holdingId, holdings.id))
    .where(eq(transactions.type, "dividend"))
    .orderBy(asc(transactions.date), asc(transactions.id))
    .all();

  const positions = computePositions();
  const avgCostMap = new Map(positions.map((p) => [p.holdingId, p.avgCost]));

  const now = new Date();
  const trailing12mCutoff = new Date(now);
  trailing12mCutoff.setFullYear(trailing12mCutoff.getFullYear() - 1);
  const trailing12mDate = trailing12mCutoff.toISOString().slice(0, 10);

  let totalAllTime = 0;
  let trailing12m = 0;

  const yearsSet = new Set<number>();
  const allRows = divTxns.map((t) => {
    const amount = t.price ?? 0;
    const perShare = t.shares && t.shares > 0 ? amount / t.shares : null;
    const avgCost = avgCostMap.get(t.holdingId) ?? null;
    const yieldOnCost =
      perShare != null && avgCost != null && avgCost > 0
        ? (perShare / avgCost) * 100
        : null;

    totalAllTime += amount;
    if (t.date >= trailing12mDate) trailing12m += amount;
    yearsSet.add(parseInt(t.date.slice(0, 4), 10));

    return {
      id: t.id,
      ticker: t.ticker,
      name: t.name,
      date: t.date,
      amount,
      shares: t.shares,
      perShare,
      tax: t.tax,
      currency: t.currency,
      yieldOnCost,
    };
  });

  const totalCostBasis = positions.reduce((s, p) => s + p.totalCostBasis, 0);
  const portfolioYieldOnCost =
    totalCostBasis > 0 ? (totalAllTime / totalCostBasis) * 100 : null;

  const years = Array.from(yearsSet).sort((a, b) => b - a);

  const rows = filterYear
    ? allRows.filter((r) => r.date.startsWith(filterYear.toString()))
    : allRows;

  return NextResponse.json({
    totalAllTime,
    trailing12m,
    yieldOnCost: portfolioYieldOnCost,
    years,
    rows: rows.reverse(), // most recent first
  });
}
