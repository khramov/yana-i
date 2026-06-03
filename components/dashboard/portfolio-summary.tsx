"use client";

import useSWR from "swr";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { displayTicker } from "@/lib/ticker";

interface Top5Entry {
  ticker: string;
  name: string | null;
  marketValue: number;
  weight: number | null;
  pnlPct: number | null;
}

interface SummaryData {
  baseCurrency: string;
  totalValue: number | null;
  costBasis: number;
  unrealizedPnl: number | null;
  totalReturnPct: number | null;
  dividendsReceived: number;
  holdingsCount: number;
  top5: Top5Entry[];
}

const fetcher = (url: string) => fetch(url).then((r) => r.json());

function fmtCurrency(n: number | null, currency = "USD") {
  if (n == null) return "—";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(n);
}

function fmtPct(n: number | null, { sign = false } = {}) {
  if (n == null) return "—";
  const prefix = sign && n > 0 ? "+" : "";
  return `${prefix}${n.toFixed(2)}%`;
}

function KpiCard({
  title,
  value,
  colorValue,
}: {
  title: string;
  value: string;
  colorValue?: number | null;
}) {
  const colored = colorValue != null;
  const positive = (colorValue ?? 0) >= 0;
  return (
    <Card>
      <CardHeader className="pb-1 pt-4 px-5">
        <CardTitle className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent className="pb-4 px-5">
        <p
          className={cn(
            "text-xl font-semibold font-mono",
            colored && positive && "text-green-600",
            colored && !positive && "text-red-500"
          )}
        >
          {value}
        </p>
      </CardContent>
    </Card>
  );
}

function SummarySkeleton() {
  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
        {Array.from({ length: 6 }).map((_, i) => (
          <Card key={i}>
            <CardHeader className="pb-1 pt-4 px-5">
              <Skeleton className="h-3 w-24" />
            </CardHeader>
            <CardContent className="pb-4 px-5">
              <Skeleton className="h-6 w-32 mt-1" />
            </CardContent>
          </Card>
        ))}
      </div>
      <Card>
        <CardHeader className="pb-2">
          <Skeleton className="h-4 w-28" />
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {Array.from({ length: 5 }).map((_, i) => (
              <Skeleton key={i} className="h-4 w-full" />
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

export function PortfolioSummary() {
  const { data, isLoading } = useSWR<SummaryData>("/api/portfolio/summary", fetcher, {
    refreshInterval: 60_000,
  });

  if (isLoading) return <SummarySkeleton />;

  const d = data ?? {
    baseCurrency: "USD",
    totalValue: null,
    costBasis: 0,
    unrealizedPnl: null,
    totalReturnPct: null,
    dividendsReceived: 0,
    holdingsCount: 0,
    top5: [],
  };

  const bc = d.baseCurrency;
  const fmt = (n: number | null) => fmtCurrency(n, bc);

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
        <KpiCard title="Total Value" value={fmt(d.totalValue)} />
        <KpiCard title="Cost Basis" value={fmt(d.costBasis)} />
        <KpiCard
          title="Unrealized P&L"
          value={
            d.unrealizedPnl != null
              ? `${d.unrealizedPnl >= 0 ? "+" : ""}${fmt(d.unrealizedPnl)}`
              : "—"
          }
          colorValue={d.unrealizedPnl}
        />
        <KpiCard
          title="Total Return"
          value={fmtPct(d.totalReturnPct, { sign: true })}
          colorValue={d.totalReturnPct}
        />
        <KpiCard title="Dividends Received" value={fmt(d.dividendsReceived)} />
        <KpiCard title="Open Positions" value={d.holdingsCount.toString()} />
      </div>

      {d.top5.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-semibold">Top Positions</CardTitle>
          </CardHeader>
          <CardContent className="px-0 pb-2">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b">
                  <th className="text-left font-medium text-muted-foreground px-5 pb-2">Ticker</th>
                  <th className="text-right font-medium text-muted-foreground px-5 pb-2">Market Value</th>
                  <th className="text-right font-medium text-muted-foreground px-5 pb-2">Weight</th>
                  <th className="text-right font-medium text-muted-foreground px-5 pb-2">P&L %</th>
                </tr>
              </thead>
              <tbody>
                {d.top5.map((p) => {
                  const pnlPositive = p.pnlPct != null && p.pnlPct >= 0;
                  return (
                    <tr key={p.ticker} className="border-b last:border-0 hover:bg-muted/40">
                      <td className="px-5 py-2.5">
                        <span className="font-medium">{displayTicker(p.ticker)}</span>
                        {p.name && (
                          <span className="ml-2 text-xs text-muted-foreground">{p.name}</span>
                        )}
                      </td>
                      <td className="px-5 py-2.5 text-right font-mono">
                        {fmt(p.marketValue)}
                      </td>
                      <td className="px-5 py-2.5 text-right font-mono text-muted-foreground">
                        {fmtPct(p.weight)}
                      </td>
                      <td
                        className={cn(
                          "px-5 py-2.5 text-right font-mono",
                          p.pnlPct != null && pnlPositive && "text-green-600",
                          p.pnlPct != null && !pnlPositive && "text-red-500"
                        )}
                      >
                        {fmtPct(p.pnlPct, { sign: true })}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
