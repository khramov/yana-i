import { DividendCalendar } from "@/components/dividends/dividend-calendar";

export const metadata = { title: "Dividend Calendar — Yana" };

export default function Page() {
  return (
    <main className="flex flex-col gap-6 p-8">
      <h1 className="text-2xl font-semibold">Dividend Calendar</h1>
      <DividendCalendar />
    </main>
  );
}
