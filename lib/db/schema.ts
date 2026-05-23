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
