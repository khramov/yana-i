"use client";

import useSWR from "swr";
import { useState } from "react";
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
} from "recharts";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

interface Snapshot {
  date: string;
  totalValue: number;
  costBasis: number;
  baseCurrency: string;
}

type Range = "1M" | "3M" | "6M" | "1Y" | "All";

const RANGES: Range[] = ["1M", "3M", "6M", "1Y", "All"];

function fromDateForRange(range: Range): string | null {
  if (range === "All") return null;
  const days: Record<Exclude<Range, "All">, number> = {
    "1M": 30,
    "3M": 90,
    "6M": 180,
    "1Y": 365,
  };
  const d = new Date();
  d.setDate(d.getDate() - days[range]);
  return d.toISOString().slice(0, 10);
}

const fetcher = (url: string) => fetch(url).then((r) => r.json());

function fmtCurrency(n: number, currency: string) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(n);
}

function fmtAxisDate(date: string, range: Range) {
  const d = new Date(date + "T00:00:00");
  if (range === "1M") return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  return d.toLocaleDateString("en-US", { month: "short", year: "2-digit" });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function CustomTooltip({ active, payload, label, currency }: any) {
  if (!active || !payload?.length) return null;
  const value = payload.find((p: any) => p.dataKey === "totalValue")?.value;
  const cost = payload.find((p: any) => p.dataKey === "costBasis")?.value;
  const date = new Date(label + "T00:00:00").toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
  });
  return (
    <div className="rounded-lg border bg-background px-3 py-2 shadow-sm text-sm">
      <p className="text-muted-foreground mb-1">{date}</p>
      {value != null && (
        <p className="font-semibold">{fmtCurrency(value, currency)}</p>
      )}
      {cost != null && (
        <p className="text-muted-foreground text-xs">Cost basis: {fmtCurrency(cost, currency)}</p>
      )}
    </div>
  );
}

export function GrowthChart() {
  const [range, setRange] = useState<Range>("1Y");
  const from = fromDateForRange(range);
  const url = from
    ? `/api/portfolio/history?from=${from}`
    : `/api/portfolio/history`;

  const { data, isLoading } = useSWR<Snapshot[]>(url, fetcher);

  const currency = data?.[0]?.baseCurrency ?? "USD";

  const minValue = data && data.length > 0
    ? Math.min(...data.map((d) => Math.min(d.totalValue, d.costBasis))) * 0.95
    : 0;
  const maxValue = data && data.length > 0
    ? Math.max(...data.map((d) => Math.max(d.totalValue, d.costBasis))) * 1.05
    : undefined;

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between pb-2">
        <CardTitle className="text-base font-semibold">Portfolio Growth</CardTitle>
        <div className="flex gap-1">
          {RANGES.map((r) => (
            <button
              key={r}
              onClick={() => setRange(r)}
              className={cn(
                "px-2.5 py-1 rounded text-xs font-medium transition-colors",
                r === range
                  ? "bg-primary text-primary-foreground"
                  : "text-muted-foreground hover:text-foreground hover:bg-muted"
              )}
            >
              {r}
            </button>
          ))}
        </div>
      </CardHeader>

      <CardContent className="pb-4">
        {isLoading ? (
          <Skeleton className="h-64 w-full" />
        ) : !data || data.length === 0 ? (
          <div className="h-64 flex flex-col items-center justify-center gap-2 text-center">
            <p className="text-muted-foreground text-sm">No data yet for this range.</p>
            <p className="text-muted-foreground text-xs">
              A snapshot is recorded each day when you open the app. Come back tomorrow to see your
              first data point.
            </p>
          </div>
        ) : data.length === 1 ? (
          <div className="h-64 flex flex-col items-center justify-center gap-2 text-center">
            <p className="font-semibold text-lg">{fmtCurrency(data[0].totalValue, currency)}</p>
            <p className="text-muted-foreground text-sm">First snapshot recorded today.</p>
            <p className="text-muted-foreground text-xs">
              The chart will fill in as daily snapshots accumulate.
            </p>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={256}>
            <AreaChart data={data} margin={{ top: 4, right: 4, left: 0, bottom: 0 }}>
              <defs>
                <linearGradient id="gradValue" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.2} />
                  <stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
              <XAxis
                dataKey="date"
                tickFormatter={(v) => fmtAxisDate(v, range)}
                tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }}
                axisLine={false}
                tickLine={false}
                minTickGap={40}
              />
              <YAxis
                domain={[minValue, maxValue ?? "auto"]}
                tickFormatter={(v) =>
                  new Intl.NumberFormat("en-US", {
                    notation: "compact",
                    style: "currency",
                    currency,
                    maximumFractionDigits: 1,
                  }).format(v)
                }
                tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }}
                axisLine={false}
                tickLine={false}
                width={60}
              />
              <Tooltip content={<CustomTooltip currency={currency} />} />
              <Area
                type="monotone"
                dataKey="costBasis"
                stroke="hsl(var(--muted-foreground))"
                strokeWidth={1.5}
                strokeDasharray="4 2"
                fill="none"
                dot={false}
                name="Cost Basis"
              />
              <Area
                type="monotone"
                dataKey="totalValue"
                stroke="hsl(var(--primary))"
                strokeWidth={2}
                fill="url(#gradValue)"
                dot={false}
                name="Portfolio Value"
              />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </CardContent>
    </Card>
  );
}
