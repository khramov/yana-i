"use client";

import { useState } from "react";
import useSWR from "swr";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { X } from "lucide-react";
import { AddTickerForm } from "./add-ticker-form";
import { WatchlistSkeleton } from "./watchlist-skeleton";
import { displayTicker } from "@/lib/ticker";

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

  const [removeError, setRemoveError] = useState<string | null>(null);
  const [removingId, setRemovingId] = useState<number | null>(null);

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

  async function removeTicker(id: number) {
    setRemoveError(null);
    setRemovingId(id);
    try {
      const res = await fetch(`/api/holdings/${id}`, { method: "DELETE" });
      if (!res.ok) {
        const json = await res.json().catch(() => ({}));
        setRemoveError(json.error ?? "Failed to remove");
        return;
      }
      mutateHoldings();
    } finally {
      setRemovingId(null);
    }
  }

  const isLoading = holdingsLoading || (!!tickers && pricesLoading);

  return (
    <Card className="w-full">
      <CardHeader>
        <CardTitle>Watchlist</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <AddTickerForm onAdd={addTicker} />

        {removeError && (
          <p className="text-sm text-destructive">{removeError}</p>
        )}

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
                  className="group flex items-center justify-between py-3"
                >
                  <div className="flex flex-col">
                    <span className="font-medium text-sm">{displayTicker(h.ticker)}</span>
                    <span className="text-xs text-muted-foreground">
                      {h.name ?? "—"}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-mono">
                      {formatPrice(entry?.price ?? null, entry?.currency ?? null)}
                    </span>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-7 w-7 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 hover:text-destructive"
                      title={`Remove ${displayTicker(h.ticker)}`}
                      disabled={removingId === h.id}
                      onClick={() => removeTicker(h.id)}
                    >
                      <X className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
