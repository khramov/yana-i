"use client";

import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";

export interface GoalOption {
  key: string;
  label: string;
}

interface GoalEditorProps {
  open: boolean;
  onClose: () => void;
  scope: "holding" | "asset_class";
  title: string;
  options: GoalOption[];
  existing: { key: string; pct: number }[];
  onSaved: () => void;
}

export function GoalEditor({
  open,
  onClose,
  scope,
  title,
  options,
  existing,
  onSaved,
}: GoalEditorProps) {
  // Parent passes a changing `key` so this remounts when opened, seeding fresh state.
  const [values, setValues] = useState<Record<string, string>>(() => {
    const seed: Record<string, string> = {};
    for (const o of options) {
      const hit = existing.find((e) => e.key === o.key);
      seed[o.key] = hit ? String(hit.pct) : "";
    }
    return seed;
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const sum = Object.values(values).reduce((a, v) => a + (parseFloat(v) || 0), 0);
  const allEmpty = Object.values(values).every((v) => v.trim() === "" || parseFloat(v) === 0);
  const canSave = allEmpty || Math.abs(sum - 100) < 0.5;

  async function save() {
    setBusy(true);
    setError(null);
    try {
      const targets = Object.entries(values)
        .map(([key, v]) => ({ key, pct: parseFloat(v) || 0 }))
        .filter((t) => t.pct > 0);
      const res = await fetch("/api/goals", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ scope, targets }),
      });
      if (!res.ok) {
        const json = await res.json().catch(() => ({}));
        setError(json.error ?? "Failed to save goals");
        return;
      }
      onSaved();
      onClose();
    } finally {
      setBusy(false);
    }
  }

  function distributeEvenly() {
    const n = options.length;
    if (n === 0) return;
    const base = Math.floor((100 / n) * 10) / 10;
    const seed: Record<string, string> = {};
    options.forEach((o, i) => {
      // Put the rounding remainder on the first row so the total is exactly 100.
      seed[o.key] = i === 0 ? String(Math.round((100 - base * (n - 1)) * 10) / 10) : String(base);
    });
    setValues(seed);
  }

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
        </DialogHeader>

        <div className="flex flex-col gap-2 max-h-[55vh] overflow-y-auto pr-1">
          {options.length === 0 ? (
            <p className="text-sm text-muted-foreground py-4">
              Nothing to set targets for yet. Add holdings to this portfolio first.
            </p>
          ) : (
            options.map((o) => (
              <div key={o.key} className="flex items-center gap-3">
                <Label className="flex-1 truncate text-sm font-normal">{o.label}</Label>
                <div className="flex items-center gap-1">
                  <Input
                    type="number"
                    step="any"
                    min="0"
                    max="100"
                    className="w-24 text-right"
                    value={values[o.key] ?? ""}
                    onChange={(e) => setValues((s) => ({ ...s, [o.key]: e.target.value }))}
                  />
                  <span className="text-sm text-muted-foreground">%</span>
                </div>
              </div>
            ))
          )}
        </div>

        <div className="flex items-center justify-between border-t pt-3 text-sm">
          <button
            type="button"
            onClick={distributeEvenly}
            className="text-muted-foreground hover:text-foreground underline-offset-2 hover:underline"
          >
            Distribute evenly
          </button>
          <span className={cn("font-medium tabular-nums", canSave ? "text-green-600" : "text-destructive")}>
            Total: {sum.toFixed(1)}%
          </span>
        </div>

        {error && <p className="text-sm text-destructive">{error}</p>}

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={save} disabled={busy || !canSave}>
            {busy ? "Saving…" : allEmpty ? "Clear goals" : "Save goals"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
