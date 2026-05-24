import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { portfolioSnapshots } from "@/lib/db/schema";
import { writeSnapshotIfNeeded } from "@/lib/portfolio";
import { and, gte, lte, asc } from "drizzle-orm";

export async function GET(req: NextRequest) {
  await writeSnapshotIfNeeded();

  const { searchParams } = req.nextUrl;
  const from = searchParams.get("from");
  const to = searchParams.get("to");

  const conditions = [];
  if (from) conditions.push(gte(portfolioSnapshots.date, from));
  if (to) conditions.push(lte(portfolioSnapshots.date, to));

  const rows =
    conditions.length > 0
      ? db
          .select()
          .from(portfolioSnapshots)
          .where(and(...conditions))
          .orderBy(asc(portfolioSnapshots.date))
          .all()
      : db.select().from(portfolioSnapshots).orderBy(asc(portfolioSnapshots.date)).all();

  return NextResponse.json(rows);
}
