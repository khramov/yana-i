"use client";

import useSWR, { useSWRConfig } from "swr";
import { useState } from "react";
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
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Plus, Settings } from "lucide-react";
import {
  SUPPORTED_CURRENCIES,
  CURRENCY_LABELS,
  DEFAULT_CURRENCY,
} from "@/lib/currencies";

interface Portfolio {
  id: number;
  name: string;
  baseCurrency: string;
}

interface PortfoliosResponse {
  portfolios: Portfolio[];
  currentId: number;
}

const fetcher = (url: string) => fetch(url).then((r) => r.json());

function setPortfolioCookie(id: number) {
  document.cookie = `portfolioId=${id}; path=/; max-age=${60 * 60 * 24 * 365}`;
}

function CurrencySelect({
  value,
  onChange,
}: {
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <Select value={value} onValueChange={(v) => v && onChange(v)}>
      <SelectTrigger>
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
  );
}

export function PortfolioSwitcher() {
  const { data } = useSWR<PortfoliosResponse>("/api/portfolios", fetcher);
  const { mutate: globalMutate } = useSWRConfig();

  const portfolios = data?.portfolios ?? [];
  const currentId = data?.currentId;
  const current = portfolios.find((p) => p.id === currentId) ?? null;

  const [createOpen, setCreateOpen] = useState(false);
  const [newName, setNewName] = useState("");
  const [newCurrency, setNewCurrency] = useState<string>(DEFAULT_CURRENCY);
  const [busy, setBusy] = useState(false);

  const [manageOpen, setManageOpen] = useState(false);
  const [editName, setEditName] = useState("");
  const [editCurrency, setEditCurrency] = useState<string>(DEFAULT_CURRENCY);

  function revalidateAll() {
    // Revalidate every SWR key so all data reflects the active portfolio.
    return globalMutate(() => true);
  }

  async function selectPortfolio(idStr: string | null) {
    if (!idStr) return;
    const id = parseInt(idStr, 10);
    if (Number.isNaN(id) || id === currentId) return;
    setPortfolioCookie(id);
    await revalidateAll();
  }

  async function createPortfolio() {
    if (!newName.trim()) return;
    setBusy(true);
    try {
      const res = await fetch("/api/portfolios", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: newName.trim(), baseCurrency: newCurrency }),
      });
      if (res.ok) {
        const created: Portfolio = await res.json();
        setPortfolioCookie(created.id);
        await revalidateAll();
        setCreateOpen(false);
        setNewName("");
        setNewCurrency(DEFAULT_CURRENCY);
      }
    } finally {
      setBusy(false);
    }
  }

  function openManage() {
    if (!current) return;
    setEditName(current.name);
    setEditCurrency(current.baseCurrency);
    setManageOpen(true);
  }

  async function saveManage() {
    if (!current) return;
    setBusy(true);
    try {
      const res = await fetch(`/api/portfolios/${current.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: editName.trim(), baseCurrency: editCurrency }),
      });
      if (res.ok) {
        await revalidateAll();
        setManageOpen(false);
      }
    } finally {
      setBusy(false);
    }
  }

  async function deletePortfolio() {
    if (!current || portfolios.length <= 1) return;
    setBusy(true);
    try {
      const res = await fetch(`/api/portfolios/${current.id}`, { method: "DELETE" });
      if (res.ok) {
        const { fallbackId } = await res.json();
        if (fallbackId) setPortfolioCookie(fallbackId);
        await revalidateAll();
        setManageOpen(false);
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex items-center gap-1.5">
      <Select value={current ? String(current.id) : ""} onValueChange={selectPortfolio}>
        <SelectTrigger className="h-8 w-auto min-w-[10rem] gap-2">
          <SelectValue placeholder="Portfolio…" />
        </SelectTrigger>
        <SelectContent>
          {portfolios.map((p) => (
            <SelectItem key={p.id} value={String(p.id)}>
              {p.name} · {p.baseCurrency}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Button
        variant="ghost"
        size="icon"
        className="h-8 w-8"
        title="New portfolio"
        onClick={() => setCreateOpen(true)}
      >
        <Plus className="h-4 w-4" />
      </Button>
      <Button
        variant="ghost"
        size="icon"
        className="h-8 w-8"
        title="Portfolio settings"
        onClick={openManage}
      >
        <Settings className="h-4 w-4" />
      </Button>

      <Dialog open={createOpen} onOpenChange={(v) => !v && setCreateOpen(false)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>New portfolio</DialogTitle>
          </DialogHeader>
          <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="pf-name">Name</Label>
              <Input
                id="pf-name"
                placeholder="e.g. Retirement"
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && createPortfolio()}
                autoFocus
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Base currency</Label>
              <CurrencySelect value={newCurrency} onChange={setNewCurrency} />
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setCreateOpen(false)}>
              Cancel
            </Button>
            <Button onClick={createPortfolio} disabled={busy || !newName.trim()}>
              {busy ? "Creating…" : "Create"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={manageOpen} onOpenChange={(v) => !v && setManageOpen(false)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Portfolio settings</DialogTitle>
          </DialogHeader>
          <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="pf-edit-name">Name</Label>
              <Input
                id="pf-edit-name"
                value={editName}
                onChange={(e) => setEditName(e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Base currency</Label>
              <CurrencySelect value={editCurrency} onChange={setEditCurrency} />
            </div>
          </div>
          <DialogFooter className="flex-col gap-2 sm:flex-row sm:justify-between">
            <Button
              variant="destructive"
              onClick={deletePortfolio}
              disabled={busy || portfolios.length <= 1}
              title={portfolios.length <= 1 ? "Cannot delete the last portfolio" : undefined}
            >
              Delete
            </Button>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setManageOpen(false)}>
                Cancel
              </Button>
              <Button onClick={saveManage} disabled={busy || !editName.trim()}>
                {busy ? "Saving…" : "Save"}
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
