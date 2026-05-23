import { default as YahooFinance } from "yahoo-finance2";

export interface Quote {
  ticker: string;
  name: string | null;
  price: number | null;
  currency: string | null;
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
