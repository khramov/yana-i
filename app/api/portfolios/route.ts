import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { portfolios } from "@/lib/db/schema";
import { asc } from "drizzle-orm";
import { getCurrentPortfolioId } from "@/lib/portfolio-context";
import { DEFAULT_CURRENCY, isSupportedCurrency } from "@/lib/currencies";

export async function GET() {
  const rows = db.select().from(portfolios).orderBy(asc(portfolios.id)).all();
  const currentId = await getCurrentPortfolioId();
  return NextResponse.json({ portfolios: rows, currentId });
}

export async function POST(req: Request) {
  const body = await req.json().catch(() => ({}));
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const baseCurrency = isSupportedCurrency(body.baseCurrency) ? body.baseCurrency : DEFAULT_CURRENCY;

  if (!name) {
    return NextResponse.json({ error: "Name is required" }, { status: 400 });
  }

  const now = Math.floor(Date.now() / 1000);
  const row = db
    .insert(portfolios)
    .values({ name, baseCurrency, createdAt: now })
    .returning()
    .get();

  return NextResponse.json(row, { status: 201 });
}
