import { DividendsPage } from "@/components/dividends/dividends-page";

export const metadata = { title: "Dividends — Yana" };

export default function Page() {
  return (
    <main className="flex flex-col gap-6 p-8">
      <h1 className="text-2xl font-semibold">Dividends</h1>
      <DividendsPage />
    </main>
  );
}
