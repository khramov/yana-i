import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { transactions } from "@/lib/db/schema";
import { transactionSchema } from "@/lib/validations";
import { eq } from "drizzle-orm";

function computeTotal(
  shares: number | null | undefined,
  price: number | null | undefined,
  fee: number
): number {
  if (shares != null && price != null) return shares * price + fee;
  return fee;
}

export async function PUT(
  req: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const numId = parseInt(id, 10);
  if (isNaN(numId)) return NextResponse.json({ error: "Invalid id" }, { status: 400 });

  const existing = db.select().from(transactions).where(eq(transactions.id, numId)).get();
  if (!existing) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const body = await req.json();
  const parsed = transactionSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  }

  const data = parsed.data;
  const row = db
    .update(transactions)
    .set({
      holdingId: data.holdingId,
      type: data.type,
      date: data.date,
      shares: data.shares ?? null,
      price: data.price ?? null,
      fee: data.fee ?? 0,
      tax: data.tax ?? 0,
      currency: data.currency ?? "USD",
      notes: data.notes ?? null,
    })
    .where(eq(transactions.id, numId))
    .returning()
    .get();

  return NextResponse.json({ ...row, total: computeTotal(row.shares, row.price, row.fee) });
}

export async function DELETE(
  _req: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const numId = parseInt(id, 10);
  if (isNaN(numId)) return NextResponse.json({ error: "Invalid id" }, { status: 400 });

  const existing = db.select().from(transactions).where(eq(transactions.id, numId)).get();
  if (!existing) return NextResponse.json({ error: "Not found" }, { status: 404 });

  db.delete(transactions).where(eq(transactions.id, numId)).run();
  return NextResponse.json({ ok: true });
}
