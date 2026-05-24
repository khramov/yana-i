"use client";

import useSWR from "swr";
import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

interface DividendRow {
  id: number;
  ticker: string;
  name: string | null;
  date: string;
  amount: number;
  shares: number | null;
  perShare: number | null;
  tax: number;
  currency: string;
  yieldOnCost: number | null;
}

interface DividendData {
  baseCurrency: string;
  totalAllTime: number;
  trailing12m: number;
  yieldOnCost: number | null;
  years: number[];
  rows: DividendRow[];
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

function fmtPct(n: number | null) {
  if (n == null) return "—";
  return `${n.toFixed(2)}%`;
}

function KpiCard({ title, value }: { title: string; value: string }) {
  return (
    <Card>
      <CardHeader className="pb-1 pt-4 px-5">
        <CardTitle className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent className="pb-4 px-5">
        <p className="text-xl font-semibold font-mono">{value}</p>
      </CardContent>
    </Card>
  );
}

function PageSkeleton() {
  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {Array.from({ length: 3 }).map((_, i) => (
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
      <div className="space-y-2">
        {Array.from({ length: 6 }).map((_, i) => (
          <Skeleton key={i} className="h-10 w-full" />
        ))}
      </div>
    </div>
  );
}

export function DividendsPage() {
  const [year, setYear] = useState<string>("all");

  const url =
    year === "all"
      ? "/api/portfolio/dividends"
      : `/api/portfolio/dividends?year=${year}`;

  const { data, isLoading } = useSWR<DividendData>(url, fetcher);

  if (isLoading) return <PageSkeleton />;

  const d = data ?? {
    baseCurrency: "USD",
    totalAllTime: 0,
    trailing12m: 0,
    yieldOnCost: null,
    years: [],
    rows: [],
  };

  const bc = d.baseCurrency;

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <KpiCard title="Total Received (All Time)" value={fmtCurrency(d.totalAllTime, bc)} />
        <KpiCard title="Trailing 12 Months" value={fmtCurrency(d.trailing12m, bc)} />
        <KpiCard title="Yield on Cost" value={fmtPct(d.yieldOnCost)} />
      </div>

      <div className="flex items-center justify-between gap-4">
        <h2 className="text-sm font-medium text-muted-foreground">
          {year === "all" ? "All dividends" : `Dividends in ${year}`}
          {d.rows.length > 0 && (
            <span className="ml-2 text-xs">({d.rows.length})</span>
          )}
        </h2>
        <Select value={year} onValueChange={(v) => v && setYear(v)}>
          <SelectTrigger className="w-32">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All years</SelectItem>
            {d.years.map((y) => (
              <SelectItem key={y} value={y.toString()}>
                {y}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {d.rows.length === 0 ? (
        <Card>
          <CardContent className="py-16 text-center text-muted-foreground text-sm">
            {year === "all"
              ? "No dividend transactions recorded yet."
              : `No dividends recorded for ${year}.`}
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardContent className="px-0 pb-2">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b">
                  <th className="text-left font-medium text-muted-foreground px-5 pb-2 pt-3">
                    Ticker
                  </th>
                  <th className="text-left font-medium text-muted-foreground px-5 pb-2 pt-3">
                    Date
                  </th>
                  <th className="text-right font-medium text-muted-foreground px-5 pb-2 pt-3">
                    Amount
                  </th>
                  <th className="text-right font-medium text-muted-foreground px-5 pb-2 pt-3">
                    Shares
                  </th>
                  <th className="text-right font-medium text-muted-foreground px-5 pb-2 pt-3">
                    Per Share
                  </th>
                  <th className="text-right font-medium text-muted-foreground px-5 pb-2 pt-3">
                    Tax
                  </th>
                  <th className="text-right font-medium text-muted-foreground px-5 pb-2 pt-3">
                    Yield on Cost
                  </th>
                </tr>
              </thead>
              <tbody>
                {d.rows.map((row) => (
                  <tr key={row.id} className="border-b last:border-0 hover:bg-muted/40">
                    <td className="px-5 py-2.5">
                      <span className="font-medium">{row.ticker}</span>
                      {row.name && (
                        <span className="ml-2 text-xs text-muted-foreground">
                          {row.name}
                        </span>
                      )}
                    </td>
                    <td className="px-5 py-2.5 text-muted-foreground">{row.date}</td>
                    <td className="px-5 py-2.5 text-right font-mono">
                      {fmtCurrency(row.amount, row.currency)}
                    </td>
                    <td className="px-5 py-2.5 text-right font-mono text-muted-foreground">
                      {row.shares != null ? row.shares.toLocaleString() : "—"}
                    </td>
                    <td className="px-5 py-2.5 text-right font-mono text-muted-foreground">
                      {fmtCurrency(row.perShare, row.currency)}
                    </td>
                    <td className="px-5 py-2.5 text-right font-mono text-muted-foreground">
                      {row.tax > 0 ? fmtCurrency(row.tax, row.currency) : "—"}
                    </td>
                    <td className="px-5 py-2.5 text-right font-mono text-green-600">
                      {fmtPct(row.yieldOnCost)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
