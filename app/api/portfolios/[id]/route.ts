import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import {
  portfolios,
  holdings,
  transactions,
  portfolioSnapshots,
  goals,
  dividendMetadata,
} from "@/lib/db/schema";
import { eq, inArray } from "drizzle-orm";
import { isSupportedCurrency } from "@/lib/currencies";

export async function PATCH(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const numId = parseInt(id, 10);
  if (Number.isNaN(numId)) return NextResponse.json({ error: "Invalid id" }, { status: 400 });

  const existing = db.select().from(portfolios).where(eq(portfolios.id, numId)).get();
  if (!existing) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const body = await req.json().catch(() => ({}));
  const update: Partial<{ name: string; baseCurrency: string }> = {};

  if (typeof body.name === "string" && body.name.trim()) update.name = body.name.trim();
  if (body.baseCurrency !== undefined) {
    if (!isSupportedCurrency(body.baseCurrency)) {
      return NextResponse.json({ error: "Unsupported currency" }, { status: 400 });
    }
    update.baseCurrency = body.baseCurrency;
  }

  if (Object.keys(update).length === 0) {
    return NextResponse.json({ error: "Nothing to update" }, { status: 400 });
  }

  const row = db.update(portfolios).set(update).where(eq(portfolios.id, numId)).returning().get();
  return NextResponse.json(row);
}

export async function DELETE(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const numId = parseInt(id, 10);
  if (Number.isNaN(numId)) return NextResponse.json({ error: "Invalid id" }, { status: 400 });

  const all = db.select().from(portfolios).all();
  if (!all.some((p) => p.id === numId)) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  if (all.length <= 1) {
    return NextResponse.json({ error: "Cannot delete the last portfolio" }, { status: 400 });
  }

  const holdingIds = db
    .select({ id: holdings.id })
    .from(holdings)
    .where(eq(holdings.portfolioId, numId))
    .all()
    .map((h) => h.id);

  // Delete children before parents (foreign keys are enforced).
  db.delete(transactions).where(eq(transactions.portfolioId, numId)).run();
  if (holdingIds.length > 0) {
    db.delete(dividendMetadata).where(inArray(dividendMetadata.holdingId, holdingIds)).run();
  }
  db.delete(holdings).where(eq(holdings.portfolioId, numId)).run();
  db.delete(portfolioSnapshots).where(eq(portfolioSnapshots.portfolioId, numId)).run();
  db.delete(goals).where(eq(goals.portfolioId, numId)).run();
  db.delete(portfolios).where(eq(portfolios.id, numId)).run();

  const fallback = db.select().from(portfolios).get();
  return NextResponse.json({ ok: true, fallbackId: fallback?.id ?? null });
}
