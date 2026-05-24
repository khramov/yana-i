import { GrowthChart } from "@/components/analytics/growth-chart";
import { AllocationChart } from "@/components/analytics/allocation-chart";

export const metadata = { title: "Analytics — Yana" };

export default function Page() {
  return (
    <main className="flex flex-col gap-6 p-8">
      <h1 className="text-2xl font-semibold">Analytics</h1>
      <GrowthChart />
      <AllocationChart />
    </main>
  );
}
