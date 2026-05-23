"use client";

import { useState } from "react";
import useSWR from "swr";
import { TransactionForm } from "./transaction-form";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Pencil, Trash2, Plus } from "lucide-react";

interface Holding {
  id: number;
  ticker: string;
  name: string | null;
}

interface TransactionRow {
  id: number;
  holdingId: number;
  type: string;
  date: string;
  shares: number | null;
  price: number | null;
  fee: number;
  tax: number;
  currency: string;
  notes: string | null;
  total: number;
  holding: Holding | null;
}

const fetcher = (url: string) => fetch(url).then((r) => r.json());

const TYPE_COLORS: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
  buy: "default",
  sell: "destructive",
  dividend: "secondary",
  fee: "outline",
};

function fmt(n: number | null, currency = "USD") {
  if (n == null) return "—";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 4,
  }).format(n);
}

function buildUrl(type: string, from: string, to: string) {
  const params = new URLSearchParams();
  if (type && type !== "all") params.set("type", type);
  if (from) params.set("from", from);
  if (to) params.set("to", to);
  const qs = params.toString();
  return `/api/transactions${qs ? `?${qs}` : ""}`;
}

export function TransactionTable() {
  const [typeFilter, setTypeFilter] = useState("all");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");

  const [sheetOpen, setSheetOpen] = useState(false);
  const [editing, setEditing] = useState<TransactionRow | null>(null);
  const [deleting, setDeleting] = useState<TransactionRow | null>(null);
  const [deleteLoading, setDeleteLoading] = useState(false);

  const url = buildUrl(typeFilter, fromDate, toDate);
  const { data: rows, isLoading, mutate } = useSWR<TransactionRow[]>(url, fetcher);
  const { data: holdings } = useSWR<Holding[]>("/api/holdings", fetcher);

  function openAdd() {
    setEditing(null);
    setSheetOpen(true);
  }

  function openEdit(row: TransactionRow) {
    setEditing(row);
    setSheetOpen(true);
  }

  async function confirmDelete() {
    if (!deleting) return;
    setDeleteLoading(true);
    await fetch(`/api/transactions/${deleting.id}`, { method: "DELETE" });
    setDeleteLoading(false);
    setDeleting(null);
    mutate();
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-3">
        <Select value={typeFilter} onValueChange={(v) => setTypeFilter(v ?? "all")}>
          <SelectTrigger className="w-36">
            <SelectValue placeholder="All types" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All types</SelectItem>
            <SelectItem value="buy">Buy</SelectItem>
            <SelectItem value="sell">Sell</SelectItem>
            <SelectItem value="dividend">Dividend</SelectItem>
            <SelectItem value="fee">Fee</SelectItem>
          </SelectContent>
        </Select>

        <Input
          type="date"
          className="w-40"
          value={fromDate}
          onChange={(e) => setFromDate(e.target.value)}
          placeholder="From"
        />
        <Input
          type="date"
          className="w-40"
          value={toDate}
          onChange={(e) => setToDate(e.target.value)}
          placeholder="To"
        />

        <Button className="ml-auto" onClick={openAdd}>
          <Plus className="w-4 h-4 mr-1.5" />
          Add transaction
        </Button>
      </div>

      <div className="rounded-lg border overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b bg-muted/40 text-muted-foreground">
              <th className="text-left px-4 py-3 font-medium">Type</th>
              <th className="text-left px-4 py-3 font-medium">Holding</th>
              <th className="text-left px-4 py-3 font-medium">Date</th>
              <th className="text-right px-4 py-3 font-medium">Shares</th>
              <th className="text-right px-4 py-3 font-medium">Price</th>
              <th className="text-right px-4 py-3 font-medium">Fee</th>
              <th className="text-right px-4 py-3 font-medium">Tax</th>
              <th className="text-right px-4 py-3 font-medium">Total</th>
              <th className="text-left px-4 py-3 font-medium">Notes</th>
              <th className="px-4 py-3" />
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              Array.from({ length: 4 }).map((_, i) => (
                <tr key={i} className="border-b">
                  {Array.from({ length: 10 }).map((_, j) => (
                    <td key={j} className="px-4 py-3">
                      <Skeleton className="h-4 w-full" />
                    </td>
                  ))}
                </tr>
              ))
            ) : !rows || rows.length === 0 ? (
              <tr>
                <td
                  colSpan={10}
                  className="px-4 py-12 text-center text-muted-foreground"
                >
                  No transactions yet. Add one to get started.
                </td>
              </tr>
            ) : (
              rows.map((row) => (
                <tr key={row.id} className="border-b hover:bg-muted/20 transition-colors">
                  <td className="px-4 py-3">
                    <Badge variant={TYPE_COLORS[row.type] ?? "outline"}>
                      {row.type}
                    </Badge>
                  </td>
                  <td className="px-4 py-3 font-medium">
                    {row.holding?.ticker ?? `#${row.holdingId}`}
                  </td>
                  <td className="px-4 py-3 tabular-nums">{row.date}</td>
                  <td className="px-4 py-3 text-right tabular-nums">
                    {row.shares != null ? row.shares.toLocaleString() : "—"}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums font-mono">
                    {fmt(row.price, row.currency)}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums font-mono">
                    {fmt(row.fee, row.currency)}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums font-mono">
                    {row.tax > 0 ? fmt(row.tax, row.currency) : "—"}
                  </td>
                  <td className="px-4 py-3 text-right tabular-nums font-mono font-medium">
                    {fmt(row.total, row.currency)}
                  </td>
                  <td className="px-4 py-3 text-muted-foreground max-w-[160px] truncate">
                    {row.notes ?? ""}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1 justify-end">
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => openEdit(row)}
                        className="h-7 w-7"
                      >
                        <Pencil className="w-3.5 h-3.5" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => setDeleting(row)}
                        className="h-7 w-7 text-destructive hover:text-destructive"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </Button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <TransactionForm
        open={sheetOpen}
        onClose={() => setSheetOpen(false)}
        holdings={holdings ?? []}
        editing={editing}
        onSaved={() => mutate()}
      />

      <Dialog open={!!deleting} onOpenChange={(v) => !v && setDeleting(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete transaction?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            This will permanently remove the{" "}
            <span className="font-medium">{deleting?.type}</span> transaction for{" "}
            <span className="font-medium">
              {deleting?.holding?.ticker ?? `#${deleting?.holdingId}`}
            </span>{" "}
            on {deleting?.date}. This action cannot be undone.
          </p>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setDeleting(null)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={confirmDelete}
              disabled={deleteLoading}
            >
              {deleteLoading ? "Deleting…" : "Delete"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
