import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { transactions, holdings } from "@/lib/db/schema";
import { transactionSchema } from "@/lib/validations";
import { eq, and, gte, lte, inArray } from "drizzle-orm";

function computeTotal(
  shares: number | null | undefined,
  price: number | null | undefined,
  fee: number
): number {
  if (shares != null && price != null) return shares * price + fee;
  return fee;
}

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const type = searchParams.get("type");
  const from = searchParams.get("from");
  const to = searchParams.get("to");

  const conditions = [];
  if (type && ["buy", "sell", "dividend", "fee"].includes(type)) {
    conditions.push(eq(transactions.type, type));
  }
  if (from) conditions.push(gte(transactions.date, from));
  if (to) conditions.push(lte(transactions.date, to));

  const rows =
    conditions.length > 0
      ? db.select().from(transactions).where(and(...conditions)).orderBy(transactions.date).all()
      : db.select().from(transactions).orderBy(transactions.date).all();

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
  const body = await req.json();
  const parsed = transactionSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const data = parsed.data;
  const now = Math.floor(Date.now() / 1000);

  const row = db
    .insert(transactions)
    .values({
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
