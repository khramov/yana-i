"use client";

import { useRef, useState } from "react";
import { useSWRConfig } from "swr";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Upload } from "lucide-react";

interface ImportResult {
  imported: number;
  failed: number;
  errors: { row: number; message: string }[];
}

export function TransactionImport() {
  const { mutate: globalMutate } = useSWRConfig();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [fileName, setFileName] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<ImportResult | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  function reset() {
    setFileName(null);
    setError(null);
    setResult(null);
  }

  async function onFile(file: File) {
    setBusy(true);
    setError(null);
    setResult(null);
    setFileName(file.name);
    try {
      const csv = await file.text();
      const res = await fetch("/api/transactions/import", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ csv }),
      });
      const json = await res.json();
      if (!res.ok) {
        setError(json.error ?? "Import failed");
        return;
      }
      setResult(json as ImportResult);
      await globalMutate(() => true);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Import failed");
    } finally {
      setBusy(false);
      if (inputRef.current) inputRef.current.value = "";
    }
  }

  return (
    <>
      <Button
        variant="outline"
        onClick={() => {
          reset();
          setOpen(true);
        }}
      >
        <Upload className="w-4 h-4 mr-1.5" />
        Import CSV
      </Button>

      <Dialog open={open} onOpenChange={(v) => !v && setOpen(false)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Import transactions from CSV</DialogTitle>
          </DialogHeader>

          <div className="flex flex-col gap-3 text-sm">
            <p className="text-muted-foreground">
              Columns: <code className="text-foreground">ticker, type, date, shares, price, fee, tax, currency, notes</code>.
              {" "}
              <span className="text-foreground">ticker</span>,{" "}
              <span className="text-foreground">type</span> (buy/sell/dividend/fee) and{" "}
              <span className="text-foreground">date</span> (YYYY-MM-DD) are required.
              Rows import into the active portfolio; unknown tickers are added automatically.
            </p>

            <input
              ref={inputRef}
              type="file"
              accept=".csv,text/csv"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) onFile(f);
              }}
            />
            <Button
              variant="secondary"
              disabled={busy}
              onClick={() => inputRef.current?.click()}
            >
              {busy ? "Importing…" : fileName ? `Choose another file (${fileName})` : "Choose CSV file"}
            </Button>

            {error && <p className="text-destructive">{error}</p>}

            {result && (
              <div className="rounded-md border p-3">
                <p className="font-medium">
                  Imported {result.imported} transaction{result.imported === 1 ? "" : "s"}
                  {result.failed > 0 ? `, ${result.failed} skipped` : ""}.
                </p>
                {result.errors.length > 0 && (
                  <ul className="mt-2 max-h-40 overflow-y-auto text-xs text-muted-foreground space-y-0.5">
                    {result.errors.map((er, i) => (
                      <li key={i}>
                        Row {er.row}: {er.message}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>
              {result ? "Done" : "Cancel"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
