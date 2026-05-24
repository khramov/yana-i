import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { holdings } from "@/lib/db/schema";
import { fetchQuoteDetails } from "@/lib/yahoo";
import { eq } from "drizzle-orm";

export async function GET() {
  const rows = db.select().from(holdings).all();
  return NextResponse.json(rows);
}

export async function POST(req: Request) {
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
      ticker: symbol,
      name: quote.name,
      sector: quote.sector,
      assetClass: quote.assetClass,
      currency: quote.currency ?? "USD",
      createdAt: now,
    })
    .onConflictDoUpdate({
      target: holdings.ticker,
      set: { name: quote.name, sector: quote.sector, assetClass: quote.assetClass, currency: quote.currency ?? "USD" },
    })
    .run();

  const row = db.select().from(holdings).where(eq(holdings.ticker, symbol)).get();
  return NextResponse.json(row, { status: 201 });
}
