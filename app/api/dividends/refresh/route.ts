import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { holdings, dividendMetadata } from "@/lib/db/schema";
import { eq, inArray } from "drizzle-orm";
import { getCurrentPortfolioId } from "@/lib/portfolio-context";
import { default as YahooFinance } from "yahoo-finance2";

const yf = new YahooFinance({ suppressNotices: ["yahooSurvey"] });

function toDateStr(d: unknown): string | null {
  if (!d) return null;
  if (d instanceof Date) return d.toISOString().slice(0, 10);
  if (typeof d === "number") return new Date(d * 1000).toISOString().slice(0, 10);
  return null;
}

function detectFrequency(annual: number, perPayment: number): string | null {
  if (!annual || !perPayment || perPayment <= 0) return null;
  const ratio = annual / perPayment;
  if (ratio < 1.5) return "annual";
  if (ratio < 3) return "semi-annual";
  if (ratio < 6) return "quarterly";
  return "monthly";
}

export async function POST() {
  const portfolioId = await getCurrentPortfolioId();
  const allHoldings = db.select().from(holdings).where(eq(holdings.portfolioId, portfolioId)).all();
  const now = Math.floor(Date.now() / 1000);
  let refreshed = 0;
  const errors: string[] = [];

  for (const h of allHoldings) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const summary = await (yf as any).quoteSummary(h.ticker, {
        modules: ["calendarEvents", "summaryDetail"],
      });

      const cal = summary?.calendarEvents ?? null;
      const detail = summary?.summaryDetail ?? null;

      const exDivDate = toDateStr(cal?.exDividendDate);
      const payDate = toDateStr(cal?.dividendDate);
      const annualDividendRate = (detail?.dividendRate as number | null | undefined) ?? null;
      const amountPerShare = (detail?.lastDividendValue as number | null | undefined) ?? null;
      const frequency = annualDividendRate && amountPerShare
        ? detectFrequency(annualDividendRate, amountPerShare)
        : null;

      db.insert(dividendMetadata)
        .values({
          holdingId: h.id,
          exDivDate,
          payDate,
          amountPerShare,
          annualDividendRate,
          frequency,
          fetchedAt: now,
        })
        .onConflictDoUpdate({
          target: dividendMetadata.holdingId,
          set: { exDivDate, payDate, amountPerShare, annualDividendRate, frequency, fetchedAt: now },
        })
        .run();

      refreshed++;
    } catch (err) {
      errors.push(`${h.ticker}: ${err instanceof Error ? err.message : "unknown"}`);
    }
  }

  return NextResponse.json({ refreshed, errors, refreshedAt: now });
}

async function currentHoldingIds(): Promise<number[]> {
  const portfolioId = await getCurrentPortfolioId();
  return db
    .select({ id: holdings.id })
    .from(holdings)
    .where(eq(holdings.portfolioId, portfolioId))
    .all()
    .map((h) => h.id);
}

export async function DELETE() {
  const ids = await currentHoldingIds();
  if (ids.length > 0) {
    db.delete(dividendMetadata).where(inArray(dividendMetadata.holdingId, ids)).run();
  }
  return NextResponse.json({ ok: true });
}

// Allow reading last-refresh timestamp
export async function GET() {
  const ids = await currentHoldingIds();
  const rows =
    ids.length > 0
      ? db.select().from(dividendMetadata).where(inArray(dividendMetadata.holdingId, ids)).all()
      : [];
  const lastRefreshed = rows.length > 0
    ? Math.max(...rows.map((r) => r.fetchedAt))
    : null;
  return NextResponse.json({ count: rows.length, lastRefreshed });
}

