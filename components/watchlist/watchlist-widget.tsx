"use client";

import useSWR from "swr";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { AddTickerForm } from "./add-ticker-form";
import { WatchlistSkeleton } from "./watchlist-skeleton";

interface Holding {
  id: number;
  ticker: string;
  name: string | null;
}

interface PriceEntry {
  ticker: string;
  price: number | null;
  currency: string | null;
}

const fetcher = (url: string) => fetch(url).then((r) => r.json());

function formatPrice(price: number | null, currency: string | null) {
  if (price === null) return "—";
  const locale = "en-US";
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency: currency ?? "USD",
    minimumFractionDigits: 2,
  }).format(price);
}

export function WatchlistWidget() {
  const {
    data: holdings,
    isLoading: holdingsLoading,
    mutate: mutateHoldings,
  } = useSWR<Holding[]>("/api/holdings", fetcher);

  const tickers = holdings?.map((h) => h.ticker).join(",") ?? "";

  const { data: prices, isLoading: pricesLoading } = useSWR<PriceEntry[]>(
    tickers ? `/api/prices?tickers=${tickers}` : null,
    fetcher,
    { refreshInterval: 60_000 }
  );

  const priceMap = new Map(prices?.map((p) => [p.ticker, p]) ?? []);

  async function addTicker(ticker: string) {
    const res = await fetch("/api/holdings", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ticker }),
    });
    if (!res.ok) {
      const json = await res.json();
      throw new Error(json.error ?? "Failed to add");
    }
    mutateHoldings();
  }

  const isLoading = holdingsLoading || (!!tickers && pricesLoading);

  return (
    <Card className="w-full">
      <CardHeader>
        <CardTitle>Watchlist</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <AddTickerForm onAdd={addTicker} />

        {isLoading ? (
          <WatchlistSkeleton />
        ) : !holdings || holdings.length === 0 ? (
          <p className="text-sm text-muted-foreground py-4 text-center">
            No tickers yet. Add one above.
          </p>
        ) : (
          <div className="flex flex-col divide-y">
            {holdings.map((h) => {
              const entry = priceMap.get(h.ticker);
              return (
                <div
                  key={h.id}
                  className="flex items-center justify-between py-3"
                >
                  <div className="flex flex-col">
                    <span className="font-medium text-sm">{h.ticker}</span>
                    <span className="text-xs text-muted-foreground">
                      {h.name ?? "—"}
                    </span>
                  </div>
                  <span className="text-sm font-mono">
                    {formatPrice(entry?.price ?? null, entry?.currency ?? null)}
                  </span>
                </div>
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
