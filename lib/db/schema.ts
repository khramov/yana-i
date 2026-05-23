import { sqliteTable, text, real, integer } from "drizzle-orm/sqlite-core";

export const holdings = sqliteTable("holdings", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  ticker: text("ticker").notNull().unique(),
  name: text("name"),
  createdAt: integer("created_at").notNull().default(0),
});

export const priceCache = sqliteTable("price_cache", {
  ticker: text("ticker").primaryKey(),
  price: real("price"),
  currency: text("currency"),
  updatedAt: integer("updated_at").notNull(),
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
