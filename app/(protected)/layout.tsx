import Link from "next/link";
import { redirect } from "next/navigation";
import { getSessionUser } from "@/lib/auth";
import { PortfolioSwitcher } from "@/components/portfolio/portfolio-switcher";
import { UserMenu } from "@/components/auth/user-menu";

export default async function ProtectedLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  // Authoritative auth check: validates the session against the DB (catches
  // expired/invalid cookies that the edge middleware can't verify).
  const user = await getSessionUser();
  if (!user) redirect("/login");

  return (
    <>
      <nav className="border-b px-8 py-3 flex items-center gap-6 text-sm">
        <span className="font-semibold text-base">Yana</span>
        <Link href="/" className="text-muted-foreground hover:text-foreground transition-colors">
          Dashboard
        </Link>
        <Link href="/transactions" className="text-muted-foreground hover:text-foreground transition-colors">
          Transactions
        </Link>
        <Link href="/holdings" className="text-muted-foreground hover:text-foreground transition-colors">
          Holdings
        </Link>
        <Link href="/dividends" className="text-muted-foreground hover:text-foreground transition-colors">
          Dividends
        </Link>
        <Link href="/analytics" className="text-muted-foreground hover:text-foreground transition-colors">
          Analytics
        </Link>
        <Link href="/income" className="text-muted-foreground hover:text-foreground transition-colors">
          Income
        </Link>
        <Link href="/dividends/calendar" className="text-muted-foreground hover:text-foreground transition-colors">
          Calendar
        </Link>
        <div className="ml-auto flex items-center gap-4">
          <PortfolioSwitcher />
          <UserMenu email={user.email} />
        </div>
      </nav>
      {children}
    </>
  );
}
