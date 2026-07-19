import { cookies } from "next/headers";
import { db } from "@/lib/db";
import { portfolios } from "@/lib/db/schema";
import { and, asc, eq } from "drizzle-orm";
import { requireUser } from "@/lib/auth";

import { DEFAULT_CURRENCY } from "@/lib/currencies";
export { SUPPORTED_CURRENCIES, DEFAULT_CURRENCY } from "@/lib/currencies";

export const PORTFOLIO_COOKIE = "portfolioId";

export interface Portfolio {
  id: number;
  name: string;
  baseCurrency: string;
}

/** The signed-in user's first portfolio, creating one if they have none. */
export function getDefaultPortfolioForUser(userId: number): Portfolio {
  const first = db
    .select()
    .from(portfolios)
    .where(eq(portfolios.userId, userId))
    .orderBy(asc(portfolios.id))
    .get();
  if (first) return first;

  const now = Math.floor(Date.now() / 1000);
  return db
    .insert(portfolios)
    .values({ userId, name: "Main Portfolio", baseCurrency: DEFAULT_CURRENCY, createdAt: now })
    .returning()
    .get();
}

/** Look up a portfolio by id, scoped to the given owner. Returns null if not owned. */
export function getOwnedPortfolioById(id: number, userId: number): Portfolio | null {
  return (
    db
      .select()
      .from(portfolios)
      .where(and(eq(portfolios.id, id), eq(portfolios.userId, userId)))
      .get() ?? null
  );
}

/**
 * Resolve the active portfolio for the signed-in user from the request cookie,
 * falling back to their first portfolio. Only ever returns a portfolio the user owns.
 * Throws UnauthorizedError when there is no valid session.
 */
export async function getCurrentPortfolio(): Promise<Portfolio> {
  const user = await requireUser();
  const store = await cookies();
  const raw = store.get(PORTFOLIO_COOKIE)?.value;
  const id = raw ? parseInt(raw, 10) : NaN;
  if (!Number.isNaN(id)) {
    const found = getOwnedPortfolioById(id, user.id);
    if (found) return found;
  }
  return getDefaultPortfolioForUser(user.id);
}

export async function getCurrentPortfolioId(): Promise<number> {
  return (await getCurrentPortfolio()).id;
}
