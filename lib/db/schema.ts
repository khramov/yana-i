import { sqliteTable, text, real, integer, primaryKey, unique } from "drizzle-orm/sqlite-core";

export const users = sqliteTable("users", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  email: text("email").notNull().unique(),
  passwordHash: text("password_hash").notNull(),
  createdAt: integer("created_at").notNull().default(0),
});

export const sessions = sqliteTable("sessions", {
  token: text("token").primaryKey(),
  userId: integer("user_id").notNull().references(() => users.id),
  expiresAt: integer("expires_at").notNull(),
  createdAt: integer("created_at").notNull(),
});

export const portfolios = sqliteTable("portfolios", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  userId: integer("user_id"),
  name: text("name").notNull(),
  baseCurrency: text("base_currency").notNull().default("EUR"),
  createdAt: integer("created_at").notNull().default(0),
});

export const holdings = sqliteTable(
  "holdings",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    portfolioId: integer("portfolio_id").notNull().default(1),
    ticker: text("ticker").notNull(),
    name: text("name"),
    sector: text("sector"),
    assetClass: text("asset_class").default("stock"),
    currency: text("currency").default("USD"),
    createdAt: integer("created_at").notNull().default(0),
  },
  (t) => [unique().on(t.portfolioId, t.ticker)]
);

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

export const portfolioSnapshots = sqliteTable(
  "portfolio_snapshots",
  {
    portfolioId: integer("portfolio_id").notNull().default(1),
    date: text("date").notNull(), // YYYY-MM-DD
    totalValue: real("total_value").notNull(),
    costBasis: real("cost_basis").notNull(),
    baseCurrency: text("base_currency").notNull(),
    recordedAt: integer("recorded_at").notNull(),
  },
  (t) => [primaryKey({ columns: [t.portfolioId, t.date] })]
);

export const dividendMetadata = sqliteTable("dividend_metadata", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  holdingId: integer("holding_id").notNull().unique().references(() => holdings.id),
  exDivDate: text("ex_div_date"),
  payDate: text("pay_date"),
  amountPerShare: real("amount_per_share"),
  annualDividendRate: real("annual_dividend_rate"),
  frequency: text("frequency"),
  fetchedAt: integer("fetched_at").notNull(),
});

export const transactions = sqliteTable("transactions", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  portfolioId: integer("portfolio_id").notNull().default(1),
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

export const goals = sqliteTable(
  "goals",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    portfolioId: integer("portfolio_id").notNull(),
    scope: text("scope").notNull(), // holding | asset_class
    targetKey: text("target_key").notNull(), // ticker or asset class
    targetPct: real("target_pct").notNull(),
    createdAt: integer("created_at").notNull(),
  },
  (t) => [unique().on(t.portfolioId, t.scope, t.targetKey)]
);
