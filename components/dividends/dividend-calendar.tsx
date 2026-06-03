"use client";

import useSWR from "swr";
import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { displayTicker } from "@/lib/ticker";

interface UpcomingEvent {
  ticker: string;
  name: string | null;
  exDivDate: string | null;
  payDate: string | null;
  amountPerShare: number;
  frequency: string | null;
  sharesHeld: number;
  estimatedIncomeNative: number;
  estimatedIncomeBase: number;
  currency: string;
  isUpcoming: boolean;
}

interface UpcomingResponse {
  baseCurrency: string;
  events: UpcomingEvent[];
}

const fetcher = (url: string) => fetch(url).then((r) => r.json());

function fmt(n: number, currency: string) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(n);
}

const DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

function buildCalendarDays(year: number, month: number) {
  const firstDay = new Date(year, month, 1).getDay(); // 0=Sun
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const cells: (number | null)[] = Array(firstDay).fill(null);
  for (let d = 1; d <= daysInMonth; d++) cells.push(d);
  while (cells.length % 7 !== 0) cells.push(null);
  return cells;
}

function toYMD(year: number, month: number, day: number): string {
  return `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

export function DividendCalendar() {
  const today = new Date();
  const [viewYear, setViewYear] = useState(today.getFullYear());
  const [viewMonth, setViewMonth] = useState(today.getMonth());
  const [selected, setSelected] = useState<string | null>(null);

  const { data, isLoading } = useSWR<UpcomingResponse>("/api/dividends/upcoming", fetcher);

  const events = data?.events ?? [];
  const baseCurrency = data?.baseCurrency ?? "USD";

  // Build maps: date → events
  const exDivMap = new Map<string, UpcomingEvent[]>();
  const payMap = new Map<string, UpcomingEvent[]>();
  for (const e of events) {
    if (e.exDivDate) {
      const list = exDivMap.get(e.exDivDate) ?? [];
      list.push(e);
      exDivMap.set(e.exDivDate, list);
    }
    if (e.payDate) {
      const list = payMap.get(e.payDate) ?? [];
      list.push(e);
      payMap.set(e.payDate, list);
    }
  }

  const cells = buildCalendarDays(viewYear, viewMonth);
  const todayStr = today.toISOString().slice(0, 10);

  function navigate(delta: number) {
    let m = viewMonth + delta;
    let y = viewYear;
    if (m < 0) { m = 11; y--; }
    if (m > 11) { m = 0; y++; }
    setViewMonth(m);
    setViewYear(y);
    setSelected(null);
  }

  const selectedExDiv = selected ? exDivMap.get(selected) ?? [] : [];
  const selectedPay = selected ? payMap.get(selected) ?? [] : [];
  const selectedAll = [...selectedExDiv.map(e => ({ ...e, type: "ex-div" as const })),
                       ...selectedPay.map(e => ({ ...e, type: "pay" as const }))];

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-base font-semibold">
            {MONTH_NAMES[viewMonth]} {viewYear}
          </CardTitle>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => navigate(-1)}>‹</Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => { setViewYear(today.getFullYear()); setViewMonth(today.getMonth()); }}
            >
              Today
            </Button>
            <Button variant="outline" size="sm" onClick={() => navigate(1)}>›</Button>
          </div>
        </CardHeader>
        <CardContent className="pb-4">
          {isLoading ? (
            <Skeleton className="h-64 w-full" />
          ) : (
            <>
              {/* Legend */}
              <div className="flex gap-4 mb-3 text-xs text-muted-foreground">
                <span className="flex items-center gap-1">
                  <span className="inline-block w-2.5 h-2.5 rounded-sm bg-amber-400" />
                  Ex-dividend
                </span>
                <span className="flex items-center gap-1">
                  <span className="inline-block w-2.5 h-2.5 rounded-sm bg-emerald-500" />
                  Pay date
                </span>
              </div>

              {/* Day headers */}
              <div className="grid grid-cols-7 mb-1">
                {DAY_NAMES.map((d) => (
                  <div key={d} className="text-center text-xs font-medium text-muted-foreground py-1">
                    {d}
                  </div>
                ))}
              </div>

              {/* Calendar grid */}
              <div className="grid grid-cols-7 border-l border-t">
                {cells.map((day, i) => {
                  const dateStr = day ? toYMD(viewYear, viewMonth, day) : null;
                  const isToday = dateStr === todayStr;
                  const hasEx = dateStr ? exDivMap.has(dateStr) : false;
                  const hasPay = dateStr ? payMap.has(dateStr) : false;
                  const isSelected = dateStr === selected;

                  return (
                    <div
                      key={i}
                      onClick={() => {
                        if (dateStr && (hasEx || hasPay)) {
                          setSelected(isSelected ? null : dateStr);
                        }
                      }}
                      className={cn(
                        "border-r border-b min-h-[72px] p-1.5 flex flex-col",
                        day && (hasEx || hasPay) && "cursor-pointer hover:bg-muted/50",
                        isSelected && "bg-muted/70",
                        !day && "bg-muted/20"
                      )}
                    >
                      {day && (
                        <>
                          <span
                            className={cn(
                              "text-xs font-medium w-6 h-6 flex items-center justify-center rounded-full self-end",
                              isToday && "bg-primary text-primary-foreground"
                            )}
                          >
                            {day}
                          </span>
                          <div className="flex flex-col gap-0.5 mt-1">
                            {hasEx && (exDivMap.get(dateStr!)!).map((e) => (
                              <span
                                key={`ex-${e.ticker}`}
                                className="text-[10px] bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300 rounded px-1 truncate"
                              >
                                EX {displayTicker(e.ticker)}
                              </span>
                            ))}
                            {hasPay && (payMap.get(dateStr!)!).map((e) => (
                              <span
                                key={`pay-${e.ticker}`}
                                className="text-[10px] bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-300 rounded px-1 truncate"
                              >
                                PAY {displayTicker(e.ticker)}
                              </span>
                            ))}
                          </div>
                        </>
                      )}
                    </div>
                  );
                })}
              </div>

              {/* Selected day detail */}
              {selected && selectedAll.length > 0 && (
                <div className="mt-4 rounded-lg border p-4">
                  <p className="text-sm font-medium mb-3">{selected}</p>
                  <div className="flex flex-col gap-3">
                    {selectedAll.map((e, i) => (
                      <div key={i} className="flex items-start justify-between gap-4 text-sm">
                        <div>
                          <span
                            className={cn(
                              "text-xs font-medium rounded px-1.5 py-0.5 mr-2",
                              e.type === "ex-div"
                                ? "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300"
                                : "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-300"
                            )}
                          >
                            {e.type === "ex-div" ? "EX-DIV" : "PAY"}
                          </span>
                          <span className="font-medium">{displayTicker(e.ticker)}</span>
                          {e.name && (
                            <span className="text-muted-foreground ml-2 text-xs">{e.name}</span>
                          )}
                        </div>
                        <div className="text-right shrink-0">
                          {e.amountPerShare > 0 && (
                            <p className="font-medium">
                              {fmt(e.amountPerShare, e.currency)}/share
                            </p>
                          )}
                          {e.estimatedIncomeBase > 0 && (
                            <p className="text-muted-foreground text-xs">
                              ≈ {fmt(e.estimatedIncomeBase, baseCurrency)} est.
                            </p>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {events.length === 0 && (
                <p className="text-muted-foreground text-sm text-center py-4">
                  No dividend metadata loaded. Click &quot;Refresh Estimates&quot; on the Income page.
                </p>
              )}
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
