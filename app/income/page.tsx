import { IncomePage } from "@/components/income/income-page";

export const metadata = { title: "Income — Yana" };

export default function Page() {
  return (
    <main className="flex flex-col gap-6 p-8">
      <h1 className="text-2xl font-semibold">Income</h1>
      <IncomePage />
    </main>
  );
}
