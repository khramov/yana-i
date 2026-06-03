import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { portfolioSnapshots } from "@/lib/db/schema";
import { writeSnapshotIfNeeded } from "@/lib/portfolio";
import { getCurrentPortfolio } from "@/lib/portfolio-context";
import { and, eq, gte, lte, asc } from "drizzle-orm";

export async function GET(req: NextRequest) {
  const { id: portfolioId, baseCurrency } = await getCurrentPortfolio();
  await writeSnapshotIfNeeded(portfolioId, baseCurrency);

  const { searchParams } = req.nextUrl;
  const from = searchParams.get("from");
  const to = searchParams.get("to");

  const conditions = [eq(portfolioSnapshots.portfolioId, portfolioId)];
  if (from) conditions.push(gte(portfolioSnapshots.date, from));
  if (to) conditions.push(lte(portfolioSnapshots.date, to));

  const rows = db
    .select()
    .from(portfolioSnapshots)
    .where(and(...conditions))
    .orderBy(asc(portfolioSnapshots.date))
    .all();

  return NextResponse.json(rows);
}
