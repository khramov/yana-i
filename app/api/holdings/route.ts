import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { holdings } from "@/lib/db/schema";
import { fetchQuoteDetails } from "@/lib/yahoo";
import { and, eq } from "drizzle-orm";
import { getCurrentPortfolioId } from "@/lib/portfolio-context";

export async function GET() {
  const portfolioId = await getCurrentPortfolioId();
  const rows = db.select().from(holdings).where(eq(holdings.portfolioId, portfolioId)).all();
  return NextResponse.json(rows);
}

export async function POST(req: Request) {
  const portfolioId = await getCurrentPortfolioId();
  const { ticker } = await req.json();
  if (!ticker || typeof ticker !== "string") {
    return NextResponse.json({ error: "ticker required" }, { status: 400 });
  }
  const symbol = ticker.trim().toUpperCase();

  const quote = await fetchQuoteDetails(symbol);
  if (quote.price === null) {
    return NextResponse.json(
      { error: `Ticker "${symbol}" not found` },
      { status: 404 }
    );
  }

  const now = Math.floor(Date.now() / 1000);
  db.insert(holdings)
    .values({
      portfolioId,
      ticker: symbol,
      name: quote.name,
      sector: quote.sector,
      assetClass: quote.assetClass,
      currency: quote.currency ?? "USD",
      createdAt: now,
    })
    .onConflictDoUpdate({
      target: [holdings.portfolioId, holdings.ticker],
      set: { name: quote.name, sector: quote.sector, assetClass: quote.assetClass, currency: quote.currency ?? "USD" },
    })
    .run();

  const row = db
    .select()
    .from(holdings)
    .where(and(eq(holdings.portfolioId, portfolioId), eq(holdings.ticker, symbol)))
    .get();
  return NextResponse.json(row, { status: 201 });
}
