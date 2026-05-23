import { Skeleton } from "@/components/ui/skeleton";

export function WatchlistSkeleton() {
  return (
    <div className="flex flex-col divide-y">
      {Array.from({ length: 3 }).map((_, i) => (
        <div key={i} className="flex items-center justify-between py-3">
          <div className="flex flex-col gap-1">
            <Skeleton className="h-4 w-14" />
            <Skeleton className="h-3 w-28" />
          </div>
          <Skeleton className="h-4 w-16" />
        </div>
      ))}
    </div>
  );
}
