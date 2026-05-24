import { default as YahooFinance } from "yahoo-finance2";

export interface Quote {
  ticker: string;
  name: string | null;
  price: number | null;
  currency: string | null;
}

export interface QuoteDetails extends Quote {
  sector: string | null;
  assetClass: "stock" | "etf" | "bond" | "cash";
}

const yf = new YahooFinance({ suppressNotices: ["yahooSurvey"] });

export async function fetchQuotes(tickers: string[]): Promise<Quote[]> {
  const results = await Promise.allSettled(
    tickers.map((ticker) => fetchSingleQuote(ticker))
  );
  return results.map((r, i) =>
    r.status === "fulfilled"
      ? r.value
      : { ticker: tickers[i], name: null, price: null, currency: null }
  );
}

export async function fetchQuoteDetails(ticker: string): Promise<QuoteDetails> {
  try {
    const quote = await yf.quote(ticker);
    const assetClass = mapQuoteType((quote as { quoteType?: string }).quoteType);

    let sector: string | null = null;
    if (assetClass === "stock") {
      try {
        const summary = await yf.quoteSummary(ticker, { modules: ["assetProfile"] });
        sector = (summary.assetProfile as { sector?: string } | null)?.sector ?? null;
      } catch {
        // sector unavailable for this ticker
      }
    }

    return {
      ticker,
      name: quote.shortName ?? quote.longName ?? null,
      price: quote.regularMarketPrice ?? null,
      currency: quote.currency ?? null,
      sector,
      assetClass,
    };
  } catch {
    return { ticker, name: null, price: null, currency: null, sector: null, assetClass: "stock" };
  }
}

function mapQuoteType(quoteType?: string): "stock" | "etf" | "bond" | "cash" {
  switch (quoteType?.toUpperCase()) {
    case "ETF":
    case "MUTUALFUND":
      return "etf";
    case "BOND":
      return "bond";
    case "CURRENCY":
      return "cash";
    default:
      return "stock";
  }
}

async function fetchSingleQuote(ticker: string): Promise<Quote> {
  try {
    const quote = await yf.quote(ticker);
    return {
      ticker,
      name: quote.shortName ?? quote.longName ?? null,
      price: quote.regularMarketPrice ?? null,
      currency: quote.currency ?? null,
    };
  } catch {
    return { ticker, name: null, price: null, currency: null };
  }
}
