import { cookies } from "next/headers";
import { db } from "@/lib/db";
import { portfolios } from "@/lib/db/schema";
import { asc, eq } from "drizzle-orm";

import { DEFAULT_CURRENCY } from "@/lib/currencies";
export { SUPPORTED_CURRENCIES, DEFAULT_CURRENCY } from "@/lib/currencies";

export const PORTFOLIO_COOKIE = "portfolioId";

export interface Portfolio {
  id: number;
  name: string;
  baseCurrency: string;
}

export function getDefaultPortfolio(): Portfolio {
  const first = db.select().from(portfolios).orderBy(asc(portfolios.id)).get();
  if (first) return first;
  // Should never happen (migration seeds one), but stay safe.
  const now = Math.floor(Date.now() / 1000);
  return db
    .insert(portfolios)
    .values({ name: "Main Portfolio", baseCurrency: DEFAULT_CURRENCY, createdAt: now })
    .returning()
    .get();
}

export function getPortfolioById(id: number): Portfolio | null {
  return db.select().from(portfolios).where(eq(portfolios.id, id)).get() ?? null;
}

/** Resolve the active portfolio from the request cookie, falling back to the first. */
export async function getCurrentPortfolio(): Promise<Portfolio> {
  const store = await cookies();
  const raw = store.get(PORTFOLIO_COOKIE)?.value;
  const id = raw ? parseInt(raw, 10) : NaN;
  if (!Number.isNaN(id)) {
    const found = getPortfolioById(id);
    if (found) return found;
  }
  return getDefaultPortfolio();
}

export async function getCurrentPortfolioId(): Promise<number> {
  return (await getCurrentPortfolio()).id;
}
