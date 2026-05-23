"use client";

import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";

interface Props {
  onAdd: (ticker: string) => Promise<void>;
}

export function AddTickerForm({ onAdd }: Props) {
  const [value, setValue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function submit() {
    const ticker = value.trim().toUpperCase();
    if (!ticker) return;
    setLoading(true);
    setError(null);
    try {
      await onAdd(ticker);
      setValue("");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Failed to add ticker");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex flex-col gap-1">
      <div className="flex gap-2">
        <Input
          placeholder="Add ticker (e.g. AAPL)"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && submit()}
          disabled={loading}
          className="uppercase placeholder:normal-case"
        />
        <Button onClick={submit} disabled={loading || !value.trim()} size="icon">
          <Plus className="h-4 w-4" />
        </Button>
      </div>
      {error && <p className="text-sm text-destructive">{error}</p>}
    </div>
  );
}
