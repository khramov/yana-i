import { db } from "@/lib/db";
import { holdings, transactions } from "@/lib/db/schema";
import { asc } from "drizzle-orm";

export interface PositionData {
  holdingId: number;
  ticker: string;
  name: string | null;
  sharesHeld: number;
  avgCost: number | null;
  totalCostBasis: number;
  currency: string;
}

export function computePositions(): PositionData[] {
  const allHoldings = db.select().from(holdings).all();
  const allTxns = db
    .select()
    .from(transactions)
    .orderBy(asc(transactions.date), asc(transactions.id))
    .all();

  const txnsByHolding = new Map<number, typeof allTxns>();
  for (const t of allTxns) {
    const list = txnsByHolding.get(t.holdingId) ?? [];
    list.push(t);
    txnsByHolding.set(t.holdingId, list);
  }

  return allHoldings.map((h) => {
    const txns = txnsByHolding.get(h.id) ?? [];
    let shares = 0;
    let avgCostPerShare = 0;
    let currency = "USD";

    for (const t of txns) {
      if (t.type === "buy" && t.shares != null && t.price != null) {
        currency = t.currency ?? "USD";
        const newShares = t.shares;
        const lotCost = newShares * t.price + t.fee;
        avgCostPerShare =
          shares + newShares > 0
            ? (shares * avgCostPerShare + lotCost) / (shares + newShares)
            : 0;
        shares += newShares;
      } else if (t.type === "sell" && t.shares != null) {
        shares = Math.max(0, shares - t.shares);
      }
    }

    const sharesHeld = Math.round(shares * 1e8) / 1e8; // float cleanup
    const totalCostBasis = sharesHeld * avgCostPerShare;

    return {
      holdingId: h.id,
      ticker: h.ticker,
      name: h.name,
      sharesHeld,
      avgCost: sharesHeld > 0 ? avgCostPerShare : null,
      totalCostBasis,
      currency,
    };
  });
}
