export const SUPPORTED_CURRENCIES = ["EUR", "USD", "RUB"] as const;
export type SupportedCurrency = (typeof SUPPORTED_CURRENCIES)[number];
export const DEFAULT_CURRENCY: SupportedCurrency = "EUR";

export const CURRENCY_LABELS: Record<string, string> = {
  EUR: "EUR — Euro",
  USD: "USD — US Dollar",
  RUB: "RUB — Russian Ruble",
};

export function isSupportedCurrency(value: unknown): value is SupportedCurrency {
  return typeof value === "string" && (SUPPORTED_CURRENCIES as readonly string[]).includes(value);
}
