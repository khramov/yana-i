import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { transactions, holdings } from "@/lib/db/schema";
import { transactionSchema } from "@/lib/validations";
import { eq, and, gte, lte, inArray } from "drizzle-orm";
import { getCurrentPortfolioId } from "@/lib/portfolio-context";

function computeTotal(
  shares: number | null | undefined,
  price: number | null | undefined,
  fee: number
): number {
  if (shares != null && price != null) return shares * price + fee;
  return fee;
}

export async function GET(req: Request) {
  const portfolioId = await getCurrentPortfolioId();
  const { searchParams } = new URL(req.url);
  const type = searchParams.get("type");
  const from = searchParams.get("from");
  const to = searchParams.get("to");

  const conditions = [eq(transactions.portfolioId, portfolioId)];
  if (type && ["buy", "sell", "dividend", "fee"].includes(type)) {
    conditions.push(eq(transactions.type, type));
  }
  if (from) conditions.push(gte(transactions.date, from));
  if (to) conditions.push(lte(transactions.date, to));

  const rows = db
    .select()
    .from(transactions)
    .where(and(...conditions))
    .orderBy(transactions.date)
    .all();

  const holdingIds = [...new Set(rows.map((r) => r.holdingId))];
  const holdingRows =
    holdingIds.length > 0
      ? db.select().from(holdings).where(inArray(holdings.id, holdingIds)).all()
      : [];
  const holdingMap = new Map(holdingRows.map((h) => [h.id, h]));

  const result = rows.map((r) => ({
    ...r,
    total: computeTotal(r.shares, r.price, r.fee),
    holding: holdingMap.get(r.holdingId) ?? null,
  }));

  return NextResponse.json(result);
}

export async function POST(req: Request) {
  const portfolioId = await getCurrentPortfolioId();
  const body = await req.json();
  const parsed = transactionSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const data = parsed.data;

  // Guard against attaching a transaction to a holding in another portfolio.
  const holding = db.select().from(holdings).where(eq(holdings.id, data.holdingId)).get();
  if (!holding || holding.portfolioId !== portfolioId) {
    return NextResponse.json({ error: "Holding not found in this portfolio" }, { status: 400 });
  }

  const now = Math.floor(Date.now() / 1000);

  const row = db
    .insert(transactions)
    .values({
      portfolioId,
      holdingId: data.holdingId,
      type: data.type,
      date: data.date,
      shares: data.shares ?? null,
      price: data.price ?? null,
      fee: data.fee ?? 0,
      tax: data.tax ?? 0,
      currency: data.currency ?? "USD",
      notes: data.notes ?? null,
      createdAt: now,
    })
    .returning()
    .get();

  return NextResponse.json(
    { ...row, total: computeTotal(row.shares, row.price, row.fee) },
    { status: 201 }
  );
}
