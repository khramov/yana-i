// Yahoo Finance appends an exchange/MIC suffix after a dot for non-US listings
// (e.g. SXR8.DE on XETRA, EMIM.AS on Amsterdam). We store the full symbol so
// quote lookups keep working, but strip the suffix for display. Share-class
// tickers like BRK.B use a dot too, so we only strip *known* exchange suffixes.
const EXCHANGE_SUFFIXES = new Set([
  // Germany
  "DE", "F", "BE", "BM", "DU", "HM", "HA", "MU", "SG", "STU",
  // Rest of Europe
  "AS", "BR", "PA", "MI", "MC", "LS", "VI", "IR", "L", "SW", "VX", "Z",
  "ST", "HE", "CO", "OL", "IC", "PR", "WA", "AT", "BD", "RG", "TL", "VS",
  // Americas
  "TO", "V", "NE", "CN", "MX", "SA", "BA", "SN",
  // Asia / Pacific / Middle East / Africa
  "HK", "T", "KS", "KQ", "TW", "TWO", "SS", "SZ", "BO", "NS", "SI",
  "AX", "NZ", "JK", "KL", "BK", "SR", "JO", "CA", "TA", "QA", "IS",
]);

export function displayTicker(ticker: string): string {
  const dot = ticker.lastIndexOf(".");
  if (dot <= 0) return ticker;
  const suffix = ticker.slice(dot + 1).toUpperCase();
  return EXCHANGE_SUFFIXES.has(suffix) ? ticker.slice(0, dot) : ticker;
}
