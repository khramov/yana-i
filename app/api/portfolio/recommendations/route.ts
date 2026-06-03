import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { goals } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { computeEnrichedPositions } from "@/lib/portfolio";
import { getCurrentPortfolio } from "@/lib/portfolio-context";

interface RecRow {
  key: string;
  name: string | null;
  currentValue: number;
  currentPct: number;
  targetPct: number | null;
  driftPct: number | null;
  buyAmount: number;
  buyShares: number | null;
}

export async function GET() {
  const { id: portfolioId, baseCurrency } = await getCurrentPortfolio();
  const enriched = await computeEnrichedPositions(portfolioId, baseCurrency);
  const totalValue = enriched.reduce((sum, p) => sum + (p.marketValueBase ?? 0), 0);

  const goalRows = db.select().from(goals).where(eq(goals.portfolioId, portfolioId)).all();
  const holdingGoals = new Map<string, number>();
  const classGoals = new Map<string, number>();
  for (const g of goalRows) {
    if (g.scope === "holding") holdingGoals.set(g.targetKey, g.targetPct);
    else if (g.scope === "asset_class") classGoals.set(g.targetKey, g.targetPct);
  }

  // Current value per holding (ticker) and per asset class.
  const byTicker = new Map<string, { value: number; priceBase: number | null; name: string | null }>();
  const byClass = new Map<string, { value: number }>();
  for (const p of enriched) {
    const value = p.marketValueBase ?? 0;
    byTicker.set(p.ticker, { value, priceBase: p.currentPriceBase, name: p.name });
    const c = byClass.get(p.assetClass) ?? { value: 0 };
    c.value += value;
    byClass.set(p.assetClass, c);
  }

  function buildHolding(): { hasGoals: boolean; rows: RecRow[] } {
    const keys = new Set<string>([...holdingGoals.keys(), ...byTicker.keys()]);
    const rows: RecRow[] = [...keys].map((key) => {
      const cur = byTicker.get(key);
      const currentValue = cur?.value ?? 0;
      const currentPct = totalValue > 0 ? (currentValue / totalValue) * 100 : 0;
      const targetPct = holdingGoals.has(key) ? holdingGoals.get(key)! : null;
      const targetValue = targetPct != null ? (targetPct / 100) * totalValue : null;
      const buyAmount = targetValue != null ? Math.max(0, targetValue - currentValue) : 0;
      const priceBase = cur?.priceBase ?? null;
      return {
        key,
        name: cur?.name ?? null,
        currentValue,
        currentPct,
        targetPct,
        driftPct: targetPct != null ? currentPct - targetPct : null,
        buyAmount,
        buyShares: priceBase && priceBase > 0 ? buyAmount / priceBase : null,
      };
    });
    rows.sort((a, b) => b.buyAmount - a.buyAmount || b.currentValue - a.currentValue);
    return { hasGoals: holdingGoals.size > 0, rows };
  }

  function buildClass(): { hasGoals: boolean; rows: RecRow[] } {
    const keys = new Set<string>([...classGoals.keys(), ...byClass.keys()]);
    const rows: RecRow[] = [...keys].map((key) => {
      const currentValue = byClass.get(key)?.value ?? 0;
      const currentPct = totalValue > 0 ? (currentValue / totalValue) * 100 : 0;
      const targetPct = classGoals.has(key) ? classGoals.get(key)! : null;
      const targetValue = targetPct != null ? (targetPct / 100) * totalValue : null;
      const buyAmount = targetValue != null ? Math.max(0, targetValue - currentValue) : 0;
      return {
        key,
        name: null,
        currentValue,
        currentPct,
        targetPct,
        driftPct: targetPct != null ? currentPct - targetPct : null,
        buyAmount,
        buyShares: null,
      };
    });
    rows.sort((a, b) => b.buyAmount - a.buyAmount || b.currentValue - a.currentValue);
    return { hasGoals: classGoals.size > 0, rows };
  }

  return NextResponse.json({
    baseCurrency,
    totalValue,
    holding: buildHolding(),
    assetClass: buildClass(),
  });
}
