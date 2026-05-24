import { db } from "@/lib/db";
import { fxRates } from "@/lib/db/schema";
import { and, eq } from "drizzle-orm";
import { default as YahooFinance } from "yahoo-finance2";

const yf = new YahooFinance({ suppressNotices: ["yahooSurvey"] });
const FX_CACHE_TTL = 3600; // 1 hour

export function getBaseCurrency(): string {
  return process.env.BASE_CURRENCY ?? "USD";
}

export async function getRate(from: string, to: string): Promise<number> {
  if (from === to) return 1;

  const now = Math.floor(Date.now() / 1000);

  const cached = db
    .select()
    .from(fxRates)
    .where(and(eq(fxRates.fromCurrency, from), eq(fxRates.toCurrency, to)))
    .get();

  if (cached && now - cached.fetchedAt < FX_CACHE_TTL) {
    return cached.rate;
  }

  try {
    const ticker = `${from}${to}=X`;
    const quote = await yf.quote(ticker);
    const rate = quote.regularMarketPrice ?? null;
    if (rate != null) {
      db.insert(fxRates)
        .values({ fromCurrency: from, toCurrency: to, rate, fetchedAt: now })
        .onConflictDoUpdate({
          target: [fxRates.fromCurrency, fxRates.toCurrency],
          set: { rate, fetchedAt: now },
        })
        .run();
      return rate;
    }
  } catch {
    // fall through to stale cache or default
  }

  return cached?.rate ?? 1;
}

export async function toBase(amount: number, fromCurrency: string): Promise<number> {
  const rate = await getRate(fromCurrency, getBaseCurrency());
  return amount * rate;
}
