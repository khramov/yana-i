"use client";

import { useEffect } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { transactionSchema, type TransactionInput } from "@/lib/validations";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { SUPPORTED_CURRENCIES, CURRENCY_LABELS, DEFAULT_CURRENCY } from "@/lib/currencies";
import { displayTicker } from "@/lib/ticker";

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
}

interface TransactionFormProps {
  open: boolean;
  onClose: () => void;
  holdings: Holding[];
  editing: TransactionRow | null;
  onSaved: () => void;
}

export function TransactionForm({
  open,
  onClose,
  holdings,
  editing,
  onSaved,
}: TransactionFormProps) {
  const {
    register,
    handleSubmit,
    watch,
    setValue,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<TransactionInput>({
    resolver: zodResolver(transactionSchema),
    defaultValues: {
      type: "buy",
      date: new Date().toISOString().slice(0, 10),
      fee: 0,
      tax: 0,
      currency: DEFAULT_CURRENCY,
    },
  });

  const txType = watch("type");
  const showShares = txType === "buy" || txType === "sell";
  const showPrice = txType === "buy" || txType === "sell" || txType === "dividend";
  const showTax = txType === "dividend";

  useEffect(() => {
    if (editing) {
      reset({
        holdingId: editing.holdingId,
        type: editing.type as TransactionInput["type"],
        date: editing.date,
        shares: editing.shares ?? undefined,
        price: editing.price ?? undefined,
        fee: editing.fee,
        tax: editing.tax,
        currency: editing.currency,
        notes: editing.notes ?? undefined,
      });
    } else {
      reset({
        type: "buy",
        date: new Date().toISOString().slice(0, 10),
        fee: 0,
        tax: 0,
        currency: "USD",
      });
    }
  }, [editing, reset, open]);

  async function onSubmit(data: TransactionInput) {
    const url = editing ? `/api/transactions/${editing.id}` : "/api/transactions";
    const method = editing ? "PUT" : "POST";
    const res = await fetch(url, {
      method,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data),
    });
    if (res.ok) {
      onSaved();
      onClose();
    }
  }

  return (
    <Sheet open={open} onOpenChange={(v) => !v && onClose()}>
      <SheetContent className="w-full sm:max-w-md overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{editing ? "Edit Transaction" : "Add Transaction"}</SheetTitle>
        </SheetHeader>

        <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-5 mt-6">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="holdingId">Holding</Label>
            <Select
              value={watch("holdingId")?.toString() ?? null}
              onValueChange={(v) => v && setValue("holdingId", parseInt(v, 10))}
            >
              <SelectTrigger id="holdingId">
                <SelectValue placeholder="Select ticker…" />
              </SelectTrigger>
              <SelectContent>
                {holdings.map((h) => (
                  <SelectItem key={h.id} value={h.id.toString()}>
                    {displayTicker(h.ticker)} {h.name ? `— ${h.name}` : ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.holdingId && (
              <p className="text-xs text-destructive">{errors.holdingId.message}</p>
            )}
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="type">Type</Label>
            <Select
              value={txType ?? null}
              onValueChange={(v) => v && setValue("type", v as TransactionInput["type"])}
            >
              <SelectTrigger id="type">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="buy">Buy</SelectItem>
                <SelectItem value="sell">Sell</SelectItem>
                <SelectItem value="dividend">Dividend</SelectItem>
                <SelectItem value="fee">Fee</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="date">Date</Label>
            <Input id="date" type="date" {...register("date")} />
            {errors.date && (
              <p className="text-xs text-destructive">{errors.date.message}</p>
            )}
          </div>

          {showShares && (
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="shares">Shares</Label>
              <Input
                id="shares"
                type="number"
                step="any"
                placeholder="0"
                {...register("shares", { valueAsNumber: true })}
              />
              {errors.shares && (
                <p className="text-xs text-destructive">{errors.shares.message}</p>
              )}
            </div>
          )}

          {showPrice && (
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="price">
                {txType === "dividend" ? "Amount" : "Price per share"}
              </Label>
              <Input
                id="price"
                type="number"
                step="any"
                placeholder="0.00"
                {...register("price", { valueAsNumber: true })}
              />
              {errors.price && (
                <p className="text-xs text-destructive">{errors.price.message}</p>
              )}
            </div>
          )}

          <div className="flex gap-3">
            <div className="flex flex-col gap-1.5 flex-1">
              <Label htmlFor="fee">Fee</Label>
              <Input
                id="fee"
                type="number"
                step="any"
                placeholder="0.00"
                {...register("fee", { valueAsNumber: true })}
              />
            </div>

            {showTax && (
              <div className="flex flex-col gap-1.5 flex-1">
                <Label htmlFor="tax">Tax withheld</Label>
                <Input
                  id="tax"
                  type="number"
                  step="any"
                  placeholder="0.00"
                  {...register("tax", { valueAsNumber: true })}
                />
              </div>
            )}
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="currency">Currency</Label>
            <Select
              value={watch("currency") ?? DEFAULT_CURRENCY}
              onValueChange={(v) => v && setValue("currency", v)}
            >
              <SelectTrigger id="currency">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {SUPPORTED_CURRENCIES.map((c) => (
                  <SelectItem key={c} value={c}>
                    {CURRENCY_LABELS[c] ?? c}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="notes">Notes</Label>
            <Input id="notes" placeholder="Optional…" {...register("notes")} />
          </div>

          <div className="flex gap-3 pt-2">
            <Button type="submit" disabled={isSubmitting} className="flex-1">
              {isSubmitting ? "Saving…" : editing ? "Save changes" : "Add transaction"}
            </Button>
            <Button type="button" variant="outline" onClick={onClose}>
              Cancel
            </Button>
          </div>
        </form>
      </SheetContent>
    </Sheet>
  );
}
