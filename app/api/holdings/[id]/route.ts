import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { holdings, transactions, dividendMetadata } from "@/lib/db/schema";
import { and, eq } from "drizzle-orm";
import { getCurrentPortfolioId } from "@/lib/portfolio-context";

export async function DELETE(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const portfolioId = await getCurrentPortfolioId();
  const { id } = await params;
  const numId = parseInt(id, 10);
  if (Number.isNaN(numId)) return NextResponse.json({ error: "Invalid id" }, { status: 400 });

  const holding = db
    .select()
    .from(holdings)
    .where(and(eq(holdings.id, numId), eq(holdings.portfolioId, portfolioId)))
    .get();
  if (!holding) return NextResponse.json({ error: "Not found" }, { status: 404 });

  const txnCount = db
    .select({ id: transactions.id })
    .from(transactions)
    .where(eq(transactions.holdingId, numId))
    .all().length;
  if (txnCount > 0) {
    return NextResponse.json(
      {
        error: `${holding.ticker} has ${txnCount} transaction${txnCount === 1 ? "" : "s"}. Delete those first to remove it.`,
      },
      { status: 409 }
    );
  }

  db.delete(dividendMetadata).where(eq(dividendMetadata.holdingId, numId)).run();
  db.delete(holdings).where(eq(holdings.id, numId)).run();
  return NextResponse.json({ ok: true });
}
