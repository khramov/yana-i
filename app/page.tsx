import { PortfolioSummary } from "@/components/dashboard/portfolio-summary";
import { WatchlistWidget } from "@/components/watchlist/watchlist-widget";

export default function Home() {
  return (
    <main className="min-h-screen p-8">
      <div className="max-w-5xl mx-auto space-y-8">
        <h1 className="text-2xl font-bold">Dashboard</h1>
        <PortfolioSummary />
        <WatchlistWidget />
      </div>
    </main>
  );
}
