import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { holdings, transactions } from "@/lib/db/schema";
import { transactionSchema } from "@/lib/validations";
import { and, eq } from "drizzle-orm";
import { getCurrentPortfolioId } from "@/lib/portfolio-context";
import { fetchQuoteDetails } from "@/lib/yahoo";
import { isSupportedCurrency, DEFAULT_CURRENCY } from "@/lib/currencies";

// Minimal RFC4180-style CSV parser: handles quoted fields, escaped quotes ("")
// and both \n and \r\n line endings.
function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let field = "";
  let row: string[] = [];
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ",") {
      row.push(field);
      field = "";
    } else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      rows.push(row);
      field = "";
      row = [];
    } else {
      field += ch;
    }
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter((r) => r.some((c) => c.trim() !== ""));
}

function parseNum(raw: string | undefined): number | undefined {
  if (raw == null) return undefined;
  const trimmed = raw.trim();
  if (trimmed === "") return undefined;
  const n = Number(trimmed.replace(",", "."));
  return Number.isFinite(n) ? n : NaN;
}

export async function POST(req: Request) {
  const portfolioId = await getCurrentPortfolioId();

  let csv = "";
  const contentType = req.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    const body = await req.json().catch(() => ({}));
    csv = typeof body.csv === "string" ? body.csv : "";
  } else {
    csv = await req.text();
  }

  const rows = parseCsv(csv);
  if (rows.length < 2) {
    return NextResponse.json(
      { error: "CSV must have a header row and at least one data row" },
      { status: 400 }
    );
  }

  const header = rows[0].map((h) => h.trim().toLowerCase());
  const col = (name: string) => header.indexOf(name);
  const idx = {
    ticker: col("ticker"),
    type: col("type"),
    date: col("date"),
    shares: col("shares"),
    price: col("price"),
    fee: col("fee"),
    tax: col("tax"),
    currency: col("currency"),
    notes: col("notes"),
  };

  if (idx.ticker < 0 || idx.type < 0 || idx.date < 0) {
    return NextResponse.json(
      { error: "CSV must include at least 'ticker', 'type' and 'date' columns" },
      { status: 400 }
    );
  }

  const now = Math.floor(Date.now() / 1000);
  const holdingCache = new Map<string, number>();
  const errors: { row: number; message: string }[] = [];
  let imported = 0;

  async function resolveHolding(ticker: string): Promise<number> {
    const symbol = ticker.trim().toUpperCase();
    const cached = holdingCache.get(symbol);
    if (cached) return cached;

    const existing = db
      .select()
      .from(holdings)
      .where(and(eq(holdings.portfolioId, portfolioId), eq(holdings.ticker, symbol)))
      .get();
    if (existing) {
      holdingCache.set(symbol, existing.id);
      return existing.id;
    }

    const quote = await fetchQuoteDetails(symbol);
    const created = db
      .insert(holdings)
      .values({
        portfolioId,
        ticker: symbol,
        name: quote.name,
        sector: quote.sector,
        assetClass: quote.assetClass,
        currency: quote.currency ?? DEFAULT_CURRENCY,
        createdAt: now,
      })
      .returning()
      .get();
    holdingCache.set(symbol, created.id);
    return created.id;
  }

  for (let r = 1; r < rows.length; r++) {
    const cells = rows[r];
    const lineNo = r + 1; // 1-based, accounting for header
    try {
      const ticker = (cells[idx.ticker] ?? "").trim();
      if (!ticker) {
        errors.push({ row: lineNo, message: "Missing ticker" });
        continue;
      }
      const type = (cells[idx.type] ?? "").trim().toLowerCase();
      const date = (cells[idx.date] ?? "").trim();

      // Up-front shape check so a malformed row doesn't create a stub holding.
      if (!["buy", "sell", "dividend", "fee"].includes(type)) {
        errors.push({ row: lineNo, message: `type: must be buy/sell/dividend/fee (got "${type}")` });
        continue;
      }
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
        errors.push({ row: lineNo, message: "date: Date must be YYYY-MM-DD" });
        continue;
      }

      const rawCurrency = idx.currency >= 0 ? (cells[idx.currency] ?? "").trim().toUpperCase() : "";
      const currency = isSupportedCurrency(rawCurrency) ? rawCurrency : DEFAULT_CURRENCY;

      const candidate = {
        holdingId: await resolveHolding(ticker),
        type,
        date,
        shares: idx.shares >= 0 ? parseNum(cells[idx.shares]) : undefined,
        price: idx.price >= 0 ? parseNum(cells[idx.price]) : undefined,
        fee: idx.fee >= 0 ? parseNum(cells[idx.fee]) ?? 0 : 0,
        tax: idx.tax >= 0 ? parseNum(cells[idx.tax]) ?? 0 : 0,
        currency,
        notes: idx.notes >= 0 ? (cells[idx.notes] ?? "").trim() || undefined : undefined,
      };

      const parsed = transactionSchema.safeParse(candidate);
      if (!parsed.success) {
        const first = parsed.error.issues[0];
        errors.push({ row: lineNo, message: first ? `${first.path.join(".")}: ${first.message}` : "Invalid row" });
        continue;
      }

      const data = parsed.data;
      db.insert(transactions)
        .values({
          portfolioId,
          holdingId: data.holdingId,
          type: data.type,
          date: data.date,
          shares: data.shares ?? null,
          price: data.price ?? null,
          fee: data.fee ?? 0,
          tax: data.tax ?? 0,
          currency: data.currency ?? DEFAULT_CURRENCY,
          notes: data.notes ?? null,
          createdAt: now,
        })
        .run();
      imported++;
    } catch (e) {
      errors.push({ row: lineNo, message: e instanceof Error ? e.message : "Unknown error" });
    }
  }

  return NextResponse.json({ imported, failed: errors.length, errors });
}
