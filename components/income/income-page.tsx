"use client";

import useSWR, { mutate as globalMutate } from "swr";
import { useState } from "react";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  Cell,
} from "recharts";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { displayTicker } from "@/lib/ticker";
import { Button } from "@/components/ui/button";

interface MonthlyIncome {
  month: string; // YYYY-MM
  amount: number;
}

interface ByHoldingRow {
  ticker: string;
  name: string | null;
  trailing12m: number;
  forward: number;
}

interface IncomeResponse {
  baseCurrency: string;
  monthly: MonthlyIncome[];
  forwardAnnual: number;
  byHolding: ByHoldingRow[];
  lastRefreshed: number | null;
}

const fetcher = (url: string) => fetch(url).then((r) => r.json());

function fmt(n: number, currency: string) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(n);
}

function fmtTs(ts: number | null): string {
  if (!ts) return "Never";
  return new Date(ts * 1000).toLocaleString();
}

function monthLabel(ym: string): string {
  const [y, m] = ym.split("-");
  const d = new Date(Number(y), Number(m) - 1, 1);
  return d.toLocaleString("en-US", { month: "short", year: "2-digit" });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function CustomTooltip({ active, payload, currency }: any) {
  if (!active || !payload?.length) return null;
  const d = payload[0];
  return (
    <div className="rounded-lg border bg-background px-3 py-2 shadow-sm text-sm">
      <p className="font-medium">{d.payload.monthLabel}</p>
      <p className="text-muted-foreground">{fmt(d.value, currency)}</p>
    </div>
  );
}

export function IncomePage() {
  const { data, isLoading } = useSWR<IncomeResponse>("/api/portfolio/income", fetcher);
  const [refreshing, setRefreshing] = useState(false);
  const [refreshError, setRefreshError] = useState<string | null>(null);

  const currency = data?.baseCurrency ?? "USD";
  const monthly = data?.monthly ?? [];
  const byHolding = data?.byHolding ?? [];
  const forwardAnnual = data?.forwardAnnual ?? 0;
  const lastRefreshed = data?.lastRefreshed ?? null;

  // Show last 24 months
  const recentMonths = monthly.slice(-24);
  const chartData = recentMonths.map((m) => ({
    month: m.month,
    monthLabel: monthLabel(m.month),
    amount: m.amount,
  }));

  const trailing12mTotal = byHolding.reduce((s, h) => s + h.trailing12m, 0);

  async function handleRefresh() {
    setRefreshing(true);
    setRefreshError(null);
    try {
      const res = await fetch("/api/dividends/refresh", { method: "POST" });
      if (!res.ok) throw new Error("Refresh failed");
      await globalMutate("/api/portfolio/income");
    } catch (err) {
      setRefreshError(err instanceof Error ? err.message : "Unknown error");
    } finally {
      setRefreshing(false);
    }
  }

  return (
    <div className="flex flex-col gap-6">
      {/* Summary cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Trailing 12 Months
            </CardTitle>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <Skeleton className="h-8 w-28" />
            ) : (
              <p className="text-2xl font-semibold tabular-nums">
                {fmt(trailing12mTotal, currency)}
              </p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Forward Annual (est.)
            </CardTitle>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <Skeleton className="h-8 w-28" />
            ) : forwardAnnual > 0 ? (
              <p className="text-2xl font-semibold tabular-nums">
                {fmt(forwardAnnual, currency)}
              </p>
            ) : (
              <p className="text-2xl font-semibold text-muted-foreground">—</p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Monthly Average (TTM)
            </CardTitle>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <Skeleton className="h-8 w-28" />
            ) : (
              <p className="text-2xl font-semibold tabular-nums">
                {fmt(trailing12mTotal / 12, currency)}
              </p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Monthly bar chart */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-base font-semibold">Monthly Income</CardTitle>
        </CardHeader>
        <CardContent className="pb-4">
          {isLoading ? (
            <Skeleton className="h-56 w-full" />
          ) : chartData.length === 0 ? (
            <div className="h-56 flex items-center justify-center">
              <p className="text-muted-foreground text-sm">No dividend transactions yet.</p>
            </div>
          ) : (
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={chartData} margin={{ top: 4, right: 4, left: 0, bottom: 0 }}>
                <XAxis
                  dataKey="monthLabel"
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                  interval="preserveStartEnd"
                />
                <YAxis
                  tickFormatter={(v) =>
                    new Intl.NumberFormat("en-US", {
                      notation: "compact",
                      currency,
                      style: "currency",
                      maximumFractionDigits: 0,
                    }).format(v)
                  }
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                  width={60}
                />
                <Tooltip content={<CustomTooltip currency={currency} />} />
                <Bar dataKey="amount" radius={[3, 3, 0, 0]} maxBarSize={32}>
                  {chartData.map((_, i) => (
                    <Cell key={i} fill="#3b82f6" />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          )}
        </CardContent>
      </Card>

      {/* Income by holding */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-base font-semibold">Income by Holding</CardTitle>
          <div className="flex flex-col items-end gap-1">
            <Button
              size="sm"
              variant="outline"
              onClick={handleRefresh}
              disabled={refreshing}
            >
              {refreshing ? "Refreshing…" : "Refresh Estimates"}
            </Button>
            <span className="text-xs text-muted-foreground">
              Updated: {fmtTs(lastRefreshed)}
            </span>
          </div>
        </CardHeader>
        <CardContent className="pb-4">
          {refreshError && (
            <p className="text-destructive text-sm mb-2">{refreshError}</p>
          )}
          {isLoading ? (
            <Skeleton className="h-40 w-full" />
          ) : byHolding.length === 0 ? (
            <p className="text-muted-foreground text-sm py-6 text-center">
              No dividend data yet. Add dividend transactions to see income by holding.
            </p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-muted-foreground text-xs border-b">
                  <th className="pb-2 font-medium">Ticker</th>
                  <th className="pb-2 font-medium text-right">Trailing 12m</th>
                  <th className="pb-2 font-medium text-right">Forward Annual</th>
                  <th className="pb-2 font-medium text-right">% of Total</th>
                </tr>
              </thead>
              <tbody>
                {byHolding.map((h) => (
                  <tr key={h.ticker} className="border-b last:border-0">
                    <td className="py-2">
                      <span className="font-medium">{displayTicker(h.ticker)}</span>
                      {h.name && (
                        <span className="text-muted-foreground ml-2 text-xs truncate max-w-[200px] inline-block align-middle">
                          {h.name}
                        </span>
                      )}
                    </td>
                    <td className="py-2 text-right tabular-nums">
                      {h.trailing12m > 0 ? fmt(h.trailing12m, currency) : "—"}
                    </td>
                    <td className="py-2 text-right tabular-nums">
                      {h.forward > 0 ? fmt(h.forward, currency) : "—"}
                    </td>
                    <td className="py-2 text-right tabular-nums text-muted-foreground">
                      {trailing12mTotal > 0
                        ? ((h.trailing12m / trailing12mTotal) * 100).toFixed(1) + "%"
                        : "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
