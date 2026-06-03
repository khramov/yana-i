import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { goals } from "@/lib/db/schema";
import { and, eq } from "drizzle-orm";
import { getCurrentPortfolioId } from "@/lib/portfolio-context";

type Scope = "holding" | "asset_class";

function groupByScope(rows: { scope: string; targetKey: string; targetPct: number }[]) {
  const out: Record<Scope, { key: string; pct: number }[]> = { holding: [], asset_class: [] };
  for (const r of rows) {
    if (r.scope === "holding" || r.scope === "asset_class") {
      out[r.scope].push({ key: r.targetKey, pct: r.targetPct });
    }
  }
  return out;
}

export async function GET() {
  const portfolioId = await getCurrentPortfolioId();
  const rows = db.select().from(goals).where(eq(goals.portfolioId, portfolioId)).all();
  return NextResponse.json(groupByScope(rows));
}

export async function PUT(req: Request) {
  const portfolioId = await getCurrentPortfolioId();
  const body = await req.json().catch(() => ({}));

  const scope = body.scope;
  if (scope !== "holding" && scope !== "asset_class") {
    return NextResponse.json({ error: "scope must be 'holding' or 'asset_class'" }, { status: 400 });
  }

  const rawTargets = Array.isArray(body.targets) ? body.targets : [];
  const targets: { key: string; pct: number }[] = [];
  for (const t of rawTargets) {
    const key = typeof t?.key === "string" ? t.key.trim() : "";
    const pct = Number(t?.pct);
    if (!key || !Number.isFinite(pct) || pct < 0) {
      return NextResponse.json({ error: "Each target needs a key and a non-negative percent" }, { status: 400 });
    }
    if (pct > 0) targets.push({ key, pct });
  }

  if (targets.length > 0) {
    const sum = targets.reduce((a, b) => a + b.pct, 0);
    if (Math.abs(sum - 100) > 0.5) {
      return NextResponse.json(
        { error: `Targets must add up to 100% (currently ${sum.toFixed(1)}%)` },
        { status: 400 }
      );
    }
  }

  const now = Math.floor(Date.now() / 1000);
  // Replace the whole scope atomically.
  db.transaction((tx) => {
    tx.delete(goals).where(and(eq(goals.portfolioId, portfolioId), eq(goals.scope, scope))).run();
    for (const t of targets) {
      tx.insert(goals)
        .values({ portfolioId, scope, targetKey: t.key, targetPct: t.pct, createdAt: now })
        .run();
    }
  });

  const rows = db.select().from(goals).where(eq(goals.portfolioId, portfolioId)).all();
  return NextResponse.json(groupByScope(rows));
}
