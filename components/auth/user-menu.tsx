"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { LogOut } from "lucide-react";

export function UserMenu({ email }: { email: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function logout() {
    setBusy(true);
    try {
      await fetch("/api/auth/logout", { method: "POST" });
      router.replace("/login");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex items-center gap-2">
      <Link
        href="/settings"
        className="text-muted-foreground hover:text-foreground transition-colors max-w-[14rem] truncate"
        title={`${email} — account settings`}
      >
        {email}
      </Link>
      <Button
        variant="ghost"
        size="icon"
        className="h-8 w-8"
        title="Log out"
        onClick={logout}
        disabled={busy}
      >
        <LogOut className="h-4 w-4" />
      </Button>
    </div>
  );
}
