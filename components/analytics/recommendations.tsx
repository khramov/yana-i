"use client";

import useSWR from "swr";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { displayTicker } from "@/lib/ticker";
import { formatAssetClass } from "@/lib/asset-class";

interface RecRow {
  key: string;
  name: string | null;
  currentValue: number;
  currentPct: number;
  targetPct: number | null;
  driftPct: number | null;
  buyAmount: number;
  buyShares: number | null;
}

interface RecResponse {
  baseCurrency: string;
  totalValue: number;
  holding: { hasGoals: boolean; rows: RecRow[] };
  assetClass: { hasGoals: boolean; rows: RecRow[] };
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

function fmtShares(n: number) {
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: 4 }).format(n);
}

function Section({
  title,
  scope,
  data,
  currency,
}: {
  title: string;
  scope: "holding" | "asset_class";
  data: { hasGoals: boolean; rows: RecRow[] };
  currency: string;
}) {
  const label = (key: string) =>
    scope === "holding" ? displayTicker(key) : formatAssetClass(key);
  const buys = data.rows.filter((r) => r.buyAmount > 0.5);

  return (
    <div className="flex flex-col gap-2">
      <h3 className="text-sm font-medium">{title}</h3>
      {!data.hasGoals ? (
        <p className="text-sm text-muted-foreground">
          No targets set. Use “Set goals” on the allocation card to get suggestions.
        </p>
      ) : buys.length === 0 ? (
        <p className="text-sm text-green-600">On target — nothing to buy right now.</p>
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-muted-foreground text-xs border-b">
              <th className="pb-2 font-medium">{scope === "holding" ? "Holding" : "Asset class"}</th>
              <th className="pb-2 font-medium text-right">Current</th>
              <th className="pb-2 font-medium text-right">Target</th>
              <th className="pb-2 font-medium text-right">Buy</th>
              {scope === "holding" && <th className="pb-2 font-medium text-right">≈ Shares</th>}
            </tr>
          </thead>
          <tbody>
            {buys.map((r) => (
              <tr key={r.key} className="border-b last:border-0">
                <td className="py-2 font-medium">{label(r.key)}</td>
                <td className="py-2 text-right tabular-nums text-muted-foreground">
                  {r.currentPct.toFixed(1)}%
                </td>
                <td className="py-2 text-right tabular-nums text-muted-foreground">
                  {r.targetPct != null ? `${r.targetPct.toFixed(1)}%` : "—"}
                </td>
                <td className="py-2 text-right tabular-nums font-medium">
                  {fmtCurrency(r.buyAmount, currency)}
                </td>
                {scope === "holding" && (
                  <td className="py-2 text-right tabular-nums text-muted-foreground">
                    {r.buyShares != null ? fmtShares(r.buyShares) : "—"}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

export function Recommendations() {
  const { data, isLoading } = useSWR<RecResponse>(
    "/api/portfolio/recommendations",
    fetcher,
    { refreshInterval: 60_000 }
  );

  const currency = data?.baseCurrency ?? "USD";

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base font-semibold">What to buy now</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        {isLoading || !data ? (
          <Skeleton className="h-32 w-full" />
        ) : (
          <>
            <p className="text-xs text-muted-foreground -mt-1">
              Amounts needed to bring underweight positions up to their targets at the current
              portfolio value ({fmtCurrency(data.totalValue, currency)}).
            </p>
            <Section title="By holding" scope="holding" data={data.holding} currency={currency} />
            <Section
              title="By asset class"
              scope="asset_class"
              data={data.assetClass}
              currency={currency}
            />
          </>
        )}
      </CardContent>
    </Card>
  );
}
