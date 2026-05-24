"use client";

import { useState } from "react";
import useSWR from "swr";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";

interface HoldingRow {
  holdingId: number;
  ticker: string;
  name: string | null;
  sharesHeld: number;
  avgCost: number | null;
  nativeCurrency: string;
  currentPrice: number | null;
  marketValue: number | null;   // base currency
  unrealizedPnl: number | null; // base currency
  pnlPct: number | null;
}

interface HoldingsResponse {
  baseCurrency: string;
  positions: HoldingRow[];
}

const fetcher = (url: string) => fetch(url).then((r) => r.json());

function fmt(n: number | null, currency = "USD", decimals = 2) {
  if (n == null) return "—";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(n);
}

function fmtShares(n: number) {
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 6,
    minimumFractionDigits: 0,
  }).format(n);
}

function PnlCell({
  value,
  pct,
  currency,
}: {
  value: number | null;
  pct: number | null;
  currency: string;
}) {
  if (value == null) return <span className="text-muted-foreground">—</span>;
  const positive = value >= 0;
  return (
    <span className={cn("font-mono", positive ? "text-green-600" : "text-red-500")}>
      {positive ? "+" : ""}
      {value.toLocaleString("en-US", {
        style: "currency",
        currency,
        minimumFractionDigits: 2,
      })}
      {pct != null && (
        <span className="ml-1.5 text-xs opacity-75">
          ({positive ? "+" : ""}
          {pct.toFixed(2)}%)
        </span>
      )}
    </span>
  );
}

export function HoldingsTable() {
  const [showClosed, setShowClosed] = useState(false);
  const { data, isLoading } = useSWR<HoldingsResponse>(
    "/api/portfolio/holdings",
    fetcher,
    { refreshInterval: 60_000 }
  );

  const baseCurrency = data?.baseCurrency ?? "USD";
  const rows = data?.positions ?? [];
  const visible = rows.filter((r) => showClosed || r.sharesHeld > 0);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-2">
        <Switch
          id="show-closed"
          checked={showClosed}
          onCheckedChange={setShowClosed}
        />
        <Label htmlFor="show-closed" className="text-sm text-muted-foreground cursor-pointer">
          Show closed positions
        </Label>
      </div>

      <div className="rounded-lg border overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b bg-muted/40 text-muted-foreground">
              <th className="text-left px-4 py-3 font-medium">Ticker</th>
              <th className="text-left px-4 py-3 font-medium">Name</th>
              <th className="text-right px-4 py-3 font-medium">Shares</th>
              <th className="text-right px-4 py-3 font-medium">Avg Cost</th>
              <th className="text-right px-4 py-3 font-medium">Current Price</th>
              <th className="text-right px-4 py-3 font-medium">
                Market Value ({baseCurrency})
              </th>
              <th className="text-right px-4 py-3 font-medium">
                Unrealized P&amp;L ({baseCurrency})
              </th>
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              Array.from({ length: 5 }).map((_, i) => (
                <tr key={i} className="border-b">
                  {Array.from({ length: 7 }).map((_, j) => (
                    <td key={j} className="px-4 py-3">
                      <Skeleton className="h-4 w-full" />
                    </td>
                  ))}
                </tr>
              ))
            ) : visible.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-4 py-12 text-center text-muted-foreground">
                  {rows.length > 0
                    ? 'No open positions. Toggle "Show closed" to see past holdings.'
                    : "No holdings yet. Add tickers from the dashboard and record transactions."}
                </td>
              </tr>
            ) : (
              visible.map((row) => (
                <tr
                  key={row.holdingId}
                  className={cn(
                    "border-b hover:bg-muted/20 transition-colors",
                    row.sharesHeld === 0 && "opacity-50"
                  )}
                >
                  <td className="px-4 py-3 font-semibold">{row.ticker}</td>
                  <td className="px-4 py-3 text-muted-foreground max-w-[200px] truncate">
                    {row.name ?? "—"}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums font-mono">
                    {fmtShares(row.sharesHeld)}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums font-mono">
                    {fmt(row.avgCost, row.nativeCurrency, 4)}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums font-mono">
                    {fmt(row.currentPrice, row.nativeCurrency)}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums font-mono">
                    {fmt(row.marketValue, baseCurrency)}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <PnlCell value={row.unrealizedPnl} pct={row.pnlPct} currency={baseCurrency} />
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
