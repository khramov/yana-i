import { HoldingsTable } from "@/components/holdings/holdings-table";

export const metadata = { title: "Holdings — Yana" };

export default function HoldingsPage() {
  return (
    <main className="flex flex-col gap-6 p-8">
      <h1 className="text-2xl font-semibold">Holdings</h1>
      <HoldingsTable />
    </main>
  );
}
