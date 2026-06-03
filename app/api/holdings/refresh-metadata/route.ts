import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { holdings } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { getCurrentPortfolioId } from "@/lib/portfolio-context";
import { fetchQuoteDetails } from "@/lib/yahoo";

// Re-fetches name/sector/asset class/currency for every holding in the active
// portfolio. Fixes rows that predate asset-class detection (stored as "stock"
// with the wrong currency).
export async function POST() {
  const portfolioId = await getCurrentPortfolioId();
  const rows = db.select().from(holdings).where(eq(holdings.portfolioId, portfolioId)).all();

  let updated = 0;
  const errors: string[] = [];

  for (const h of rows) {
    const quote = await fetchQuoteDetails(h.ticker);
    // price === null means the lookup failed — don't clobber good data with defaults.
    if (quote.price === null) {
      errors.push(h.ticker);
      continue;
    }
    db.update(holdings)
      .set({
        name: quote.name ?? h.name,
        sector: quote.sector,
        assetClass: quote.assetClass,
        currency: quote.currency ?? h.currency,
      })
      .where(eq(holdings.id, h.id))
      .run();
    updated++;
  }

  return NextResponse.json({ updated, errors });
}
