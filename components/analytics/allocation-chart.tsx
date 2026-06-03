"use client";

import useSWR, { useSWRConfig } from "swr";
import { useState } from "react";
import {
  PieChart,
  Pie,
  Cell,
  Tooltip,
  ResponsiveContainer,
} from "recharts";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { Target } from "lucide-react";
import { cn } from "@/lib/utils";
import { displayTicker } from "@/lib/ticker";
import { ASSET_CLASSES, formatAssetClass } from "@/lib/asset-class";
import { GoalEditor, type GoalOption } from "./goal-editor";

interface AllocationSlice {
  key: string;
  label: string;
  value: number;
  percentage: number;
}

interface AllocationResponse {
  baseCurrency: string;
  slices: AllocationSlice[];
}

interface GoalsResponse {
  holding: { key: string; pct: number }[];
  asset_class: { key: string; pct: number }[];
}

type GroupBy = "holding" | "sector" | "asset_class";

const VIEWS: { key: GroupBy; label: string }[] = [
  { key: "holding", label: "Holding" },
  { key: "sector", label: "Sector" },
  { key: "asset_class", label: "Asset Class" },
];

const PALETTE = [
  "#3b82f6", "#10b981", "#f59e0b", "#8b5cf6", "#ef4444",
  "#ec4899", "#06b6d4", "#84cc16", "#f97316", "#6366f1",
];

const fetcher = (url: string) => fetch(url).then((r) => r.json());

function fmtCurrency(n: number, currency: string) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(n);
}

function sliceLabel(view: GroupBy, slice: AllocationSlice) {
  return view === "holding" ? displayTicker(slice.label) : slice.label;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function CustomTooltip({ active, payload, currency }: any) {
  if (!active || !payload?.length) return null;
  const d = payload[0];
  return (
    <div className="rounded-lg border bg-background px-3 py-2 shadow-sm text-sm">
      <p className="font-medium">{d.name}</p>
      <p className="text-muted-foreground">{fmtCurrency(d.value, currency)}</p>
      <p className="text-muted-foreground text-xs">{d.payload.percentage.toFixed(1)}%</p>
    </div>
  );
}

export function AllocationChart() {
  const [view, setView] = useState<GroupBy>("holding");
  const [editorOpen, setEditorOpen] = useState(false);
  const { mutate: globalMutate } = useSWRConfig();

  const { data, isLoading } = useSWR<AllocationResponse>(
    `/api/portfolio/allocation?by=${view}`,
    fetcher
  );
  const { data: goals } = useSWR<GoalsResponse>("/api/goals", fetcher);

  const currency = data?.baseCurrency ?? "USD";
  const slices = data?.slices ?? [];

  const goalsEnabled = view === "holding" || view === "asset_class";
  const existingGoals = goalsEnabled ? goals?.[view] ?? [] : [];
  const goalMap = new Map(existingGoals.map((g) => [g.key, g.pct]));

  // Options for the editor: held tickers for holding view, the fixed set for asset class.
  const editorOptions: GoalOption[] =
    view === "holding"
      ? slices.map((s) => ({ key: s.key, label: displayTicker(s.label) }))
      : ASSET_CLASSES.map((c) => ({ key: c, label: formatAssetClass(c) }));

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between pb-2">
        <CardTitle className="text-base font-semibold">Allocation</CardTitle>
        <div className="flex items-center gap-2">
          {goalsEnabled && (
            <Button variant="outline" size="sm" onClick={() => setEditorOpen(true)}>
              <Target className="h-3.5 w-3.5 mr-1.5" />
              Set goals
            </Button>
          )}
          <div className="flex gap-1">
            {VIEWS.map((v) => (
              <button
                key={v.key}
                onClick={() => setView(v.key)}
                className={cn(
                  "px-2.5 py-1 rounded text-xs font-medium transition-colors",
                  v.key === view
                    ? "bg-primary text-primary-foreground"
                    : "text-muted-foreground hover:text-foreground hover:bg-muted"
                )}
              >
                {v.label}
              </button>
            ))}
          </div>
        </div>
      </CardHeader>

      <CardContent className="pb-4">
        {isLoading ? (
          <Skeleton className="h-64 w-full" />
        ) : slices.length === 0 ? (
          <div className="h-64 flex items-center justify-center">
            <p className="text-muted-foreground text-sm">No open positions to display.</p>
          </div>
        ) : (
          <div className="flex flex-col gap-6 md:flex-row md:items-start">
            <div className="w-full md:w-64 shrink-0">
              <ResponsiveContainer width="100%" height={220}>
                <PieChart>
                  <Pie
                    data={slices.map((s) => ({ ...s, label: sliceLabel(view, s) }))}
                    dataKey="value"
                    nameKey="label"
                    cx="50%"
                    cy="50%"
                    innerRadius="55%"
                    outerRadius="80%"
                    paddingAngle={2}
                    strokeWidth={0}
                  >
                    {slices.map((_, i) => (
                      <Cell key={i} fill={PALETTE[i % PALETTE.length]} />
                    ))}
                  </Pie>
                  <Tooltip content={<CustomTooltip currency={currency} />} />
                </PieChart>
              </ResponsiveContainer>
            </div>

            <div className="flex-1 min-w-0">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-muted-foreground text-xs border-b">
                    <th className="pb-2 font-medium">Label</th>
                    <th className="pb-2 font-medium text-right">Value</th>
                    <th className="pb-2 font-medium text-right">Weight</th>
                    {goalsEnabled && <th className="pb-2 font-medium text-right">Target</th>}
                    {goalsEnabled && <th className="pb-2 font-medium text-right">Gap</th>}
                  </tr>
                </thead>
                <tbody>
                  {slices.map((s, i) => {
                    const target = goalMap.get(s.key);
                    const gap = target != null ? s.percentage - target : null;
                    return (
                      <tr key={s.key} className="border-b last:border-0">
                        <td className="py-2 flex items-center gap-2 min-w-0">
                          <span
                            className="inline-block w-2.5 h-2.5 rounded-sm shrink-0"
                            style={{ background: PALETTE[i % PALETTE.length] }}
                          />
                          <span className="truncate">{sliceLabel(view, s)}</span>
                        </td>
                        <td className="py-2 text-right tabular-nums">
                          {fmtCurrency(s.value, currency)}
                        </td>
                        <td className="py-2 text-right tabular-nums text-muted-foreground">
                          {s.percentage.toFixed(1)}%
                        </td>
                        {goalsEnabled && (
                          <td className="py-2 text-right tabular-nums text-muted-foreground">
                            {target != null ? `${target.toFixed(1)}%` : "—"}
                          </td>
                        )}
                        {goalsEnabled && (
                          <td className="py-2 text-right tabular-nums">
                            {gap == null ? (
                              <span className="text-muted-foreground">—</span>
                            ) : Math.abs(gap) < 0.05 ? (
                              <span className="text-green-600">on target</span>
                            ) : (
                              <span className={gap > 0 ? "text-amber-600" : "text-blue-600"}>
                                {gap > 0 ? "+" : ""}
                                {gap.toFixed(1)}%
                              </span>
                            )}
                          </td>
                        )}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
              {goalsEnabled && existingGoals.length === 0 && (
                <p className="text-xs text-muted-foreground mt-3">
                  No targets set for this view. Use “Set goals” to define them.
                </p>
              )}
            </div>
          </div>
        )}
      </CardContent>

      {goalsEnabled && editorOpen && (
        <GoalEditor
          key={view}
          open
          onClose={() => setEditorOpen(false)}
          scope={view}
          title={view === "holding" ? "Target allocation by holding" : "Target allocation by asset class"}
          options={editorOptions}
          existing={existingGoals}
          onSaved={() => globalMutate(() => true)}
        />
      )}
    </Card>
  );
}
