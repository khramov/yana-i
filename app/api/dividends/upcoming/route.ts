import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { holdings, dividendMetadata } from "@/lib/db/schema";
import { eq, inArray } from "drizzle-orm";
import { computePositions } from "@/lib/portfolio";
import { toBase } from "@/lib/fx";
import { getCurrentPortfolio } from "@/lib/portfolio-context";

export async function GET() {
  const { id: portfolioId, baseCurrency } = await getCurrentPortfolio();
  const positions = computePositions(portfolioId).filter((p) => p.sharesHeld > 0);
  const holdingIds = positions.map((p) => p.holdingId);

  if (holdingIds.length === 0) {
    return NextResponse.json({ baseCurrency, events: [] });
  }

  const metadata = db
    .select()
    .from(dividendMetadata)
    .where(inArray(dividendMetadata.holdingId, holdingIds))
    .all();

  const allHoldings = db.select().from(holdings).where(eq(holdings.portfolioId, portfolioId)).all();
  const holdingMap = new Map(allHoldings.map((h) => [h.id, h]));
  const positionMap = new Map(positions.map((p) => [p.holdingId, p]));

  const today = new Date().toISOString().slice(0, 10);

  const events = await Promise.all(
    metadata
      .filter((m) => m.exDivDate || m.payDate)
      .map(async (m) => {
        const holding = holdingMap.get(m.holdingId);
        const position = positionMap.get(m.holdingId);
        if (!holding || !position) return null;

        const nativeCurrency = holding.currency ?? "USD";
        const amountPerShare = m.amountPerShare ?? 0;
        const estimatedIncomeNative = position.sharesHeld * amountPerShare;
        const estimatedIncomeBase = await toBase(estimatedIncomeNative, nativeCurrency, baseCurrency);

        return {
          ticker: holding.ticker,
          name: holding.name,
          exDivDate: m.exDivDate,
          payDate: m.payDate,
          amountPerShare,
          frequency: m.frequency,
          sharesHeld: position.sharesHeld,
          estimatedIncomeNative,
          estimatedIncomeBase,
          currency: nativeCurrency,
          fetchedAt: m.fetchedAt,
          isUpcoming: m.exDivDate ? m.exDivDate >= today : false,
        };
      })
  );

  const filtered = events
    .filter(Boolean)
    .sort((a, b) => {
      const da = a!.exDivDate ?? a!.payDate ?? "";
      const db2 = b!.exDivDate ?? b!.payDate ?? "";
      return da.localeCompare(db2);
    });

  return NextResponse.json({ baseCurrency, events: filtered });
}
