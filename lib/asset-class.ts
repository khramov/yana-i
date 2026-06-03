export const ASSET_CLASSES = ["stock", "etf", "bond", "cash"] as const;
export type AssetClass = (typeof ASSET_CLASSES)[number];

export function formatAssetClass(raw: string): string {
  switch (raw) {
    case "etf":
      return "ETF";
    case "bond":
      return "Bond";
    case "cash":
      return "Cash";
    default:
      return "Stock";
  }
}
