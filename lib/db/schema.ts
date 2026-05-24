import { sqliteTable, text, real, integer, primaryKey } from "drizzle-orm/sqlite-core";

export const holdings = sqliteTable("holdings", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  ticker: text("ticker").notNull().unique(),
  name: text("name"),
  sector: text("sector"),
  assetClass: text("asset_class").default("stock"),
  currency: text("currency").default("USD"),
  createdAt: integer("created_at").notNull().default(0),
});

export const priceCache = sqliteTable("price_cache", {
  ticker: text("ticker").primaryKey(),
  price: real("price"),
  currency: text("currency"),
  updatedAt: integer("updated_at").notNull(),
});

export const fxRates = sqliteTable(
  "fx_rates",
  {
    fromCurrency: text("from_currency").notNull(),
    toCurrency: text("to_currency").notNull(),
    rate: real("rate").notNull(),
    fetchedAt: integer("fetched_at").notNull(),
  },
  (t) => [primaryKey({ columns: [t.fromCurrency, t.toCurrency] })]
);

export const portfolioSnapshots = sqliteTable("portfolio_snapshots", {
  date: text("date").primaryKey(), // YYYY-MM-DD
  totalValue: real("total_value").notNull(),
  costBasis: real("cost_basis").notNull(),
  baseCurrency: text("base_currency").notNull(),
  recordedAt: integer("recorded_at").notNull(),
});

export const transactions = sqliteTable("transactions", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  holdingId: integer("holding_id").notNull().references(() => holdings.id),
  type: text("type").notNull(), // buy | sell | dividend | fee
  date: text("date").notNull(), // YYYY-MM-DD
  shares: real("shares"),
  price: real("price"),
  fee: real("fee").notNull().default(0),
  tax: real("tax").notNull().default(0),
  currency: text("currency").notNull().default("USD"),
  notes: text("notes"),
  createdAt: integer("created_at").notNull(),
});
